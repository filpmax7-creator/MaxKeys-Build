#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ConversationTranslator.h"

static ConversationTranslator *engine;
static BOOL twitter;
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
static char xSession;
extern "C" void *MXCopyConversationKey(const void *screen);
static NSString *chatID(UIViewController *vc) {
    if (twitter) {
        for (UIViewController *screen=vc; screen; screen=screen.parentViewController) {
            id vm=property(screen,@"viewModel") ?: property(screen,@"conversationViewModel") ?: property(screen,@"presenter");
            id conversation=property(screen,@"conversation") ?: property(vm,@"conversation") ?: property(screen,@"thread") ?: property(vm,@"thread");
            for (id source in @[screen, vm ?: NSNull.null, conversation ?: NSNull.null]) {
                id identifier=property(source,@"conversationID") ?: property(source,@"conversationId") ?: property(source,@"threadID") ?: property(source,@"threadId");
                if (!identifier && source==conversation) identifier=property(source,@"identifier");
                if ([identifier isKindOfClass:NSNumber.class]) identifier=[identifier stringValue];
                if ([identifier isKindOfClass:NSString.class] && [identifier length])
                    return [@"twitter.dm." stringByAppendingString:identifier];
            }
        }
        for (UIViewController *screen=vc; screen; screen=screen.parentViewController) {
            if (![NSStringFromClass(screen.class) isEqual:@"DMConversation.ConversationViewController"]) continue;
            NSString *key=objc_getAssociatedObject(screen,&xSession);
            if (!key) {
                key=CFBridgingRelease(MXCopyConversationKey((__bridge const void *)screen));
                if (key) objc_setAssociatedObject(screen,&xSession,key,OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
            return key;
        }
        return nil;
    }
    id session = property(vc, @"chatSession");
    for (NSString *key in @[@"contactJID", @"jid", @"chatJID"]) {
        id jid = property(session,key);
        if (jid && ![jid isKindOfClass:NSString.class]) jid = property(jid,@"rawString");
        if ([jid isKindOfClass:NSString.class] && [jid length]) return jid;
    }
    return nil;
}
static BOOL translationAllowed(NSString *chat) {
    return (!twitter && chat.length && ([NSUserDefaults.standardUserDefaults objectForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]] || [NSUserDefaults.standardUserDefaults objectForKey:[@"MaxWhatsTranslate.incoming." stringByAppendingString:chat]])) || (chat.length && [NSUserDefaults.standardUserDefaults boolForKey:[@"MaxTranslate.X.Google." stringByAppendingString:chat]]);
}
static NSString *setting(NSString *chat) {
    if (!translationAllowed(chat)) return nil;
    return chat ? [NSUserDefaults.standardUserDefaults stringForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]] : nil;
}
static void note(UIViewController *vc, NSString *text) {
    if (!vc.view.window || vc.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:twitter ? @"ترجمة X" : @"\u062a\u0631\u062c\u0645\u0629 \u0648\u0627\u062a\u0633\u0627\u0628" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"\u062a\u0645" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
static NSString *incomingLanguage(NSString *chat) {
    if (!translationAllowed(chat)) return nil;
    if (!chat) return nil;
    return [NSUserDefaults.standardUserDefaults stringForKey:[@"MaxWhatsTranslate.incoming." stringByAppendingString:chat]] ?: (setting(chat) ? @"ar" : nil);
}
static void refreshViews(UIView *view) {
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] || [view isKindOfClass:NSClassFromString(@"WAMessageAttributedTextSliceView")]) [view setNeedsLayout];
    for (UIView *child in view.subviews) refreshViews(child);
}
static void showIncomingReport(UIViewController *vc);
static void installMenu(UIViewController *vc) {
    NSString *chat=chatID(vc);
    if (!chat || (!twitter && !vc.navigationController)) return;
    UIBarButtonItem *button=objc_getAssociatedObject(vc,&languageButton);
    NSArray *items=vc.navigationItem.rightBarButtonItems ?: @[];
    __weak UIViewController *weakVC=vc;
    NSDictionary *names=@{@"en":@"\u0627\u0644\u0625\u0646\u062c\u0644\u064a\u0632\u064a\u0629",@"tr":@"\u0627\u0644\u062a\u0631\u0643\u064a\u0629",@"ar":@"\u0627\u0644\u0639\u0631\u0628\u064a\u0629",@"fr":@"\u0627\u0644\u0641\u0631\u0646\u0633\u064a\u0629",@"de":@"\u0627\u0644\u0623\u0644\u0645\u0627\u0646\u064a\u0629",@"es":@"\u0627\u0644\u0625\u0633\u0628\u0627\u0646\u064a\u0629",@"ru":@"\u0627\u0644\u0631\u0648\u0633\u064a\u0629",@"zh-CN":@"\u0627\u0644\u0635\u064a\u0646\u064a\u0629",@"ur":@"\u0627\u0644\u0623\u0631\u062f\u064a\u0629",@"hi":@"\u0627\u0644\u0647\u0646\u062f\u064a\u0629",@"id":@"\u0627\u0644\u0625\u0646\u062f\u0648\u0646\u064a\u0633\u064a\u0629"};

    NSMutableArray *groups=[NSMutableArray new];
    if (!translationAllowed(chat)) {
        [groups addObject:[UIAction actionWithTitle:@"تفعيل الترجمة" image:nil identifier:nil handler:^(__unused UIAction *sender){
            if (![chatID(weakVC) isEqual:chat]) return;
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"MaxTranslate.X.Google." stringByAppendingString:chat]];
            [engine setLanguage:@"en" forChat:chat];
            installMenu(weakVC);
            refreshViews(weakVC.view);
        }]];
    } else {
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
        for (NSString *prefix in @[@"MaxWhatsTranslate.incoming.",@"MaxWhatsTranslate.target.",@"MaxTranslate.X.Google."])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:[prefix stringByAppendingString:chat]];
        installMenu(weakVC);
        refreshViews(weakVC.view);
    }]];
    [groups addObject:[UIAction actionWithTitle:@"فحص ترجمة الوارد" image:nil identifier:nil handler:^(__unused UIAction *sender){
        showIncomingReport(weakVC);
    }]];
    }
    UIMenu *menu=[UIMenu menuWithTitle:@"ترجمة المحادثة" children:groups];
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
    if (twitter && ![NSStringFromClass(self.class) isEqual:@"DMConversation.ConversationViewController"]) return;
    if (twitter) objc_setAssociatedObject(self,&xSession,nil,OBJC_ASSOCIATION_ASSIGN);
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
    if (twitter && ([name containsString:@"sendmessage"] || [name containsString:@"senddirectmessage"] || [self.accessibilityIdentifier.lowercaseString isEqual:@"dmsendbutton"])) isSend=YES;
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

