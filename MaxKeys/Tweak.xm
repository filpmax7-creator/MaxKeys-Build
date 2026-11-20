#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>

@interface MKBar : UIView

@property(nonatomic,weak) UIView<UITextInput> *editor;
@property(nonatomic,strong) UIStackView *rows;
@property(nonatomic,strong) UIView *original;
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
-(void)layoutSubviews { [super layoutSubviews]; CGFloat height=CGRectGetHeight(self.bounds); _rows.frame=CGRectMake(0,height-44,self.bounds.size.width,44);
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
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.mlgm.kayoko.core.show"), NULL, NULL, true);
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

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            %init;
        }
    }
}
