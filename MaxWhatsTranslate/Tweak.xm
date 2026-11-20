#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ConversationTranslator.h"

static ConversationTranslator *engine;
static char languageButton, sending, originalText, translatedText;

static id property(id object, NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static UIViewController *controller(UIView *view) {
    for (UIResponder *r=view; r; r=r.nextResponder)
        if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    return nil;
}
static NSString *chatID(UIViewController *vc) {
    id session = property(vc, @"chatSession");
    for (NSString *key in @[@"contactJID", @"jid", @"chatJID"]) {
        id jid = property(session,key);
        if (jid && ![jid isKindOfClass:NSString.class]) jid = property(jid,@"rawString");
        if ([jid isKindOfClass:NSString.class] && [jid length]) return jid;
    }
    return nil;
}
static NSString *setting(NSString *chat) {
    return chat ? [NSUserDefaults.standardUserDefaults stringForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]] : nil;
}
static void note(UIViewController *vc, NSString *text) {
    if (!vc.view.window || vc.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"\u062a\u0631\u062c\u0645\u0629 \u0648\u0627\u062a\u0633\u0627\u0628" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"\u062a\u0645" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
static void installMenu(UIViewController *vc) {
    NSString *chat=chatID(vc);
    if (!chat || !vc.navigationController) return;
    UIBarButtonItem *previous=objc_getAssociatedObject(vc,&languageButton);
    NSArray *items=vc.navigationItem.rightBarButtonItems ?: @[];
    if (previous && [items containsObject:previous]) return;
    NSDictionary *names=@{@"en":@"\u0627\u0644\u0625\u0646\u062c\u0644\u064a\u0632\u064a\u0629",@"tr":@"\u0627\u0644\u062a\u0631\u0643\u064a\u0629",@"ar":@"\u0627\u0644\u0639\u0631\u0628\u064a\u0629",@"fr":@"\u0627\u0644\u0641\u0631\u0646\u0633\u064a\u0629",@"de":@"\u0627\u0644\u0623\u0644\u0645\u0627\u0646\u064a\u0629",@"es":@"\u0627\u0644\u0625\u0633\u0628\u0627\u0646\u064a\u0629",@"ru":@"\u0627\u0644\u0631\u0648\u0633\u064a\u0629",@"zh-CN":@"\u0627\u0644\u0635\u064a\u0646\u064a\u0629",@"ur":@"\u0627\u0644\u0623\u0631\u062f\u064a\u0629",@"hi":@"\u0627\u0644\u0647\u0646\u062f\u064a\u0629",@"id":@"\u0627\u0644\u0625\u0646\u062f\u0648\u0646\u064a\u0633\u064a\u0629"};
    NSMutableArray *actions=[NSMutableArray new];
    for (NSString *code in [[names allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [actions addObject:[UIAction actionWithTitle:names[code] image:nil identifier:nil handler:^(__unused UIAction *action){
            [engine setLanguage:code forChat:chat];
        }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"\u0625\u064a\u0642\u0627\u0641 \u0644\u0647\u0630\u0647 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629" image:nil identifier:nil handler:^(__unused UIAction *action){
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]];
    }]];
    UIMenu *menu=[UIMenu menuWithTitle:@"\u0644\u063a\u0629 \u0627\u0644\u0625\u0631\u0633\u0627\u0644 \u00b7 \u062a\u064f\u062a\u0631\u062c\u0645 \u0627\u0644\u0631\u0633\u0627\u0626\u0644 \u0639\u0628\u0631 Google" children:actions];
    UIBarButtonItem *button=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] menu:menu];
    button.accessibilityLabel=@"\u0644\u063a\u0629 \u062a\u0631\u062c\u0645\u0629 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629";
    objc_setAssociatedObject(vc,&languageButton,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:button];
}
static UITextView *activeEditor(UIView *root) {
    if ([root isKindOfClass:UITextView.class] && root.isFirstResponder) return (UITextView *)root;
    for (UIView *child in root.subviews) {
        UITextView *editor=activeEditor(child);
        if (editor) return editor;
    }
    return nil;
}
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    installMenu(self);
}
%end
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    UIViewController *vc=controller(self);
    NSString *chat=chatID(vc);
    NSString *language=setting(chat);
    NSString *name=NSStringFromSelector(action).lowercaseString;
    BOOL isSend=[name containsString:@"sendbutton"] || [name isEqual:@"sendmessage:"] || [name isEqual:@"sendpressed:"];
    if (!isSend || !language || !target) { %orig; return; }
    UITextView *editor=activeEditor(vc.view);
    NSString *draft=[editor.text copy];
    if (!draft.length) { %orig; return; }
    if (objc_getAssociatedObject(editor,&sending)) return;
    objc_setAssociatedObject(editor,&sending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIViewController *weakVC=vc;
    __weak UITextView *weakEditor=editor;
    __weak UIControl *weakControl=self;
    __weak id weakTarget=target;
    [engine translateDraft:draft chat:chat completion:^(NSString *result){
        UITextView *field=weakEditor;
        if (!field) return;
        objc_setAssociatedObject(field,&sending,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIViewController *current=weakVC;
        UIControl *button=weakControl;
        id receiver=weakTarget;
        if (!button.window || !receiver || !field.isFirstResponder || ![chatID(controller(button)) isEqual:chat] ||
            ![setting(chat) isEqual:language] || ![field.text isEqual:draft]) return;
        if (!result.length) { note(current,@"\u062a\u0639\u0630\u0631\u062a \u0627\u0644\u062a\u0631\u062c\u0645\u0629. \u0645\u0633\u0648\u062f\u062a\u0643 \u0645\u062d\u0641\u0648\u0638\u0629."); return; }
        UITextRange *range=[field textRangeFromPosition:field.beginningOfDocument toPosition:field.endOfDocument];
        [field replaceRange:range withText:result];
        if ([field.text isEqual:result]) [UIApplication.sharedApplication sendAction:action to:receiver from:button forEvent:nil];
    }];
}
%end

// Match the rendered message to its model before requesting or presenting a translation.
static void translateLabel(UILabel *label) {
    UIView *cell=label.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class] && ![cell isKindOfClass:UICollectionViewCell.class]) cell=cell.superview;
    if (!cell) return;
    id model=property(cell,@"message") ?: property(property(cell,@"cellData"),@"message");
    NSNumber *outgoing=property(model,@"isFromMe");
    NSString *text=property(model,@"text");
    NSString *chat=chatID(controller(cell));
    if (!setting(chat) || ![outgoing isKindOfClass:NSNumber.class] || outgoing.boolValue || ![text isKindOfClass:NSString.class] || !text.length) return;
    if (![label.text isEqual:text] || [objc_getAssociatedObject(label,&originalText) isEqual:text]) return;
    objc_setAssociatedObject(label,&originalText,text,OBJC_ASSOCIATION_COPY_NONATOMIC);
    __weak UILabel *weakLabel=label;
    [engine translateIncoming:text completion:^(NSString *result){
        UILabel *current=weakLabel;
        if (!current.window || ![current.text isEqual:text] || ![chatID(controller(current)) isEqual:chat] || !setting(chat)) return;
        if (!result.length || [result isEqual:text]) return;
        NSString *display=[NSString stringWithFormat:@"%@\n%@",text,result];
        objc_setAssociatedObject(current,&translatedText,display,OBJC_ASSOCIATION_COPY_NONATOMIC);
        current.numberOfLines=0;
        current.text=display;
        [current invalidateIntrinsicContentSize];
    }];
}
%hook UILabel
- (void)layoutSubviews {
    %orig;
    if (self.window && self.text.length) translateLabel(self);
}
- (void)setText:(NSString *)text {
    if (![objc_getAssociatedObject(self,&translatedText) isEqual:text]) {
        objc_setAssociatedObject(self,&originalText,nil,OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(self,&translatedText,nil,OBJC_ASSOCIATION_ASSIGN);
    }
    %orig;
}
%end
%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"net.whatsapp.WhatsApp"]) {
        engine=[ConversationTranslator new];
        %init;
    }
}