static NSNumber *deliveryDirection(id owner) {
    for (NSString *key in @[@"isFromMe",@"fromMe",@"isOutgoing",@"outgoing",@"isSentByCurrentUser",@"isOutgoingMessage",@"isIncoming"]) {
        id flag=property(owner,key);
        if ([flag isKindOfClass:NSNumber.class]) return [key isEqual:@"isIncoming"] ? @(![flag boolValue]) : flag;
    }
    return nil;
}
static id messageIn(id owner) {
    for (id holder in @[owner ?: NSNull.null, property(owner,@"cellData") ?: NSNull.null,
                         property(owner,@"viewModel") ?: NSNull.null, property(owner,@"messageData") ?: NSNull.null, property(owner,@"messageViewModel") ?: NSNull.null]) {
        for (NSString *key in @[@"message",@"waMessage",@"messageObject",@"directMessage",@"dmMessage"]) {
            id model=property(holder,key);
            if (deliveryDirection(model)) return model;
        }
        if (deliveryDirection(holder)) return holder;
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
    static NSCharacterSet *marks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ marks=[NSCharacterSet characterSetWithCharactersInString:@"\u200e\u200f\u061c\u2066\u2067\u2068\u2069"]; });
    NSString *clean=[[s componentsSeparatedByCharactersInSet:marks] componentsJoinedByString:@""];
    return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static void inspectVisible(UIView *v, NSMutableOrderedSet *classes, NSUInteger *cells, NSUInteger *models) {
    if (v.hidden || !v.window || v.alpha < 0.01) return;
    if (!CGRectIntersectsRect([v convertRect:v.bounds toView:v.window],v.window.bounds)) return;
    NSString *name=NSStringFromClass(v.class);
    if ([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class]) {
        (*cells)++;
        if (modelForView(v)) (*models)++;
        [classes addObject:name];
    } else if (([name localizedCaseInsensitiveContainsString:@"message"] || [name localizedCaseInsensitiveContainsString:@"text"]) && classes.count<14)
        [classes addObject:name];
    for (UIView *child in v.subviews) inspectVisible(child,classes,cells,models);
}
static void showIncomingReport(UIViewController *vc) {
    NSUInteger cells=0, models=0;
    NSMutableOrderedSet *classes=[NSMutableOrderedSet new];
    inspectVisible(vc.view,classes,&cells,&models);
    NSString *target=incomingLanguage(chatID(vc)) ?: @"—";
    note(vc,[NSString stringWithFormat:@"اللغة: %@ · الخلايا: %lu · النماذج: %lu\n%@",target,(unsigned long)cells,(unsigned long)models,[classes.array componentsJoinedByString:@"\n"]]);
}
extern "C" int32_t MXOutgoingMessage(const void *holder);
static NSNumber *xBubbleDirection(UIView *view) {
    UIView *bubble=nil;
    for (UIView *p=view.superview;p;p=p.superview) {
        NSString *name=NSStringFromClass(p.class);
        if ([name isEqual:@"ChatConversation.MessageTextView"]) bubble=p;
        if ([name containsString:@"MessageQuote"]) return nil;
        if (![name isEqual:@"ChatConversation.MessageCell"]) continue;
        if (!bubble) return nil;
        int32_t flag=MXOutgoingMessage((__bridge const void *)p);
        if (flag>=0) return @(flag);
        CGRect frame=[bubble convertRect:bubble.bounds toView:p];
        CGFloat left=CGRectGetMinX(frame),right=CGRectGetWidth(p.bounds)-CGRectGetMaxX(frame);
        if (frame.size.width<=0 || left<0 || right<0 || fabs(left-right)<12) return nil;
        return @(left>right);
    }
    return nil;
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
    NSNumber *outgoing=deliveryDirection(model);
    BOOL useBubble=twitter && !outgoing && !label;
    if (useBubble) outgoing=xBubbleDirection(view);
    if (!outgoing || outgoing.boolValue) return;
    id body=useBubble ? display : (property(model,@"text") ?: property(model,@"messageText") ?: (twitter ? property(model,@"fullText") : nil));
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
        if (!result.length) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                UIView *retry=weak;
                if (retry && [objc_getAssociatedObject(retry,&originalText) isEqual:key])
                    objc_setAssociatedObject(retry,&originalText,nil,OBJC_ASSOCIATION_ASSIGN);
            });
            return;
        }
        if ([plain(result) isEqual:plain(display)]) return;
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

