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
    return !twitter || (chat.length && [NSUserDefaults.standardUserDefaults boolForKey:[@"MaxTranslate.X.Google." stringByAppendingString:chat]]);
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
        [groups addObject:[UIAction actionWithTitle:@"تفعيل الترجمة عبر Google" image:nil identifier:nil handler:^(__unused UIAction *sender){
            UIAlertController *dialog=[UIAlertController alertControllerWithTitle:@"ترجمة هذه المحادثة" message:@"سيُرسل نص الرسائل الواردة والمسودات عند الإرسال إلى Google للترجمة. يمكنك إيقافها من هذه القائمة." preferredStyle:UIAlertControllerStyleAlert];
            [dialog addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
            [dialog addAction:[UIAlertAction actionWithTitle:@"تفعيل لهذه المحادثة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *selection){
                if (![chatID(weakVC) isEqual:chat]) return;
                [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"MaxTranslate.X.Google." stringByAppendingString:chat]];
                [engine setLanguage:@"en" forChat:chat];
                installMenu(weakVC);
                refreshViews(weakVC.view);
            }]];
            [weakVC presentViewController:dialog animated:YES completion:nil];
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
static char xLauncher;
static BOOL isDMComposer(UIView *editor) {
    for (UIResponder *r=editor; r && ![r isKindOfClass:UIWindow.class]; r=r.nextResponder) {
        NSString *name=NSStringFromClass(r.class).lowercaseString;
        if ([name containsString:@"directmessage"] || [name containsString:@"dmconversation"] ||
            [name containsString:@"dmcomposer"] || [name containsString:@"dmthread"] ||
            [name containsString:@"xchatconversation"]) return YES;
    }
    return NO;
}
static void showXOptions(UIViewController *vc, UIButton *anchor, NSString *chat, NSInteger page) {
    if (!chat.length || ![chatID(vc) isEqual:chat] || !vc.view.window || vc.presentedViewController) return;
    BOOL enabled=translationAllowed(chat);
    NSString *title=page==1 ? @"لغة الوارد" : page==2 ? @"لغة الصادر" : @"ترجمة رسائل X";
    NSString *message=enabled ? nil : @"عند التفعيل، يُرسل نص الوارد والمسودة عند الإرسال إلى Google للترجمة في هذه المحادثة.";
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    if (!enabled) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"تفعيل لهذه المحادثة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            if (![chatID(vc) isEqual:chat]) return;
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"MaxTranslate.X.Google." stringByAppendingString:chat]];
            [engine setLanguage:@"en" forChat:chat];
            refreshViews(vc.view);
        }]];
    } else if (page) {
        NSDictionary *names=@{@"en":@"\u0627\u0644\u0625\u0646\u062c\u0644\u064a\u0632\u064a\u0629",@"tr":@"\u0627\u0644\u062a\u0631\u0643\u064a\u0629",@"ar":@"\u0627\u0644\u0639\u0631\u0628\u064a\u0629",@"fr":@"\u0627\u0644\u0641\u0631\u0646\u0633\u064a\u0629",@"de":@"\u0627\u0644\u0623\u0644\u0645\u0627\u0646\u064a\u0629",@"es":@"\u0627\u0644\u0625\u0633\u0628\u0627\u0646\u064a\u0629",@"ru":@"\u0627\u0644\u0631\u0648\u0633\u064a\u0629",@"zh-CN":@"\u0627\u0644\u0635\u064a\u0646\u064a\u0629",@"ur":@"\u0627\u0644\u0623\u0631\u062f\u064a\u0629",@"hi":@"\u0627\u0644\u0647\u0646\u062f\u064a\u0629",@"id":@"\u0627\u0644\u0625\u0646\u062f\u0648\u0646\u064a\u0633\u064a\u0629"};
        for (NSString *code in [[names allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *current=page==1 ? incomingLanguage(chat) : setting(chat);
            NSString *label=[code isEqual:current] ? [@"✓ " stringByAppendingString:names[code]] : names[code];
            [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
                if (![chatID(vc) isEqual:chat]) return;
                if (page==1) [NSUserDefaults.standardUserDefaults setObject:code forKey:[@"MaxWhatsTranslate.incoming." stringByAppendingString:chat]];
                else [engine setLanguage:code forChat:chat];
                refreshViews(vc.view);
            }]];
        }
    } else {
        for (NSNumber *choice in @[@1,@2]) {
            [sheet addAction:[UIAlertAction actionWithTitle:choice.intValue==1 ? @"لغة الوارد" : @"لغة الصادر" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
                id<UIViewControllerTransitionCoordinator> transition=sheet.transitionCoordinator;
                void (^open)(void)=^{ showXOptions(vc,anchor,chat,choice.integerValue); };
                if (!transition || ![transition animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> ctx){ open(); }])
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),open);
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"إيقاف لهذه المحادثة" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
            for (NSString *prefix in @[@"MaxTranslate.X.Google.",@"MaxWhatsTranslate.incoming.",@"MaxWhatsTranslate.target."])
                [NSUserDefaults.standardUserDefaults removeObjectForKey:[prefix stringByAppendingString:chat]];
            refreshViews(vc.view);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView=anchor.window ? anchor : vc.view;
    sheet.popoverPresentationController.sourceRect=sheet.popoverPresentationController.sourceView.bounds;
    [vc presentViewController:sheet animated:YES completion:nil];
}
static void updateXComposer(UITextView *editor) {
    UIButton *old=objc_getAssociatedObject(editor,&xLauncher);
    UIViewController *vc=controller(editor);
    NSString *chat=chatID(vc);
    if (!editor.window || !editor.isFirstResponder || !editor.editable || (!isDMComposer(editor) && !chat.length)) {
        [old removeFromSuperview];
        objc_setAssociatedObject(editor,&xLauncher,nil,OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    if (old.superview==vc.view && old) return;
    if (!vc || ![editor isDescendantOfView:vc.view]) return;
    [old removeFromSuperview];
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityLabel=@"ترجمة هذه المحادثة";
    button.backgroundColor=UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius=18;
    [button setImage:[UIImage systemImageNamed:@"globe"] forState:UIControlStateNormal];
    __weak UITextView *weakEditor=editor;
    __weak UIButton *weakButton=button;
    [button addAction:[UIAction actionWithHandler:^(__unused UIAction *a){
        UITextView *field=weakEditor;
        UIViewController *owner=controller(field);
        NSString *key=chatID(owner);
        if (!key.length) { note(owner,[NSString stringWithFormat:@"تعذّر تحديد معرّف المحادثة. واجهة الكتابة: %@ · %@",NSStringFromClass(field.class),NSStringFromClass(owner.class)]); return; }
        showXOptions(owner,weakButton,key,0);
    }] forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:button];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [button.bottomAnchor constraintEqualToAnchor:editor.topAnchor constant:-4],
        [button.widthAnchor constraintEqualToConstant:36],[button.heightAnchor constraintEqualToConstant:36]]];
    objc_setAssociatedObject(editor,&xLauncher,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!twitter) installMenu(self);
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
    if (![outgoing isKindOfClass:NSNumber.class] || outgoing.boolValue) return;
    id body=property(model,@"text") ?: property(model,@"messageText") ?: (twitter ? property(model,@"fullText") : nil);
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
- (void)didMoveToWindow { %orig; if (twitter) updateXComposer(self); }
- (void)layoutSubviews { %orig; if (twitter && self.isFirstResponder) updateXComposer(self); translateView(self); }
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
%ctor {
    twitter=[NSBundle.mainBundle.bundleIdentifier isEqual:@"com.atebits.Tweetie2"];
    if (twitter || [NSBundle.mainBundle.bundleIdentifier isEqual:@"net.whatsapp.WhatsApp"]) {
        if (twitter) {
            for (NSString *event in @[UITextViewTextDidBeginEditingNotification,UITextViewTextDidEndEditingNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
                    if ([n.object isKindOfClass:UITextView.class]) updateXComposer(n.object);
                }];
            }
        }
        engine=[ConversationTranslator new];
        %init;
        if (!twitter && NSClassFromString(@"WAMessageAttributedTextSliceView")) { %init(AttributedSlice); }
    }
}