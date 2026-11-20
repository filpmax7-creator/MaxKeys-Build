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
static NSString *incomingLanguage(NSString *chat) {
    if (!chat) return nil;
    return [NSUserDefaults.standardUserDefaults stringForKey:[@"MaxWhatsTranslate.incoming." stringByAppendingString:chat]] ?: (setting(chat) ? @"ar" : nil);
}
static void refreshViews(UIView *view) {
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class]) [view setNeedsLayout];
    for (UIView *child in view.subviews) refreshViews(child);
}
static void installMenu(UIViewController *vc) {
    NSString *chat=chatID(vc);
    if (!chat || !vc.navigationController) return;
    UIBarButtonItem *button=objc_getAssociatedObject(vc,&languageButton);
    NSArray *items=vc.navigationItem.rightBarButtonItems ?: @[];
    __weak UIViewController *weakVC=vc;
    NSDictionary *names=@{@"en":@"\u0627\u0644\u0625\u0646\u062c\u0644\u064a\u0632\u064a\u0629",@"tr":@"\u0627\u0644\u062a\u0631\u0643\u064a\u0629",@"ar":@"\u0627\u0644\u0639\u0631\u0628\u064a\u0629",@"fr":@"\u0627\u0644\u0641\u0631\u0646\u0633\u064a\u0629",@"de":@"\u0627\u0644\u0623\u0644\u0645\u0627\u0646\u064a\u0629",@"es":@"\u0627\u0644\u0625\u0633\u0628\u0627\u0646\u064a\u0629",@"ru":@"\u0627\u0644\u0631\u0648\u0633\u064a\u0629",@"zh-CN":@"\u0627\u0644\u0635\u064a\u0646\u064a\u0629",@"ur":@"\u0627\u0644\u0623\u0631\u062f\u064a\u0629",@"hi":@"\u0627\u0644\u0647\u0646\u062f\u064a\u0629",@"id":@"\u0627\u0644\u0625\u0646\u062f\u0648\u0646\u064a\u0633\u064a\u0629"};

    NSMutableArray *groups=[NSMutableArray new];
    for (NSNumber *direction in @[@NO,@YES]) {
        BOOL incoming=direction.boolValue;
        NSString *current=incoming ? incomingLanguage(chat) : setting(chat);
        NSMutableArray *actions=[NSMutableArray new];
        for (NSString *code in [[names allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            UIAction *action=[UIAction actionWithTitle:names[code] image:nil identifier:nil handler:^(__unused UIAction *sender){
                if (incoming) [NSUserDefaults.standardUserDefaults setObject:code forKey:[@"MaxWhatsTranslate.incoming." stringByAppendingString:chat]];
                else [engine setLanguage:code forChat:chat];
                installMenu(weakVC);
                refreshViews(weakVC.view);
            }];
            action.state=[current isEqual:code] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [actions addObject:action];
        }
        [groups addObject:[UIMenu menuWithTitle:(incoming ? @"لغة الوارد" : @"لغة الصادر") children:actions]];
    }
    [groups addObject:[UIAction actionWithTitle:@"إيقاف لهذه المحادثة" image:nil identifier:nil handler:^(__unused UIAction *sender){
        for (NSString *prefix in @[@"MaxWhatsTranslate.incoming.",@"MaxWhatsTranslate.target."])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:[prefix stringByAppendingString:chat]];
        installMenu(weakVC);
        refreshViews(weakVC.view);
    }]];
    UIMenu *menu=[UIMenu menuWithTitle:@"ترجمة المحادثة عبر Google" children:groups];
    if (!button) {
        button=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] menu:menu];
        button.accessibilityLabel=@"لغة ترجمة المحادثة";
        objc_setAssociatedObject(vc,&languageButton,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else button.menu=menu;
    if (![items containsObject:button]) vc.navigationItem.rightBarButtonItems=[items arrayByAddingObject:button];
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

static NSString *visibleChat(UIView *v) {
    for (UIResponder *r=v; r; r=r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSString *chat=chatID((UIViewController *)r);
        if (chat.length) return chat;
    }
    return nil;
}

static id messageIn(id owner) {
    for (id holder in @[owner ?: NSNull.null, property(owner,@"cellData") ?: NSNull.null,
                         property(owner,@"viewModel") ?: NSNull.null, property(owner,@"messageData") ?: NSNull.null]) {
        for (NSString *key in @[@"message",@"waMessage",@"messageObject"]) {
            id model=property(holder,key);
            if ([model respondsToSelector:NSSelectorFromString(@"isFromMe")]) return model;
        }
        if ([holder respondsToSelector:NSSelectorFromString(@"isFromMe")]) return holder;
    }
    return nil;
}

static id modelForView(UIView *view) {
    for (UIView *v=view; v; v=v.superview) {
        if ([v isKindOfClass:UITableView.class] || [v isKindOfClass:UICollectionView.class]) break;
        id model=messageIn(v);
        if (model) return model;
        if (![v isKindOfClass:UITableViewCell.class] && ![v isKindOfClass:UICollectionViewCell.class]) continue;
        UIView *list=v.superview;
        while(list && ![list isKindOfClass:UITableView.class] && ![list isKindOfClass:UICollectionView.class]) list=list.superview;
        NSIndexPath *path=nil;
        if ([v isKindOfClass:UITableViewCell.class] && [list isKindOfClass:UITableView.class])
            path=[(UITableView *)list indexPathForCell:(UITableViewCell *)v];
        if ([v isKindOfClass:UICollectionViewCell.class] && [list isKindOfClass:UICollectionView.class])
            path=[(UICollectionView *)list indexPathForCell:(UICollectionViewCell *)v];
        id source=property(list,@"dataSource");
        if (path) for (id provider in @[source ?: NSNull.null,controller(v) ?: NSNull.null]) {
            for (NSString *key in @[@"messageAtIndexPath:",@"messageForIndexPath:"]) {
                SEL sel=NSSelectorFromString(key);
                NSMethodSignature *sig=[provider methodSignatureForSelector:sel];
                if (sig.numberOfArguments!=3 || sig.methodReturnType[0]!='@' || [sig getArgumentTypeAtIndex:2][0]!='@') continue;
                id (*get)(id,SEL,id)=(id (*)(id,SEL,id))[provider methodForSelector:sel];
                id found=messageIn(get(provider,sel,path));
                if(found) return found;
            }
        }
        break;
    }
    return nil;
}
static NSString *plain(NSString *s) {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static void translateView(UIView *view) {
    if (!view.window) return;
    BOOL label=[view isKindOfClass:UILabel.class];
    UITextView *tv=label ? nil : (UITextView *)view;
    if (tv && tv.editable) return;
    NSString *display=label ? ((UILabel *)view).text : tv.text;
    if (!display.length) return;
    NSString *chat=visibleChat(view);
    NSString *target=incomingLanguage(chat);
    NSArray *render=objc_getAssociatedObject(view,&translatedText);
    if (render && [display isEqual:render[0]]) {
        if ([chat isEqual:render[1]] && [target isEqual:render[2]]) return;
        NSAttributedString *source=render[3];
        objc_setAssociatedObject(view,&translatedText,nil,OBJC_ASSOCIATION_ASSIGN);
        if(label) ((UILabel *)view).attributedText=source; else tv.attributedText=source;
        display=source.string;
    }
    if (!target) return;
    id model=modelForView(view);
    NSNumber *outgoing=property(model,@"isFromMe");
    if (![outgoing isKindOfClass:NSNumber.class] || outgoing.boolValue) return;
    id body=property(model,@"text") ?: property(model,@"messageText");
    if ([body isKindOfClass:NSAttributedString.class]) body=[body string];
    if (![body isKindOfClass:NSString.class] || ![plain(display) isEqual:plain(body)]) return;
    NSArray *key=@[chat,target,display];
    if ([objc_getAssociatedObject(view,&originalText) isEqual:key]) return;
    objc_setAssociatedObject(view,&originalText,key,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weak=view;
    [engine translateIncoming:body target:target completion:^(NSString *result){
        UIView *v=weak;
        if (!v || ![objc_getAssociatedObject(v,&originalText) isEqual:key]) return;
        UILabel *l=label ? (UILabel *)v : nil;
        UITextView *t=label ? nil : (UITextView *)v;
        if (!result.length || [plain(result) isEqual:plain(display)]) return;
        objc_setAssociatedObject(v,&originalText,nil,OBJC_ASSOCIATION_ASSIGN);
        if (!v.window || ![visibleChat(v) isEqual:chat] || ![incomingLanguage(chat) isEqual:target] || ![(label ? l.text : t.text) isEqual:display]) return;
        NSMutableAttributedString *content=[(label ? l.attributedText : t.attributedText) mutableCopy];
        if(!content.length) content=[[NSMutableAttributedString alloc] initWithString:display];
        NSDictionary *style=@{NSFontAttributeName:(label ? l.font : t.font) ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
                              NSForegroundColorAttributeName:(label ? l.textColor : t.textColor) ?: UIColor.labelColor};
        NSAttributedString *source=[content copy];
        [content appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:result] attributes:style]];
        objc_setAssociatedObject(v,&translatedText,@[content.string,chat,target,source],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(label) { l.numberOfLines=0; l.attributedText=content; } else { t.attributedText=content; }
        [v invalidateIntrinsicContentSize];
    }];
}
%hook UILabel
- (void)layoutSubviews { %orig; translateView(self); }
%end
%hook UITextView
- (void)layoutSubviews { %orig; translateView(self); }
%end
%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"net.whatsapp.WhatsApp"]) {
        engine=[ConversationTranslator new];
        %init;
    }
}