// WhatsApp draws this text slice itself. Give its translation a separate view.
static char sliceRequest, sliceButton;
static NSArray *sliceIdentity(UIView *slice) {
    if (!slice.window) return nil;
    NSString *chat=visibleChat(slice);
    NSString *language=incomingLanguage(chat);
    if (!language.length) return nil;
    id model=modelForView(slice);
    NSNumber *direction=deliveryDirection(model);
    if (!direction || direction.boolValue) return nil;
    id body=property(model,@"text") ?: property(model,@"messageText") ?: (twitter ? property(model,@"fullText") : nil);
    if ([body isKindOfClass:NSAttributedString.class]) body=[body string];
    if (![body isKindOfClass:NSString.class] || ![body length]) return nil;
    return @[chat,language,body];
}

static void updateSlice(UIView *slice) {
    NSArray *key=sliceIdentity(slice);
    UIButton *old=objc_getAssociatedObject(slice,&sliceButton);
    if ([key isEqual:objc_getAssociatedObject(slice,&sliceRequest)]) {
        if (old && old.superview==slice) [slice bringSubviewToFront:old];
        return;
    }
    [old removeFromSuperview];
    objc_setAssociatedObject(slice,&sliceButton,nil,OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(slice,&sliceRequest,key,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!key) return;
    __weak UIView *weak=slice;
    [engine translateIncoming:key[2] target:key[1] completion:^(NSString *result) {
        UIView *current=weak;
        if (!current || ![objc_getAssociatedObject(current,&sliceRequest) isEqual:key] || ![sliceIdentity(current) isEqual:key]) return;
        if (!result.length) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                UIView *v=weak;
                if ([objc_getAssociatedObject(v,&sliceRequest) isEqual:key]) objc_setAssociatedObject(v,&sliceRequest,nil,OBJC_ASSOCIATION_ASSIGN);
            });
            return;
        }
        if ([plain(result) isEqual:plain(key[2])]) return;
        UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
        button.frame=current.bounds;
        button.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        button.backgroundColor=UIColor.secondarySystemBackgroundColor;
        button.layer.cornerRadius=5;
        button.clipsToBounds=YES;
        button.titleLabel.numberOfLines=0;
        button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontSizeToFitWidth=YES;
        button.titleLabel.minimumScaleFactor=0.8;
        [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
        [button setTitle:result forState:UIControlStateNormal];
        button.accessibilityHint=@"عرض الأصل والترجمة كاملة";
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
            UIView *v=weak;
            if ([sliceIdentity(v) isEqual:key]) note(controller(v),[NSString stringWithFormat:@"%@\n\n%@",key[2],result]);
        }] forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(current,&sliceButton,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [current addSubview:button];
    }];
}

