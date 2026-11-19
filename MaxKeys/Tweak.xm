#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

static NSURL *sharedFolder;
static BOOL setFolder(NSURL *url) {
    if (!url || ![url startAccessingSecurityScopedResource]) return NO;
    NSURL *archive=[url URLByAppendingPathComponent:@"MaxKeys Archive" isDirectory:YES];
    if(![NSFileManager.defaultManager createDirectoryAtURL:archive withIntermediateDirectories:YES attributes:nil error:nil]){
        [url stopAccessingSecurityScopedResource];return NO;
    }
    [sharedFolder stopAccessingSecurityScopedResource]; sharedFolder=url; return YES;
}
static NSString *shelfPath(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSData *bookmark=[NSUserDefaults.standardUserDefaults dataForKey:@"MaxKeys.folder"];
        if(bookmark && !sharedFolder){
            BOOL stale=NO;
            NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
            if(setFolder(url) && stale){
                NSData *fresh=[url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
                if(fresh)[NSUserDefaults.standardUserDefaults setObject:fresh forKey:@"MaxKeys.folder"];
            }
        }
    });
    if(sharedFolder)return [[sharedFolder URLByAppendingPathComponent:@"MaxKeys Archive"] path];
    NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    return [base stringByAppendingPathComponent:@"MaxKeys"];
}
static NSFileManager *fm(void) { return NSFileManager.defaultManager; }
static BOOL ready(void) {
    return [fm() createDirectoryAtPath:shelfPath() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
}
static void record(NSData *data, NSString *ext) {
    if (!data.length || !ready()) return;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *key=[NSMutableString new];
    for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [key appendFormat:@"%02x",digest[i]];
    NSString *path=[shelfPath() stringByAppendingPathComponent:[key stringByAppendingPathExtension:ext]];
    if (![fm() fileExistsAtPath:path]) [data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:nil];
    else [fm() setAttributes:@{NSFileModificationDate:NSDate.date} ofItemAtPath:path error:nil];
}
static void saveValues(NSArray *items) {
 for(NSDictionary *item in items){
    for(NSString *key in @[@"public.png",@"public.jpeg",@"public.image",@"public.utf8-plain-text",@"public.text",@"public.url"]){
      id value=item[key];if(!value)continue;
      if([value isKindOfClass:NSURL.class])value=[value absoluteString];
      if([value isKindOfClass:NSString.class])record([value dataUsingEncoding:NSUTF8StringEncoding],@"txt");
      else if([value isKindOfClass:UIImage.class])record(UIImagePNGRepresentation(value),@"png");
      else if([value isKindOfClass:NSData.class]){
        if([key containsString:@"text"]||[key hasSuffix:@"url"])record(value,@"txt");
        else record(UIImagePNGRepresentation([UIImage imageWithData:value]),@"png");
      }
      break;
    }
 }
}
%hook UIPasteboard
-(void)setString:(NSString *)s { %orig; if(self==UIPasteboard.generalPasteboard)record([s dataUsingEncoding:NSUTF8StringEncoding],@"txt"); }
-(void)setImage:(UIImage *)i { %orig; if(i&&self==UIPasteboard.generalPasteboard)record(UIImagePNGRepresentation(i),@"png"); }
-(void)setItems:(NSArray *)items { %orig; if(self==UIPasteboard.generalPasteboard)saveValues(items); }
-(void)setItems:(NSArray *)items options:(NSDictionary *)options { %orig; if(self==UIPasteboard.generalPasteboard)saveValues(items); }
%end

@interface MKArchive : UITableViewController <UISearchResultsUpdating,UIDocumentPickerDelegate>
@property(nonatomic,weak) UIView<UITextInput> *target;
@property(nonatomic,strong) NSArray<NSURL *> *files;
@property(nonatomic,strong) NSArray<NSURL *> *visible;
@property(nonatomic,strong) NSMutableDictionary *meta;
@property(nonatomic,strong) NSMutableDictionary *labels;
@property(nonatomic,strong) NSMutableDictionary *times;
@property(nonatomic,strong) UISegmentedControl *tabs;
@property(nonatomic,strong) UISearchController *finder;
@end
@implementation MKArchive
-(void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight=64;
    _tabs=[[UISegmentedControl alloc] initWithItems:@[@"\u0627\u0644\u0633\u062c\u0644",@"\u0627\u0644\u0645\u0641\u0636\u0644\u0629",@"\u0627\u0644\u0645\u062d\u0630\u0648\u0641\u0627\u062a"]];
    _tabs.selectedSegmentIndex=0;
    [_tabs addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView=_tabs;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.modalInPresentation=YES;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(emptyTrash)];
    self.pasteConfiguration=[[UIPasteConfiguration alloc] initWithAcceptableTypeIdentifiers:@[@"public.image",@"public.plain-text",@"public.url"]];
    UIPasteControlConfiguration *cfg=[UIPasteControlConfiguration new]; cfg.displayMode=UIPasteControlDisplayModeIconOnly;
    UIPasteControl *import=[[UIPasteControl alloc] initWithConfiguration:cfg]; import.target=self;
    UIBarButtonItem *folder=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(chooseFolder)];
    folder.accessibilityLabel=@"اختيار مجلد السجل المشترك";
    self.navigationItem.rightBarButtonItems=@[self.navigationItem.rightBarButtonItem,folder,[[UIBarButtonItem alloc] initWithCustomView:import]];
    _finder=[[UISearchController alloc] initWithSearchResultsController:nil];_finder.obscuresBackgroundDuringPresentation=NO;
    _finder.searchResultsUpdater=self;_finder.searchBar.placeholder=@"\u0646\u0635\u060c \u0645\u0644\u0627\u062d\u0638\u0629\u060c \u0642\u0633\u0645 \u0623\u0648 \u0646\u0648\u0639";
    self.navigationItem.searchController=_finder; self.navigationItem.hidesSearchBarWhenScrolling=NO;self.definesPresentationContext=YES;
    _meta=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"MaxKeys.archive"] mutableCopy]?:[NSMutableDictionary new];
    _labels=[NSMutableDictionary new];_times=[NSMutableDictionary new];
    [self loadFiles];
}
-(void)chooseFolder {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
-(void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;
    NSData *bookmark=nil;
    if([url startAccessingSecurityScopedResource]){
        bookmark=[url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
        [url stopAccessingSecurityScopedResource];
    }
    if(bookmark && setFolder(url)){
        [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:@"MaxKeys.folder"];[self loadFiles];return;
    }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"تعذّر فتح المجلد" message:@"اختر مجلداً قابلاً للكتابة من «على الـ iPhone»." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
-(void)loadFiles {
    NSMutableArray *items=[NSMutableArray new];
    for(NSURL *u in [fm() contentsOfDirectoryAtURL:[NSURL fileURLWithPath:shelfPath()] includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]){
        BOOL photo=[u.pathExtension isEqual:@"png"];if(!photo&&![u.pathExtension isEqual:@"txt"])continue;
        _labels[u]=photo?@"\u0635\u0648\u0631\u0629":([NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:nil]?:@"");
        NSDate *date=nil;[u getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];_times[u]=date?:NSDate.distantPast;[items addObject:u];
    }
    _files=[items sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){return [self.times[b] compare:self.times[a]];}];[self refresh];
}
-(void)pasteItemProviders:(NSArray<NSItemProvider *> *)providers {
 for(NSItemProvider *p in providers){
    Class cls=[p canLoadObjectOfClass:UIImage.class]?UIImage.class:([p canLoadObjectOfClass:NSURL.class]?NSURL.class:NSString.class);
    [p loadObjectOfClass:cls completionHandler:^(id<NSItemProviderReading> object,NSError *error){
      if(error||!object)return;
      if([(id)object isKindOfClass:UIImage.class])record(UIImagePNGRepresentation((UIImage *)object),@"png");
      else {NSString *t=[(id)object isKindOfClass:NSURL.class]?[(NSURL *)object absoluteString]:(NSString *)object;record([t dataUsingEncoding:NSUTF8StringEncoding],@"txt");}
      dispatch_async(dispatch_get_main_queue(),^{[self loadFiles];});
    }];
 }
}
-(void)emptyTrash {
 if(_tabs.selectedSegmentIndex!=2)return;
 UIAlertController *dlg=[UIAlertController alertControllerWithTitle:@"\u062a\u0641\u0631\u064a\u063a \u0627\u0644\u0645\u062d\u0630\u0648\u0641\u0627\u062a \u0646\u0647\u0627\u0626\u064a\u0627\u064b\u061f" message:nil preferredStyle:UIAlertControllerStyleAlert];
 [dlg addAction:[UIAlertAction actionWithTitle:@"\u0625\u0644\u063a\u0627\u0621" style:UIAlertActionStyleCancel handler:nil]];
 [dlg addAction:[UIAlertAction actionWithTitle:@"\u062a\u0641\u0631\u064a\u063a" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act){
 for(NSURL *u in self.files)if([self.meta[u.lastPathComponent][@"trash"] boolValue]&&[fm() removeItemAtURL:u error:nil])[self.meta removeObjectForKey:u.lastPathComponent];
 [NSUserDefaults.standardUserDefaults setObject:self.meta forKey:@"MaxKeys.archive"];[self loadFiles];}]];
 [self presentViewController:dlg animated:YES completion:nil];
}
-(void)done {[self dismissViewControllerAnimated:YES completion:nil];}
-(void)updateSearchResultsForSearchController:(UISearchController *)controller {[self refresh];}
-(void)refresh {
    NSMutableArray *rows=[NSMutableArray new];NSString *q=_finder.searchBar.text;
    self.navigationItem.leftBarButtonItem.enabled=(_tabs.selectedSegmentIndex==2);
    for(NSURL *u in _files){NSDictionary *m=_meta[u.lastPathComponent];
        if([m[@"trash"] boolValue]!=(_tabs.selectedSegmentIndex==2))continue;
        if(_tabs.selectedSegmentIndex==1&&![m[@"fav"] boolValue])continue;
        NSString *t=_labels[u];BOOL link=[t.lowercaseString hasPrefix:@"https://"]||[t.lowercaseString hasPrefix:@"http://"];
        NSString *kind=[u.pathExtension isEqual:@"png"]?@"\u0635\u0648\u0631 img":(link?@"\u0631\u0648\u0627\u0628\u0637 url":@"\u0646\u0635\u0648\u0635 txt");
        NSString *all=[NSString stringWithFormat:@"%@ %@ %@ %@",kind,t,m[@"note"]?:@"",m[@"group"]?:@""];
        if(!q.length||[all localizedCaseInsensitiveContainsString:q])[rows addObject:u];
    }_visible=rows;[self.tableView reloadData];
}
-(NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return _visible.count;}
-(UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[table dequeueReusableCellWithIdentifier:@"item"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"item"];
    NSURL *u=_visible[p.row];NSDictionary *m=_meta[u.lastPathComponent];c.textLabel.text=_labels[u];c.textLabel.numberOfLines=2;
    c.detailTextLabel.text=[NSString stringWithFormat:@"%@  %@  %@",[NSDateFormatter localizedStringFromDate:_times[u] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle],m[@"group"]?:@"",m[@"note"]?:@""];
    c.imageView.image=[u.pathExtension isEqual:@"png"]?[[UIImage imageWithContentsOfFile:u.path] imageByPreparingThumbnailOfSize:CGSizeMake(48,48)]:[UIImage systemImageNamed:@"doc.text"];
    c.accessoryType=[m[@"fav"] boolValue]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return c;
}
-(void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
    NSURL *u=_visible[p.row]; UIView<UITextInput> *v=_target; NSString *t=_labels[u];
    [table deselectRowAtIndexPath:p animated:YES];if(_tabs.selectedSegmentIndex==2)return;
    if (!v) return;
    if ([u.pathExtension isEqual:@"png"]) {
        UIImage *image=[UIImage imageWithContentsOfFile:u.path];
        if (!image) return;
        NSItemProvider *provider=[[NSItemProvider alloc] initWithObject:image];
        if(![v canPasteItemProviders:@[provider]])return;
        [v pasteItemProviders:@[provider]];
    } else {
        [v insertText:t];
    }
    NSDate *used=NSDate.date;
    if (![fm() setAttributes:@{NSFileModificationDate:used} ofItemAtPath:u.path error:nil]) return;
    _times[u]=used;
    NSMutableArray *ordered=[_files mutableCopy];
    [ordered removeObject:u];
    [ordered insertObject:u atIndex:0];
    _files=ordered;
    [self refresh];
    if (_visible.count) [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:YES];
}
-(void)save:(NSDictionary *)m key:(NSString *)k {_meta[k]=m;[NSUserDefaults.standardUserDefaults setObject:_meta forKey:@"MaxKeys.archive"];[self refresh];}
-(UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)p {
    NSString *k=_visible[p.row].lastPathComponent; NSMutableDictionary *m=[_meta[k] mutableCopy]?:[NSMutableDictionary new];
    UIContextualAction *fav=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:[m[@"fav"] boolValue]?@"\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u062a\u062b\u0628\u064a\u062a":@"\u0645\u0641\u0636\u0644\u0629" handler:^(UIContextualAction *a,UIView *v,void(^end)(BOOL)){m[@"fav"]=@(![m[@"fav"] boolValue]);end(YES);[self save:m key:k];}];
    UIContextualAction *edit=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"\u062a\u0646\u0638\u064a\u0645" handler:^(UIContextualAction *a,UIView *v,void(^end)(BOOL)){end(YES);
        UIAlertController *dlg=[UIAlertController alertControllerWithTitle:@"\u062a\u0646\u0638\u064a\u0645 \u0627\u0644\u0639\u0646\u0635\u0631" message:nil preferredStyle:UIAlertControllerStyleAlert];
        for(NSString *f in @[@"note",@"group"])[dlg addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=[f isEqual:@"note"]?@"\u0645\u0644\u0627\u062d\u0638\u0629":@"\u0627\u0644\u0642\u0633\u0645";field.text=m[f];}];
        [dlg addAction:[UIAlertAction actionWithTitle:@"\u062d\u0641\u0638" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){m[@"note"]=dlg.textFields[0].text?:@"";m[@"group"]=dlg.textFields[1].text?:@"";[self save:m key:k];}]];
        [dlg addAction:[UIAlertAction actionWithTitle:@"\u0625\u0644\u063a\u0627\u0621" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:dlg animated:YES completion:nil];}];
    NSURL *url=_visible[p.row];
    BOOL trash=_tabs.selectedSegmentIndex==2;
    UIContextualAction *del=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"\u062d\u0630\u0641" handler:^(UIContextualAction *a,UIView *v,void(^end)(BOOL)){
      if(trash){BOOL ok=[fm() removeItemAtURL:url error:nil];end(ok);if(ok){[self.meta removeObjectForKey:k];[NSUserDefaults.standardUserDefaults setObject:self.meta forKey:@"MaxKeys.archive"];[self loadFiles];}}
      else{m[@"trash"]=@YES;end(YES);[self save:m key:k];}
    }];
    UIContextualAction *restore=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"\u0627\u0633\u062a\u0639\u0627\u062f\u0629" handler:^(UIContextualAction *a,UIView *v,void(^end)(BOOL)){m[@"trash"]=@NO;end(YES);[self save:m key:k];}];
    UISwipeActionsConfiguration *actions=[UISwipeActionsConfiguration configurationWithActions:trash?@[restore,del]:@[del,fav,edit]]; actions.performsFirstActionWithFullSwipe=NO;return actions;
}
@end
static NSMutableDictionary *credential(NSString *provider) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"com.maxfilp.maxkeys.ai",
              (__bridge id)kSecAttrAccount:provider} mutableCopy];
}
static NSString *apiKey(NSString *provider) {
    NSMutableDictionary *query=credential(provider);
    query[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef result=NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query,&result)!=errSecSuccess) return nil;
    return [[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
}
@interface MKBar : UIView
@property(nonatomic,strong) UIStackView *panel;
@property(nonatomic,strong) NSURLSessionDataTask *request;
@property(nonatomic) NSUInteger generation;

@property(nonatomic,weak) UIView<UITextInput> *editor;
@property(nonatomic,strong) UIStackView *rows;
@property(nonatomic,strong) UIView *original;
@property(nonatomic,strong) UIScrollView *clips;
@end
static UIButton *button(NSString *s,void (^action)(void)) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font=[UIFont systemFontOfSize:13];
    NSDictionary *icons=@{@"طيّ الكيبورد":@"keyboard.chevron.compact.down",@"\u21b6":@"arrow.uturn.backward",@"\u21b7":@"arrow.uturn.forward",@"\u062a\u062d\u062f\u064a\u062f":@"selection.pin.in.out",@"\u2190":@"arrow.left",@"\u2192":@"arrow.right",@"\u0639\u0646\u0648\u0627\u0646\u064a":@"house",@"\u0631\u062f \u0633\u0631\u064a\u0639":@"text.bubble",@"\u0627\u0644\u062d\u0627\u0641\u0638\u0629":@"list.clipboard"};
    [b setImage:[UIImage systemImageNamed:icons[s]]?:[UIImage systemImageNamed:@"selection.pin.in.out"] forState:UIControlStateNormal];b.accessibilityLabel=s;
    [b addAction:[UIAction actionWithHandler:^(__unused UIAction *a){action();}] forControlEvents:UIControlEventTouchUpInside];
    return b;
}
@implementation MKBar
-(UIViewController *)presenter {
    UIViewController *vc=self.editor.window.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    return vc;
}
-(void)configure:(NSString *)provider {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:provider message:@"إعدادات MaxKeys لهذا التطبيق. أدخل مفتاحك، أو امسحه لحذفه." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.secureTextEntry=YES; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.placeholder=@"API Key"; f.text=apiKey(provider);}];
    [a addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *key=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSMutableDictionary *q=credential(provider);
        OSStatus status;
        if(key.length){
            NSDictionary *attrs=@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
            status=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);
            if(status==errSecItemNotFound){[q addEntriesFromDictionary:attrs]; status=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}
        } else {status=SecItemDelete((__bridge CFDictionaryRef)q); if(status==errSecItemNotFound)status=errSecSuccess;}
        if(status==errSecSuccess) [NSUserDefaults.standardUserDefaults setObject:provider forKey:@"MaxKeys.provider"];
        else [self display:@"تعذّر حفظ المفتاح في سلسلة المفاتيح." output:nil source:nil replace:NO];
    }]];
    [[self presenter] presentViewController:a animated:YES completion:nil];
}
-(void)resizePanel {
    CGRect frame=self.frame; frame.size.height=_panel?164:44; self.frame=frame;
    [self invalidateIntrinsicContentSize]; [self setNeedsLayout]; [_editor reloadInputViews];
}
-(CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric,_panel?164:44); }
-(void)hidePanel {
    _generation++; [_request cancel]; _request=nil; [_panel removeFromSuperview]; _panel=nil; [self resizePanel];
}
-(void)display:(NSString *)message output:(NSString *)result source:(NSString *)source replace:(BOOL)replace {
    [_panel removeFromSuperview]; _panel=[UIStackView new]; _panel.axis=UILayoutConstraintAxisVertical; [self addSubview:_panel];
    UITextView *preview=[UITextView new]; preview.editable=NO; preview.selectable=NO;
    preview.backgroundColor=UIColor.secondarySystemBackgroundColor; preview.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; preview.text=message;
    [_panel addArrangedSubview:preview];
    UIStackView *actions=[UIStackView new]; actions.distribution=UIStackViewDistributionFillEqually;
    [_panel addArrangedSubview:actions]; [actions.heightAnchor constraintEqualToConstant:38].active=YES;
    __weak MKBar *weak=self;
    NSArray *titles=result?@[replace?@"استبدال المحدد":@"إدراج",@"نسخ",@"إغلاق"]:@[@"إغلاق"];
    for(NSString *title in titles){
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal];
        [b addAction:[UIAction actionWithHandler:^(UIAction *act){
            MKBar *bar=weak; if(!bar)return;
            if([title isEqual:@"نسخ"]){UIPasteboard.generalPasteboard.string=result; return;}
            if(![title isEqual:@"إغلاق"]){
                UIView<UITextInput> *editor=bar.editor;
                if(!editor.isFirstResponder)return;
                UITextRange *range=editor.selectedTextRange;
                if(replace && (!range || ![[editor textInRange:range] isEqual:source])){
                    [bar display:@"تغيّر التحديد. تگدر تنسخ النتيجة أو تدرجها عند المؤشر." output:result source:nil replace:NO]; return;
                }
                [editor insertText:result];
            }
            [bar hidePanel];
        }] forControlEvents:UIControlEventTouchUpInside]; [actions addArrangedSubview:b];
    }
    [self resizePanel];
}
-(void)runAI:(NSString *)instruction source:(NSString *)source replace:(BOOL)replace {
    if(!source.length){
        UIAlertController *entry=[UIAlertController alertControllerWithTitle:@"النص المراد إرساله" message:@"اكتب النص أو الصقه ثم اضغط إرسال." preferredStyle:UIAlertControllerStyleAlert];
        [entry addTextFieldWithConfigurationHandler:nil];
        [entry addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
        [entry addAction:[UIAlertAction actionWithTitle:@"إرسال" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){NSString *text=entry.textFields.firstObject.text;if(text.length)[self runAI:instruction source:text replace:NO];}]];
        [[self presenter] presentViewController:entry animated:YES completion:nil];return;
    }
    NSString *provider=[NSUserDefaults.standardUserDefaults stringForKey:@"MaxKeys.provider"]?:@"OpenAI";
    NSString *key=apiKey(provider); if(!key.length){[self configure:provider];return;}
    BOOL google=[provider isEqual:@"Gemini"];
    NSURL *url=[NSURL URLWithString:google?@"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions":@"https://api.openai.com/v1/chat/completions"];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url];req.HTTPMethod=@"POST";req.timeoutInterval=55;
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"model":google?@"gemini-2.5-flash":@"gpt-4.1-mini",@"messages":@[@{@"role":@"system",@"content":instruction},@{@"role":@"user",@"content":source}]} options:0 error:nil];
    [_request cancel]; NSUInteger generation=++_generation;
    [self display:@"جاري تحضير النتيجة…" output:nil source:nil replace:NO];
    __weak MKBar *weak=self;
    _request=[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *err){
        NSInteger status=[(NSHTTPURLResponse *)response statusCode];
        NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSString *answer=nil;
        if([json isKindOfClass:NSDictionary.class] && status==200) answer=[json[@"choices"] firstObject][@"message"][@"content"];
        if(![answer isKindOfClass:NSString.class]||!answer.length) answer=nil;
        NSString *message=answer?:((status==401||status==403)?@"راجع مفتاح API وصلاحياته.":status==429?@"بلغت حد الطلبات أو الرصيد لدى المزوّد.":@"تعذّر الحصول على نتيجة. تحقق من الاتصال وإعدادات المزوّد.");
        if(!answer){
            NSString *code=[json isKindOfClass:NSDictionary.class] && [json[@"error"] isKindOfClass:NSDictionary.class] ? [json[@"error"][@"code"] description] : nil;
            message=[NSString stringWithFormat:@"%@ · %@ %ld %@\n%@",provider,err?@"Network":@"HTTP",(long)(err?err.code:status),code?:@"",message];
        }
        dispatch_async(dispatch_get_main_queue(),^{MKBar *bar=weak;if(bar && bar.generation==generation)[bar display:message output:answer source:source replace:replace];});
    }]; [_request resume];
}
-(UIButton *)aiButton:(BOOL)translation {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; b.accessibilityLabel=translation?@"ترجمة":@"المساعد الذكي";
    [b setImage:[UIImage systemImageNamed:translation?@"globe":@"sparkles"] forState:UIControlStateNormal];
    __weak MKBar *weak=self;
    NSMutableArray *items=[NSMutableArray new]; NSMutableArray *settings=[NSMutableArray new];
    for(NSString *provider in @[@"OpenAI",@"Gemini"])[settings addObject:[UIAction actionWithTitle:provider image:nil identifier:nil handler:^(UIAction *a){[weak configure:provider];}]];
    NSArray *options=translation?@[@"الإنجليزية",@"العربية",@"الفرنسية",@"التركية"]:@[@"رد باللهجة العراقية",@"تصحيح الكتابة",@"صياغة رسمية",@"طلب خاص"];
    for(NSString *option in options){
        UIAction *action=[UIAction actionWithTitle:option image:nil identifier:nil handler:^(UIAction *a){
            MKBar *bar=weak; UIView<UITextInput> *editor=bar.editor; UITextRange *range=editor.selectedTextRange;
            NSString *source=range?[editor textInRange:range]:nil;
            if([option isEqual:@"طلب خاص"]){
                UIAlertController *dlg=[UIAlertController alertControllerWithTitle:option message:@"اكتب طلبك للمساعد" preferredStyle:UIAlertControllerStyleAlert];
                [dlg addTextFieldWithConfigurationHandler:nil];[dlg addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
                [dlg addAction:[UIAlertAction actionWithTitle:@"إرسال" style:UIAlertActionStyleDefault handler:^(UIAlertAction *send){NSString *prompt=dlg.textFields.firstObject.text;if(prompt.length)[bar runAI:prompt source:source.length?source:prompt replace:NO];}]];
                [[bar presenter] presentViewController:dlg animated:YES completion:nil];return;
            }
            if(translation)[NSUserDefaults.standardUserDefaults setObject:option forKey:@"MaxKeys.language"];
            NSString *instruction=translation?[@"ترجم النص فقط إلى " stringByAppendingString:option]:[option stringByAppendingString:@" للنص المرفق. أعد النتيجة فقط."];
            [bar runAI:instruction source:source replace:translation];
        }];
        [items addObject:action];
    }
    if(translation){NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"MaxKeys.language"];for(UIAction *action in items)if([action.title isEqual:saved])action.state=UIMenuElementStateOn;}
    [items addObject:[UIMenu menuWithTitle:@"إعدادات المزوّد والمفتاح" children:settings]];
    b.menu=[UIMenu menuWithTitle:@"يُرسل النص عند اختيار العملية" children:items]; b.showsMenuAsPrimaryAction=YES;
    return b;
}
-(UIStackView *)row {
    UIStackView *r=[UIStackView new]; r.distribution=UIStackViewDistributionFillEqually;
    r.semanticContentAttribute=UISemanticContentAttributeForceLeftToRight;
    [_rows addArrangedSubview:r]; return r;
}
-(void)setup:(UIView<UITextInput> *)e original:(UIView *)o {
    _editor=e; _original=o; self.backgroundColor=UIColor.secondarySystemBackgroundColor;
    _rows=[UIStackView new]; _rows.axis=UILayoutConstraintAxisVertical;
    _rows.distribution=UIStackViewDistributionFillEqually; [self addSubview:_rows];
    
    __weak MKBar *w=self;
    UIStackView *r=[self row];
    [r addArrangedSubview:[self aiButton:YES]]; [r addArrangedSubview:[self aiButton:NO]];
    [r addArrangedSubview:button(@"طيّ الكيبورد",^{[w.editor resignFirstResponder];})];
    for(NSString *s in @[@"\u21b6",@"\u21b7",@"\u062a\u062d\u062f\u064a\u062f",@"\u2190",@"\u2192"]) {
        [r addArrangedSubview:button(s,^{
            UIView<UITextInput> *v=w.editor;
            if ([s isEqual:@"\u21b6"]) [v.undoManager undo];
            else if ([s isEqual:@"\u21b7"]) [v.undoManager redo];
            else if ([s isEqual:@"\u062a\u062d\u062f\u064a\u062f"]) v.selectedTextRange=[v textRangeFromPosition:v.beginningOfDocument toPosition:v.endOfDocument];
            else {
                UITextPosition *p=[v positionFromPosition:v.selectedTextRange.start inDirection:[s isEqual:@"\u2190"]?UITextLayoutDirectionLeft:UITextLayoutDirectionRight offset:1];
                if(p) v.selectedTextRange=[v textRangeFromPosition:p toPosition:p];
            }
        })];
    }

    for(NSString *s in @[@"\u0639\u0646\u0648\u0627\u0646\u064a",@"\u0631\u062f \u0633\u0631\u064a\u0639",@"\u0627\u0644\u062d\u0627\u0641\u0638\u0629"]) [r addArrangedSubview:button(s,^{
        if([s isEqual:@"\u0627\u0644\u062d\u0627\u0641\u0638\u0629"]) [w showShelf]; else [w snippet:s];
    })];
}
-(void)layoutSubviews { [super layoutSubviews]; CGFloat height=CGRectGetHeight(self.bounds); _rows.frame=CGRectMake(0,height-44,self.bounds.size.width,44); _panel.frame=CGRectMake(8,0,self.bounds.size.width-16,MAX(0,height-44));
}
-(void)snippet:(NSString *)name {
    NSString *key=[@"MaxKeys." stringByAppendingString:name];
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:key];
    if(saved.length){[_editor insertText:saved];return;}
    UIViewController *vc=_editor.window.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:name message:@"\u0627\u0643\u062a\u0628 \u0627\u0644\u0646\u0635 \u0627\u0644\u0645\u062d\u0641\u0648\u0638" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:nil];
    __weak UIView<UITextInput> *target=_editor;
    [a addAction:[UIAlertAction actionWithTitle:@"\u062d\u0641\u0638" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        NSString *t=a.textFields.firstObject.text;
        if(t.length){[NSUserDefaults.standardUserDefaults setObject:t forKey:key]; [target insertText:t];}
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"\u0625\u0644\u063a\u0627\u0621" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
-(void)showShelf {

    MKArchive *archive=[MKArchive new];archive.target=_editor;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:archive];
    nav.modalInPresentation=YES;nav.modalPresentationStyle=UIModalPresentationPageSheet;
    nav.sheetPresentationController.detents=@[[UISheetPresentationControllerDetent mediumDetent],[UISheetPresentationControllerDetent largeDetent]];
    nav.sheetPresentationController.prefersGrabberVisible=YES;
    UIViewController *vc=_editor.window.rootViewController;while(vc.presentedViewController)vc=vc.presentedViewController;
    [vc presentViewController:nav animated:YES completion:nil];
}
@end
static char barKey;
static UIView *accessory(UIView<UITextInput> *e,UIView *orig){
    if([(id<UITextInputTraits>)e isSecureTextEntry] || [orig isKindOfClass:MKBar.class]) return orig;
    MKBar *b=objc_getAssociatedObject(e,&barKey);
    if(!b || b.original!=orig){
        b=[[MKBar alloc] initWithFrame:CGRectMake(0,0,UIScreen.mainScreen.bounds.size.width,44)];
        b.autoresizingMask=UIViewAutoresizingFlexibleWidth; [b setup:e original:orig];
        objc_setAssociatedObject(e,&barKey,b,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return b;
}
%hook UITextField
-(UIView *)inputAccessoryView { return accessory(self,%orig); }
%end
%hook UITextView
-(UIView *)inputAccessoryView { return accessory(self,%orig); }
%end
