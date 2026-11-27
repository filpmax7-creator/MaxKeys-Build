#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ConversationTranslator.h"

static UIImage *conversationIcon(CGFloat width) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache=[NSCache new]; });
    NSNumber *key=@(round(width));
    UIImage *icon=[cache objectForKey:key];
    if (icon) return icon;
    CGFloat scale=key.doubleValue/32.0;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32*scale,26*scale)];
    icon=[[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c=ctx.CGContext;
        CGContextScaleCTM(c,scale,scale);
        CGContextSetLineWidth(c,1.65);
        CGContextSetLineCap(c,kCGLineCapRound);
        CGContextSetLineJoin(c,kCGLineJoinRound);
        for (NSUInteger index=0;index<2;index++) {
            CGContextSaveGState(c);
            if (index) { CGContextTranslateCTM(c,32,9); CGContextScaleCTM(c,-1,1); }
            UIBezierPath *path=[UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(5,1)];
            [path addLineToPoint:CGPointMake(16,1)];
            [path addQuadCurveToPoint:CGPointMake(20,5) controlPoint:CGPointMake(20,1)];
            [path addLineToPoint:CGPointMake(20,10)];
            [path addQuadCurveToPoint:CGPointMake(16,14) controlPoint:CGPointMake(20,14)];
            [path addLineToPoint:CGPointMake(7,14)];
            [path addLineToPoint:CGPointMake(2,16)];
            [path addLineToPoint:CGPointMake(3,13)];
            [path addQuadCurveToPoint:CGPointMake(1,9) controlPoint:CGPointMake(1,12)];
            [path addLineToPoint:CGPointMake(1,5)];
            [path addQuadCurveToPoint:CGPointMake(5,1) controlPoint:CGPointMake(1,1)];
            [path closePath];
            CGContextSetBlendMode(c,kCGBlendModeClear);
            CGContextAddPath(c,path.CGPath); CGContextFillPath(c);
            CGContextSetBlendMode(c,kCGBlendModeNormal);
            CGContextAddPath(c,path.CGPath); CGContextStrokePath(c);
            CGContextMoveToPoint(c,5,6); CGContextAddLineToPoint(c,16,6);
            CGContextMoveToPoint(c,5,10); CGContextAddLineToPoint(c,13,10);
            CGContextStrokePath(c);
            CGContextRestoreGState(c);
        }
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cache setObject:icon forKey:key];
    return icon;
}

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
        button=[[UIBarButtonItem alloc] initWithImage:conversationIcon(24) menu:menu];
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
    NSString *replyLanguage=[NSUserDefaults.standardUserDefaults stringForKey:@"MaxTranslate.ReplyLanguage"];
    BOOL inlineReply=[self.accessibilityIdentifier isEqual:@"PersistentReplySubmitButton"];
    if (twitter && replyLanguage.length && target && (inlineReply || [self.accessibilityIdentifier isEqual:@"ComposeSendTweetButton"])) {
        UIView *scope=self.window;
        if (inlineReply) {
            scope=self.superview;
            while (scope && ![scope isKindOfClass:NSClassFromString(@"T1PersistentComposeView")]) scope=scope.superview;
        }
        UITextView *editor=activeEditor(scope);
        UIResponder *context=editor;
        while (context && ![context isKindOfClass:NSClassFromString(@"T1TweetComposeSingleTweetViewController")]) context=context.nextResponder;
        if ((inlineReply || [[context valueForKey:@"isReply"] boolValue]) && editor.text.length) {
            if (objc_getAssociatedObject(editor,&sending)) return;
            NSString *draft=[editor.text copy];
            objc_setAssociatedObject(editor,&sending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UITextView *weakField=editor;
            __weak UIControl *weakButton=self;
            __weak id weakTarget=target;
            [engine translateIncoming:draft target:replyLanguage completion:^(NSString *result){
                UITextView *field=weakField;
                UIControl *button=weakButton;
                id receiver=weakTarget;
                if (!field) return;
                objc_setAssociatedObject(field,&sending,nil,OBJC_ASSOCIATION_ASSIGN);
                if (!button.window || !receiver || !field.isFirstResponder || field.window!=button.window || ![field.text isEqual:draft] ||
                    ![[NSUserDefaults.standardUserDefaults stringForKey:@"MaxTranslate.ReplyLanguage"] isEqual:replyLanguage]) return;
                if (!result.length) {note(controller(field),@"تعذّرت ترجمة الرد. مسودتك محفوظة.");return;}
                UITextRange *range=[field textRangeFromPosition:field.beginningOfDocument toPosition:field.endOfDocument];
                [field replaceRange:range withText:result];
                if ([field.text isEqual:result]) [UIApplication.sharedApplication sendAction:action to:receiver from:button forEvent:nil];
            }];
            return;
        }
    }
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
    if (!twitter && [owner isKindOfClass:NSClassFromString(@"WAMessageBubbleTableViewCell")]) {
        id message=property(owner,@"focusedMessage");
        if (deliveryDirection(message)) return message;
    }
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
        NSMutableArray *replyChoices=[NSMutableArray new];
        NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
        NSString *reply=[prefs stringForKey:@"MaxTranslate.ReplyLanguage"];
        UIAction *off=[UIAction actionWithTitle:@"إيقاف ترجمة الردود" image:nil identifier:nil handler:^(__unused UIAction *a){[prefs removeObjectForKey:@"MaxTranslate.ReplyLanguage"];}];
        off.state=reply.length?UIMenuElementStateOff:UIMenuElementStateOn;
        [replyChoices addObject:off];
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
            UIAction *choice=[UIAction actionWithTitle:item.title image:nil identifier:nil handler:^(__unused UIAction *a){[prefs setObject:code forKey:@"MaxTranslate.ReplyLanguage"];}];
            choice.state=[reply isEqual:code]?UIMenuElementStateOn:UIMenuElementStateOff;
            [replyChoices addObject:choice];
        }
        done(@[translate,[UIMenu menuWithTitle:@"لغة التغريدات" children:choices],[UIMenu menuWithTitle:@"لغة الردود" children:replyChoices]]);
    }];
    return [UIMenu menuWithTitle:@"ترجمة التغريدة" children:@[options]];
}
static void updatePostBar(UIView *bar) {
    if (!bar.window || CGRectGetWidth(bar.bounds)<120) return;
    UIButton *button=objc_getAssociatedObject(bar,&postTranslateButton);
    UIView *host=bar.superview;
    for (UIView *v=host;v;v=v.superview) {
        if ([v isKindOfClass:UITableViewCell.class]) {host=((UITableViewCell *)v).contentView;break;}
        if ([v isKindOfClass:UICollectionViewCell.class]) {host=((UICollectionViewCell *)v).contentView;break;}
    }
    if (!host) return;
    CGRect row=[bar convertRect:bar.bounds toView:host];
    CGFloat size=44;
    CGFloat centerY=MIN(MAX(CGRectGetMidY(row),size/2),CGRectGetMaxY(host.bounds)-size/2);
    CGRect slot=CGRectMake(CGRectGetMaxX(host.bounds)-size-2,centerY-size/2,size,size);
    CGFloat limit=CGRectGetMinX([host convertRect:slot toView:bar])-4;
    CGFloat width=CGRectGetWidth(bar.bounds);
    CGFloat glyph=MIN(19,MAX(12,CGRectGetHeight(bar.bounds)-1));
    if (limit<width && limit>0) {
        CGFloat factor=limit/width;
        for (UIView *child in bar.subviews) {
            if (child==button || child.hidden) continue;
            CGRect before=child.frame, after=before;
            after.origin.x*=factor;
            after.size.width*=factor;
            objc_setAssociatedObject(child,&postOriginalFrame,@[[NSValue valueWithCGRect:before],[NSValue valueWithCGRect:after]],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            child.frame=after;
        }
    }
    if (!button) {
        button=[UIButton buttonWithType:UIButtonTypeSystem];

        button.accessibilityLabel=@"ترجمة التغريدة";
        button.menu=postMenu(bar);button.showsMenuAsPrimaryAction=YES;
        [host addSubview:button];
        objc_setAssociatedObject(bar,&postTranslateButton,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.tintColor=UIColor.secondaryLabelColor;
    UIImage *icon=conversationIcon(glyph+1);
    if ([button imageForState:UIControlStateNormal]!=icon) [button setImage:icon forState:UIControlStateNormal];
    button.hidden=NO;
    if (button.superview!=host) [host addSubview:button];
    button.frame=slot;
    [host bringSubviewToFront:button];
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
- (void)willMoveToSuperview:(UIView *)next {
    if (next!=[(UIView *)self superview]) {
        UIButton *button=objc_getAssociatedObject(self,&postTranslateButton);
        [button removeFromSuperview];
    }
    %orig;
}
- (void)didMoveToWindow {
    %orig;
    UIView *bar=(UIView *)self;
    if (bar.window) [bar setNeedsLayout];
    else [(UIButton *)objc_getAssociatedObject(bar,&postTranslateButton) removeFromSuperview];
}
%end
%end

static char sileoItem, sileoRequest;
extern "C" void *MXDepictionRoot(const void *);
extern "C" void *MXDepictionText(const void *);
static void collectRenderedMarkdown(UIView *view, BOOL inMarkdown, NSMutableArray<NSString *> *parts) {
    if (view.hidden || view.alpha<0.01) return;
    NSString *type=NSStringFromClass(view.class);
    inMarkdown=inMarkdown || [type containsString:@"DepictionMarkdownView"];
    if (inMarkdown && [type hasSuffix:@"CSTextRenderView"]) {
        NSString *text=[view.accessibilityLabel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) [parts addObject:text];
        return;
    }
    for (UIView *child in view.subviews) collectRenderedMarkdown(child,inMarkdown,parts);
}
static void collectDescription(UIView *view, BOOL body, NSMutableArray *parts) {
    if (view.hidden || view.alpha<0.01) return;
    NSString *type=NSStringFromClass(view.class).lowercaseString;
    if ([view isKindOfClass:WKWebView.class]) { [parts addObject:view]; return; }
    body=body || [type containsString:@"markdown"] || [type containsString:@"depictionlabel"] || [type containsString:@"descriptionview"] || [type containsString:@"depictiontext"];
    if (body) {
        id value=CFBridgingRelease(MXDepictionText((__bridge const void *)view)) ?: property(view,@"attributedText") ?: property(view,@"attributedString") ?: property(view,@"text");
        if ([value isKindOfClass:NSAttributedString.class]) value=[value string];
        if ([value isKindOfClass:NSString.class] && [value length]) { [parts addObject:value]; return; }
    }
    for (UIView *child in view.subviews) collectDescription(child,body,parts);
}
static void translateSections(NSArray *chunks, NSUInteger index, NSString *code, NSMutableArray *output, void (^done)(NSString *)) {
    if (index==chunks.count) { done([output componentsJoinedByString:@"\n\n"]); return; }
    [engine translateIncoming:chunks[index] target:code completion:^(NSString *result){
        if (!result.length) { done(nil); return; }
        [output addObject:result];
        dispatch_async(dispatch_get_main_queue(), ^{translateSections(chunks,index+1,code,output,done);});
    }];
}
static void showSileoText(UIViewController *vc, NSString *body, NSString *code, NSObject *token) {
    if (!vc.view.window || vc.navigationController.topViewController!=vc || objc_getAssociatedObject(vc,&sileoRequest)!=token) return;
    __weak UIViewController *weak=vc;
    void (^present)(NSString *)=^(NSString *text){
        UIViewController *page=weak;
        if (!page || page.navigationController.topViewController!=page || !page.view.window || page.presentedViewController || objc_getAssociatedObject(page,&sileoRequest)!=token) return;
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"ترجمة وصف الحزمة" message:text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault handler:nil]];
        [page presentViewController:alert animated:YES completion:nil];
    };
    if (!body.length) { present(@"تعذّرت قراءة الوصف. انتظر تحميل صفحة الحزمة وحاول مرة ثانية."); return; }
    NSMutableArray *chunks=[NSMutableArray new];
    for (NSString *line in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *rest=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        while (rest.length) {
            NSUInteger length=MIN(rest.length,1000u);
            if (length<rest.length) {
                NSRange space=[rest rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet options:NSBackwardsSearch range:NSMakeRange(0,length)];
                if (space.location!=NSNotFound && space.location>0) length=space.location;
                else length=NSMaxRange([rest rangeOfComposedCharacterSequenceAtIndex:length-1]);
            }
            [chunks addObject:[rest substringToIndex:length]];
            rest=[[rest substringFromIndex:length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    translateSections(chunks,0,code,[NSMutableArray new],^(NSString *result){ present(result.length ? result : @"تعذّرت ترجمة الوصف. حاول مرة ثانية."); });
}
static void readSileoPage(UIViewController *page, NSString *code) {
    if (!page) return;
    NSObject *token=[NSObject new];
    objc_setAssociatedObject(page,&sileoRequest,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray *parts=[NSMutableArray new];
    collectRenderedMarkdown(page.view,NO,parts);
    if (parts.count) {
        showSileoText(page,[parts componentsJoinedByString:@"\n\n"],code,token);
        return;
    }
    UIView *root=CFBridgingRelease(MXDepictionRoot((__bridge const void *)page));
    if (root && [root isDescendantOfView:page.view]) collectDescription(root,YES,parts);
    else collectDescription(page.view,NO,parts);
    dispatch_group_t group=dispatch_group_create();
    NSString *script=@"(()=>{const root=document.querySelector('[itemprop=description],#description,.description,article,main')||document.body;if(!root)return '';const walk=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let n,out=[];while((n=walk.nextNode())){const p=n.parentElement;if(!p||!p.getClientRects().length||p.closest('script,style,nav,footer,button,textarea,select,[hidden]'))continue;const t=n.textContent.trim();if(t)out.push(t)}return out.join(' ')})()";
    for (NSUInteger i=0;i<parts.count;i++) {
        if (![parts[i] isKindOfClass:WKWebView.class]) continue;
        WKWebView *web=parts[i];
        dispatch_group_enter(group);
        [web evaluateJavaScript:script completionHandler:^(id value,NSError *error){
            parts[i]=[value isKindOfClass:NSString.class]?value:@"";
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group,dispatch_get_main_queue(),^{
        NSArray *unique=[[NSOrderedSet orderedSetWithArray:parts] array];
        showSileoText(page,[[unique componentsJoinedByString:@"\n\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],code,token);
    });
}
@interface MXLanguagePicker : UITableViewController <UISearchBarDelegate>
@property(nonatomic,copy) NSString *preferenceKey;
@property(nonatomic,copy) NSArray<NSDictionary *> *languages;
@property(nonatomic,copy) NSArray<NSDictionary *> *shown;
@property(nonatomic,copy) void (^choose)(NSString *);
@end
@implementation MXLanguagePicker
- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.title) self.title=@"لغة وصف الحزمة";
    if (!self.preferenceKey) self.preferenceKey=@"MaxTranslate.SileoLanguage";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(closePicker)];
    UISearchBar *search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,320,52)];
    search.delegate=self;
    search.placeholder=@"ابحث عن لغة";
    self.tableView.tableHeaderView=search;
    NSMutableArray *rows=[NSMutableArray new];
    NSLocale *ar=[NSLocale localeWithLocaleIdentifier:@"ar"], *en=[NSLocale localeWithLocaleIdentifier:@"en"];
    for (NSString *code in NSLocale.ISOLanguageCodes) {
        NSString *name=[NSLocale.currentLocale localizedStringForLanguageCode:code] ?: code;
        NSString *terms=[@[name,[ar localizedStringForLanguageCode:code] ?: code,[en localizedStringForLanguageCode:code] ?: code,code] componentsJoinedByString:@" "];
        [rows addObject:@{@"code":code,@"name":name,@"terms":terms}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];}];
    self.languages=rows; self.shown=rows;
}
- (void)closePicker { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)query {
    self.shown=query.length ? [self.languages filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"terms CONTAINS[cd] %@",query]] : self.languages;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return self.shown.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"language"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"language"];
    NSDictionary *row=self.shown[path.row]; cell.textLabel.text=row[@"name"];
    cell.accessoryType=[[NSUserDefaults.standardUserDefaults stringForKey:self.preferenceKey] isEqual:row[@"code"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSString *code=self.shown[path.row][@"code"];
    [NSUserDefaults.standardUserDefaults setObject:code forKey:self.preferenceKey];
    [self dismissViewControllerAnimated:YES completion:^{self.choose(code);}];
}
@end
static void installSileoMenu(UIViewController *vc) {
    NSString *type=[[NSStringFromClass(vc.class) componentsSeparatedByString:@"."] lastObject];
    if (![type isEqual:@"PackageViewController"] && ![type isEqual:@"NativePackageViewController"]) return;
    UINavigationItem *nav=vc.navigationItem;
    NSArray *items=nav.rightBarButtonItems;
    if (!items.count) return;
    UIBarButtonItem *button=objc_getAssociatedObject(vc,&sileoItem);
    if (button && [items containsObject:button]) return;
    if (!button) {
        __weak UIViewController *weak=vc;
        UIAction *open=[UIAction actionWithTitle:@"ترجمة وصف الحزمة" image:nil identifier:nil handler:^(__unused UIAction *action){
            MXLanguagePicker *picker=[MXLanguagePicker new];
            picker.choose=^(NSString *code){readSileoPage(weak,code);};
            [weak presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
        }];
        open.image=conversationIcon(24);
        button=[[UIBarButtonItem alloc] initWithPrimaryAction:open];
        button.accessibilityLabel=@"ترجمة وصف الحزمة";
        objc_setAssociatedObject(vc,&sileoItem,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(nav,&sileoItem,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nav.rightBarButtonItems=[items arrayByAddingObject:button];
}
static NSArray *sileoNavigationItems(UINavigationItem *nav, NSArray *items) {
    UIBarButtonItem *translation=objc_getAssociatedObject(nav,&sileoItem);
    if (!translation || [items containsObject:translation]) return items;
    return items.count ? [items arrayByAddingObject:translation] : @[translation];
}
%group SileoDescriptions
%hook UINavigationItem
- (void)setRightBarButtonItems:(NSArray *)items {
    %orig(sileoNavigationItems(self,items));
}
- (void)setRightBarButtonItems:(NSArray *)items animated:(BOOL)animated {
    %orig(sileoNavigationItems(self,items),animated);
}
%end
%hook UIViewController
- (void)viewDidLayoutSubviews { %orig; installSileoMenu(self); }
- (void)viewDidAppear:(BOOL)animated { %orig; installSileoMenu(self); }
%end
%end

static char igControl, igRequest, igCaption;
static UIResponder *igAncestor(UIResponder *r, NSString *type) {
    Class cls=NSClassFromString(type);
    for (;r;r=r.nextResponder) if ([r isKindOfClass:cls]) return r;
    return nil;
}
static NSString *igContext(UIResponder *r) {
    id thread=igAncestor(r,@"IGDirectThreadViewController");
    id ident=property(thread,@"threadId");
    if ([ident isKindOfClass:NSString.class] && [ident length]) return [@"IG.thread." stringByAppendingString:ident];
    if (igAncestor(r,@"IGStoryViewerViewController")) return @"IG.story";
    if (igAncestor(r,@"IGCommentComposerView")) return @"IG.comments";
    return nil;
}
static NSString *igKey(NSString *context, BOOL incoming) {
    return [context stringByAppendingString:incoming?@".incoming":@".outgoing"];
}
static void igPick(UIViewController *vc, NSString *key, NSString *title) {
    MXLanguagePicker *picker=[MXLanguagePicker new];
    picker.preferenceKey=key; picker.title=title;
    __weak UIViewController *weak=vc;
    picker.choose=^(__unused NSString *code){
        UIViewController *page=weak;
        [NSNotificationCenter.defaultCenter postNotificationName:@"MXIGLanguageChanged" object:page];
    };
    [vc presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}
static UIMenu *igMenu(UIViewController *vc, NSString *context) {
    __weak UIViewController *weak=vc;
    NSMutableArray *items=[NSMutableArray new];
    for (NSNumber *dir in ([context hasPrefix:@"IG.thread."] ? @[@NO,@YES] : @[@NO])) {
        NSString *title=dir.boolValue?@"لغة الوارد":([context isEqual:@"IG.comments"]?@"لغة التعليقات":([context isEqual:@"IG.story"]?@"لغة رد الستوري":@"لغة الصادر"));
        NSString *key=igKey(context,dir.boolValue);
        [items addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *action){igPick(weak,key,title);}]];
    }
    [items addObject:[UIAction actionWithTitle:@"إيقاف الترجمة" image:nil identifier:nil handler:^(__unused UIAction *action){
        for (NSNumber *dir in @[@NO,@YES]) [NSUserDefaults.standardUserDefaults removeObjectForKey:igKey(context,dir.boolValue)];
        [NSNotificationCenter.defaultCenter postNotificationName:@"MXIGLanguageChanged" object:weak];
    }]];
    return [UIMenu menuWithTitle:@"ترجمة إنستغرام" children:items];
}
static char igFieldContext;
static void igEditorButton(UITextView *field) {
    if (![field isKindOfClass:NSClassFromString(@"IGDirectKeyboardTextView")] && ![field isKindOfClass:NSClassFromString(@"IGTextViewImagePasteSupporting")]) return;
    UIView *host=field.superview;
    NSString *context=field.window?igContext(field):nil;
    UIButton *button=objc_getAssociatedObject(field,&igControl);
    if (!context || !host) { [button removeFromSuperview]; return; }
    if (!button) {
        button=[UIButton buttonWithType:UIButtonTypeSystem];
        [button setImage:conversationIcon(19) forState:UIControlStateNormal];
        button.accessibilityLabel=@"لغة الترجمة"; button.showsMenuAsPrimaryAction=YES;
        objc_setAssociatedObject(field,&igControl,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![context isEqual:objc_getAssociatedObject(button,&igFieldContext)]) {
        button.menu=igMenu(controller(field),context);
        objc_setAssociatedObject(button,&igFieldContext,context,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    if (button.superview!=host) [host addSubview:button];
    CGRect frame=[field convertRect:field.bounds toView:host];
    CGFloat width=MIN(32,CGRectGetWidth(frame));
    BOOL rtl=field.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    button.frame=CGRectMake(rtl?CGRectGetMinX(frame):CGRectGetMaxX(frame)-width,CGRectGetMinY(frame),width,CGRectGetHeight(frame));
    UIEdgeInsets inset=field.textContainerInset;
    if (rtl && inset.left<width+2) {inset.left=width+2;field.textContainerInset=inset;}
    if (!rtl && inset.right<width+2) {inset.right=width+2;field.textContainerInset=inset;}
    [host bringSubviewToFront:button];
}
static char igThreadOwner, igMenuContext;
static UIView *igCallIn(UIView *view) {
    if ([view isKindOfClass:NSClassFromString(@"IGDirectCallButton")]) return view;
    for (UIView *child in view.subviews) {
        UIView *hit=igCallIn(child);
        if (hit) return hit;
    }
    return nil;
}
static void igInstallHeader(UIViewController *vc, UINavigationBar *bar) {
    NSString *context=igContext(vc);
    UINavigationItem *item=bar.topItem;
    if (!context || !item || !bar.window || !igCallIn(bar)) return;
    UIBarButtonItem *button=objc_getAssociatedObject(vc,&igControl);
    if (!button) {
        button=[[UIBarButtonItem alloc] initWithImage:conversationIcon(23) menu:igMenu(vc,context)];
        button.accessibilityLabel=@"ترجمة المحادثة";
        objc_setAssociatedObject(vc,&igControl,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![context isEqual:objc_getAssociatedObject(button,&igMenuContext)]) {
        button.menu=igMenu(vc,context);
        objc_setAssociatedObject(button,&igMenuContext,context,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    NSArray *items=item.rightBarButtonItems ?: @[];
    if (items.firstObject==button) return;
    NSMutableArray *ordered=[items mutableCopy];
    [ordered removeObject:button]; [ordered insertObject:button atIndex:0];
    item.rightBarButtonItems=ordered;
}
%group IGFieldControls
%hook UITextView
- (void)layoutSubviews { %orig; igEditorButton(self); }
- (void)didMoveToWindow { %orig; igEditorButton(self); }
%end
%end
%group IGHeader
%hook MXIGThread
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc=(UIViewController *)self;
    UINavigationBar *bar=vc.navigationController.navigationBar;
    if (!bar) return;
    NSHashTable *owner=[NSHashTable weakObjectsHashTable];
    [owner addObject:vc]; objc_setAssociatedObject(bar,&igThreadOwner,owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    igInstallHeader(vc,bar);
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIViewController *vc=(UIViewController *)self;
    UINavigationBar *bar=vc.navigationController.navigationBar;
    if (!bar) return;
    NSHashTable *owner=objc_getAssociatedObject(bar,&igThreadOwner);
    if (owner.anyObject!=vc) return;
    objc_setAssociatedObject(bar,&igThreadOwner,nil,OBJC_ASSOCIATION_ASSIGN);
    UIBarButtonItem *button=objc_getAssociatedObject(vc,&igControl);
    if (button && [bar.topItem.rightBarButtonItems containsObject:button]) {
        NSMutableArray *items=[bar.topItem.rightBarButtonItems mutableCopy];
        [items removeObject:button]; bar.topItem.rightBarButtonItems=items;
    }
}
%end
%hook UINavigationBar
- (void)layoutSubviews {
    %orig;
    NSHashTable *owner=objc_getAssociatedObject(self,&igThreadOwner);
    UIViewController *vc=owner.anyObject;
    if (vc && vc.view.window) igInstallHeader(vc,self);
}
%end
%end
%group IGTranslation
%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    BOOL comment=action==NSSelectorFromString(@"onSendButtonTap") && igAncestor(self,@"IGCommentComposerView");
    NSString *label=self.accessibilityLabel.lowercaseString;
    BOOL send=[self isKindOfClass:NSClassFromString(@"IGDirectComposerButton")] && [@[@"send",@"إرسال",@"ارسال"] containsObject:label];
    if (!comment && !send) { %orig;return; }
    NSString *context=igContext(self);
    NSString *code=context?[NSUserDefaults.standardUserDefaults stringForKey:igKey(context,NO)]:nil;
    if (!code || !target) { %orig;return; }
    UIView *scope=(UIView *)igAncestor(self,comment?@"IGCommentComposerView":@"IGDirectComposer.IGDirectComposer");
    UITextView *field=activeEditor(scope);
    NSString *draft=[field.text copy];
    if (!draft.length || objc_getAssociatedObject(field,&sending)) return;
    objc_setAssociatedObject(field,&sending,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UITextView *weakField=field; __weak UIControl *weakButton=self; __weak id weakTarget=target;
    [engine translateIncoming:draft target:code completion:^(NSString *result){
        UITextView *f=weakField; UIControl *btn=weakButton; id receiver=weakTarget;
        if (!f) return;
        objc_setAssociatedObject(f,&sending,nil,OBJC_ASSOCIATION_ASSIGN);
        if (!f.window || f.window!=btn.window || !receiver || ![igContext(btn) isEqual:context] || ![f.text isEqual:draft] ||
            ![[NSUserDefaults.standardUserDefaults stringForKey:igKey(context,NO)] isEqual:code]) return;
        if (!result.length) {
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"تعذّرت الترجمة" message:@"مسودتك محفوظة." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"تم" style:UIAlertActionStyleDefault handler:nil]];
            [controller(f) presentViewController:alert animated:YES completion:nil]; return;
        }
        UITextRange *range=[f textRangeFromPosition:f.beginningOfDocument toPosition:f.endOfDocument];
        [f replaceRange:range withText:result];
        if ([f.text isEqual:result]) [UIApplication.sharedApplication sendAction:action to:receiver from:btn forEvent:nil];
    }];
}
%end
%end

static void igBubble(UIView *bubble) {
    NSString *context=igContext(bubble);
    if (!context || !bubble.window) return;
    UICollectionViewCell *cell=(id)igAncestor(bubble,@"IGDirectTextMessageUISwift.IGDirectTextMessageCell");
    if (!cell) return;
    id model=property(cell,@"messageCellViewModel");
    int32_t direction=model?MXOutgoingMessage((__bridge const void *)model):-1;
    UIView *textView=property(bubble,@"textView");
    id rich=property(textView,@"attributedText");
    if (![rich isKindOfClass:NSAttributedString.class] || ![textView respondsToSelector:@selector(setAttributedText:)]) return;
    NSArray *saved=objc_getAssociatedObject(bubble,&igCaption);
    NSAttributedString *original=([saved count]==2 && [rich isEqual:saved[1]])?saved[0]:rich;
    NSString *code=[NSUserDefaults.standardUserDefaults stringForKey:igKey(context,YES)];
    if (direction<0) {
        CGRect frame=[bubble convertRect:bubble.bounds toView:cell.contentView];
        CGFloat left=CGRectGetMinX(frame),right=CGRectGetWidth(cell.contentView.bounds)-CGRectGetMaxX(frame);
        if (fabs(left-right)>6) {
            BOOL leading=cell.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft?right<left:left<right;
            direction=leading?0:1;
        }
    }
    if (!code || direction!=0 || !original.length) {
        objc_setAssociatedObject(bubble,&igRequest,nil,OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(bubble,&igCaption,nil,OBJC_ASSOCIATION_ASSIGN);
        if (original!=rich) [textView setValue:original forKey:@"attributedText"];
        return;
    }
    NSArray *key=@[context,code,original.string];
    if ([key isEqual:objc_getAssociatedObject(bubble,&igRequest)] && (!saved || [rich isEqual:saved[1]])) return;
    objc_setAssociatedObject(bubble,&igRequest,key,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weak=bubble;
    [engine translateIncoming:original.string target:code completion:^(NSString *result){
        UIView *v=weak;
        if (!v.window || ![igContext(v) isEqual:context] || ![objc_getAssociatedObject(v,&igRequest) isEqual:key] ||
            ![[NSUserDefaults.standardUserDefaults stringForKey:igKey(context,YES)] isEqual:code]) return;
        if (!result.length) {objc_setAssociatedObject(v,&igRequest,nil,OBJC_ASSOCIATION_ASSIGN);return;}
        if ([result isEqual:original.string]) return;
        UIView *display=property(v,@"textView");
        if (![property(display,@"attributedText") isEqual:rich]) return;
        NSMutableAttributedString *combined=[original mutableCopy];
        [combined appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:result] attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote],NSForegroundColorAttributeName:UIColor.secondaryLabelColor}]];
        objc_setAssociatedObject(v,&igCaption,@[original,combined],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [display setValue:combined forKey:@"attributedText"]; [display invalidateIntrinsicContentSize];
    }];
}
%group IGBubbles
%hook MXIGBubble
- (void)layoutSubviews { %orig; igBubble((UIView *)self); }
%end
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.burbn.instagram"]) {
        engine=[ConversationTranslator new];
        Class thread=NSClassFromString(@"IGDirectThreadViewController");
        %init(IGFieldControls);
        %init(IGTranslation);
        if (thread) { %init(IGHeader, MXIGThread=thread); }
        Class bubbleClass=NSClassFromString(@"IGDirectTextMessageBubbleView");
        if (bubbleClass) { %init(IGBubbles, MXIGBubble=bubbleClass); }
        [NSNotificationCenter.defaultCenter addObserverForName:UITextViewTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){igEditorButton(n.object);}];
        [NSNotificationCenter.defaultCenter addObserverForName:@"MXIGLanguageChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
            UIViewController *vc=n.object;
            NSMutableArray *views=[NSMutableArray new]; if(vc.view) [views addObject:vc.view];
            for(NSUInteger i=0;i<views.count;i++){UIView *v=views[i]; if ([v isKindOfClass:bubbleClass]) [v setNeedsLayout]; [views addObjectsFromArray:v.subviews];}
        }];
        return;
    }
    if ([NSBundle.mainBundle.bundleIdentifier.lowercaseString hasPrefix:@"org.coolstar.sileo"]) { engine=[ConversationTranslator new]; %init(SileoDescriptions); return; }
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