%group AttributedSlice
%hook WAMessageAttributedTextSliceView
- (void)layoutSubviews { %orig; updateSlice((UIView *)self); }
- (void)didMoveToWindow { %orig; updateSlice((UIView *)self); }
%end
%end
@interface MXComposerSendButton : UIButton
@end
%group XComposerSend
%hook MXComposerSendButton
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=%orig;
    UIButton *sendButton=(UIButton *)self; if (!hit || !sendButton.enabled) return hit;
    NSString *role=sendButton.accessibilityLabel.lowercaseString;
    if (![role isEqual:@"إرسال"] && ![role isEqual:@"send"] && ![role isEqual:@"send message"]) return self;
    UIViewController *owner=controller(self);
    UITextView *editor=activeEditor(owner.view);
    NSString *chat=chatID(controller(editor));
    NSString *language=setting(chat);
    if (!editor.text.length || !language.length) return self;
    static char proxyKey;
    UIButton *proxy=objc_getAssociatedObject(self,&proxyKey);
    if (!proxy) {
        proxy=[UIButton buttonWithType:UIButtonTypeCustom];
        proxy.isAccessibilityElement=NO;
        proxy.frame=sendButton.bounds;
        proxy.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        __weak UIControl *original=self;
        [proxy addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
            UIControl *sender=original;
            UITextView *field=activeEditor(controller(sender).view);
            NSString *key=chatID(controller(field));
            NSString *target=setting(key);
            NSString *draft=[field.text copy];
            if (!draft.length || !target.length || objc_getAssociatedObject(field,&sending)) return;
            objc_setAssociatedObject(field,&sending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [engine translateDraft:draft chat:key completion:^(NSString *result){
                objc_setAssociatedObject(field,&sending,nil,OBJC_ASSOCIATION_ASSIGN);
                if (!sender.window || !field.isFirstResponder || ![field.text isEqual:draft] ||
                    ![chatID(controller(field)) isEqual:key] || ![setting(key) isEqual:target]) return;
                if (!result.length) { note(controller(field),@"تعذّرت الترجمة. المسودة محفوظة."); return; }
                [field replaceRange:[field textRangeFromPosition:field.beginningOfDocument toPosition:field.endOfDocument] withText:result];
                if ([field.text isEqual:result]) [sender sendActionsForControlEvents:UIControlEventTouchUpInside];
            }];
        }] forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:proxy];
        objc_setAssociatedObject(self,&proxyKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return proxy;
}
%end
%end

