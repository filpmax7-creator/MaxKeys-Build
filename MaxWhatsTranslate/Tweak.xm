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
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"���� ퟢ���" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"��" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
static void installMenu(UIViewController *vc) {
    NSString *chat=chatID(vc);
    if (!chat || !vc.navigationController) return;
    UIBarButtonItem *previous=objc_getAssociatedObject(vc,&languageButton);
    NSArray *items=vc.navigationItem.rightBarButtonItems ?: @[];
    if (previous && [items containsObject:previous]) return;
    NSDictionary *names=@{@"en":@"������",@"tr":@"�颩��",@"ar":@"��㩠�",@"fr":@"�����",@"de":@"������",@"es":@"�靫����",@"ru":@"�����",@"zh-CN":@"�����",@"ur":@"�隩��",@"hi":@"�����",@"id":@"�������"};
    NSMutableArray *actions=[NSMutableArray new];
    for (NSString *code in [[names allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [actions addObject:[UIAction actionWithTitle:names[code] image:nil identifier:nil handler:^(__unused UIAction *action){
            [engine setLanguage:code forChat:chat];
        }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"���� ��� ��꥟���" image:nil identifier:nil handler:^(__unused UIAction *action){
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]];
    }]];
    UIMenu *menu=[UIMenu menuWithTitle:@"�� �革��� � ������ �驫��� 㠩 Google" children:actions];
    UIBarButtonItem *button=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] menu:menu];
    button.accessibilityLabel=@"�� ���� ��꥟���";
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
        if (!result.length) { note(current,@"�㨩� �颩��. ����� ����."); return; }
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