static char postTranslateButton, postOriginalFrame;
static NSString *postString(id value) {
    if ([value isKindOfClass:NSAttributedString.class]) value=[value string];
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}
static NSString *postModelText(id owner) {
    id model=property(owner,@"viewModel");
    id status=property(owner,@"status") ?: property(model,@"status") ?: property(model,@"tweet");
    for (id source in @[status ?: NSNull.null,model ?: NSNull.null]) {
        for (NSString *field in @[@"fullText",@"attributedBodyText",@"bodyText",@"text"]) {
            NSString *text=postString(property(source,field));
            if (text.length) return text;
        }
    }
    return nil;
}
static NSString *localPostBody(UIView *root) {
    NSMutableArray *queue=[NSMutableArray arrayWithObject:root];
    for (NSUInteger i=0;i<queue.count;i++) {
        UIView *child=queue[i];
        NSString *name=NSStringFromClass(child.class).lowercaseString;
        if (child.hidden || [name containsString:@"quote"] || [name containsString:@"card"] || [name containsString:@"attachment"] ||
            [name containsString:@"header"] || [name containsString:@"author"] || [name containsString:@"action"] ||
            (child!=root && ([child isKindOfClass:UITableViewCell.class] || [child isKindOfClass:UICollectionViewCell.class]))) continue;
        if ([name containsString:@"bodytext"] || [name containsString:@"bodyattributedtext"] || [name containsString:@"bodyselectablecontenttext"] || [name containsString:@"tweettext"] || [name containsString:@"statustext"]) {
            NSString *text=postString(property(child,@"attributedText")) ?: postString(property(child,@"text")) ?: postModelText(child);
            if (text.length) return text;
        }
        [queue addObjectsFromArray:child.subviews];
    }
    return nil;
}
static NSString *postText(UIView *bar) {
    BOOL detail=NO;
    for (UIView *v=bar;v;v=v.superview) {
        if ([v isKindOfClass:UITableView.class] || [v isKindOfClass:UICollectionView.class] || [v isKindOfClass:UIWindow.class]) break;
        NSString *name=NSStringFromClass(v.class).lowercaseString;
        detail|=[name containsString:@"focal"] || [name containsString:@"detail"];
        NSString *text=postModelText(v);
        if (text.length) return text;
        BOOL cell=[v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class];
        if (cell || [name containsString:@"statusview"] || detail) {
            text=localPostBody(v);
            if (text.length) return text;
        }
        if (cell) break;
    }
    if (detail) {
        for (UIViewController *vc=controller(bar); vc; vc=vc.parentViewController) {
            NSString *text=postModelText(vc);
            if (text.length) return text;
        }
    }
    return nil;
}
static void translatePost(UIView *bar, NSString *code) {
    NSString *text=postText(bar);
    UIViewController *vc=controller(bar);
    if (!text) {note(vc,@"تعذّرت قراءة نص التغريدة."); return;}
    __weak UIView *weakBar=bar;
    [engine translateIncoming:text target:code completion:^(NSString *result){
        UIView *current=weakBar;
        if (!current.window || ![postText(current) isEqual:text]) return;
        note(controller(current),result.length ? result : @"تعذّرت ترجمة التغريدة.");
    }];
}
static UIMenu *postMenu(UIView *bar) {
    __weak UIView *weak=bar;
    UIDeferredMenuElement *options=[UIDeferredMenuElement elementWithUncachedProvider:^(void (^done)(NSArray<UIMenuElement *> *)){
        NSString *target=[NSUserDefaults.standardUserDefaults stringForKey:@"MaxTranslate.PostLanguage"] ?: @"ar";
        NSLocale *locale=NSLocale.currentLocale;
        NSString *language=[locale localizedStringForLanguageCode:target] ?: target;
        UIAction *translate=[UIAction actionWithTitle:[@"ترجمة إلى " stringByAppendingString:language] image:nil identifier:nil handler:^(__unused UIAction *a){ translatePost(weak,target); }];
        NSMutableArray *choices=[NSMutableArray new];
        NSArray *codes=[NSLocale.ISOLanguageCodes sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
            return [([locale localizedStringForLanguageCode:a] ?: a) localizedCaseInsensitiveCompare:([locale localizedStringForLanguageCode:b] ?: b)];
        }];
        for (NSString *code in codes) {
            UIAction *item=[UIAction actionWithTitle:([locale localizedStringForLanguageCode:code] ?: code) image:nil identifier:nil handler:^(__unused UIAction *a){
                [NSUserDefaults.standardUserDefaults setObject:code forKey:@"MaxTranslate.PostLanguage"];
                translatePost(weak,code);
            }];
            item.state=[code isEqual:target] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [choices addObject:item];
        }
        done(@[translate,[UIMenu menuWithTitle:@"لغة التغريدات" children:choices]]);
    }];
    return [UIMenu menuWithTitle:@"ترجمة التغريدة" children:@[options]];
}
static void updatePostBar(UIView *bar) {
    if (!bar.window || CGRectGetWidth(bar.bounds)<120) return;
    UIButton *button=objc_getAssociatedObject(bar,&postTranslateButton);
    CGFloat width=CGRectGetWidth(bar.bounds);
    CGFloat glyph=MIN(19,MAX(12,CGRectGetHeight(bar.bounds)-1));
    NSMutableArray<UIView *> *items=[NSMutableArray new];
    for (UIView *child in bar.subviews) {
        if (child==button || child.hidden || child.alpha<0.01 || CGRectIsEmpty(child.frame)) continue;
        [items addObject:child];
    }
    [items sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){
        return [@(CGRectGetMinX(a.frame)) compare:@(CGRectGetMinX(b.frame))];
    }];
    CGFloat slot=glyph+6, start=0, gap=0, end=0;
    for (UIView *child in items) {
        CGFloat x=CGRectGetMinX(child.frame);
        if (x-end>gap) {start=end;gap=x-end;}
        end=MAX(end,CGRectGetMaxX(child.frame));
    }
    if (width-end>gap) {start=end;gap=width-end;}
    if (gap<slot) {
        CGFloat used=0;
        for (UIView *child in items) used+=CGRectGetWidth(child.frame);
        CGFloat spacing=(width-used-slot)/MAX((CGFloat)items.count,1.0);
        if (spacing<1) {button.hidden=YES;return;}
        CGFloat x=0;
        for (UIView *child in items) {
            CGRect before=child.frame,after=before;
            after.origin.x=x;
            x+=CGRectGetWidth(after)+spacing;
            if (!CGRectEqualToRect(before,after)) {
                objc_setAssociatedObject(child,&postOriginalFrame,@[[NSValue valueWithCGRect:before],[NSValue valueWithCGRect:after]],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                child.frame=after;
            }
        }
        start=width-slot;gap=slot;
    }
    if (!button) {
        button=[UIButton buttonWithType:UIButtonTypeSystem];
        [button setImage:[UIImage systemImageNamed:@"globe"] forState:UIControlStateNormal];
        button.accessibilityLabel=@"ترجمة التغريدة";
        button.menu=postMenu(bar);button.showsMenuAsPrimaryAction=YES;
        [bar addSubview:button];
        objc_setAssociatedObject(bar,&postTranslateButton,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.tintColor=UIColor.secondaryLabelColor;
    [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:glyph-1 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
    button.hidden=NO;
    CGFloat w=MIN(gap,slot+4);
    button.frame=CGRectMake(start+(gap-w)/2,(CGRectGetHeight(bar.bounds)-24)/2,w,24);
}
%group XPostActions
%hook MXPostActionsView
- (void)layoutSubviews {
    UIView *bar=(UIView *)self;
    for (UIView *child in bar.subviews) {
        NSArray<NSValue *> *saved=objc_getAssociatedObject(child,&postOriginalFrame);
        if (!saved) continue;
        if (CGRectEqualToRect(child.frame,saved[1].CGRectValue)) child.frame=saved[0].CGRectValue;
        objc_setAssociatedObject(child,&postOriginalFrame,nil,OBJC_ASSOCIATION_ASSIGN);
    }
    %orig;
    updatePostBar(bar);
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *bar=(UIView *)self;
    UIButton *button=objc_getAssociatedObject(self,&postTranslateButton);
    if (button && bar.userInteractionEnabled && !bar.hidden && bar.alpha>0.01 && !button.hidden && CGRectContainsPoint(button.frame,point)) return button;
    return %orig;
}
%end
%end

%ctor {
    twitter=[NSBundle.mainBundle.bundleIdentifier isEqual:@"com.atebits.Tweetie2"];
    if (twitter || [NSBundle.mainBundle.bundleIdentifier isEqual:@"net.whatsapp.WhatsApp"]) {
        engine=[ConversationTranslator new];
        %init;
        Class postBar=NSClassFromString(@"TTAStatusInlineActionsView");
        if (twitter && postBar) { %init(XPostActions, MXPostActionsView=postBar); }
        Class xSend=NSClassFromString(@"ChatMessageComposer.ComposerActionAccessoryButton");
        if (twitter && xSend) { %init(XComposerSend, MXComposerSendButton=xSend); }
        if (!twitter && NSClassFromString(@"WAMessageAttributedTextSliceView")) { %init(AttributedSlice); }
    }
}

