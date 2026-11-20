#import "ConversationTranslator.h"
#import <NaturalLanguage/NaturalLanguage.h>
@interface Translator : NSObject
+ (void)translate:(NSString *)text to:(NSString *)language completion:(void (^)(NSString *))completion;
@end
@implementation ConversationTranslator {
    NSCache *_cache;
    NSMutableDictionary *_pending;
}
- (instancetype)init {
    if ((self = [super init])) {
        _cache = [NSCache new];
        _cache.countLimit = 300;
        _pending = [NSMutableDictionary new];
    }
    return self;
}
- (void)setLanguage:(NSString *)language forChat:(NSString *)chat {
    if (!chat.length || !language.length) return;
    [NSUserDefaults.standardUserDefaults setObject:language forKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]];
}
- (void)translateDraft:(NSString *)draft chat:(NSString *)chat completion:(void (^)(NSString *))completion {
    if (!chat.length || !draft.length) { completion(nil); return; }
    NSString *target = [NSUserDefaults.standardUserDefaults stringForKey:[@"MaxWhatsTranslate.target." stringByAppendingString:chat]] ?: @"en";
    [self translate:draft target:target completion:completion];
}
- (void)translateIncoming:(NSString *)text completion:(void (^)(NSString *))completion {
    if (!text.length || [[NLLanguageRecognizer dominantLanguageForString:text] isEqual:@"ar"]) { completion(nil); return; }
    [self translate:text target:@"ar" completion:completion];
}
- (void)translate:(NSString *)text target:(NSString *)target completion:(void (^)(NSString *))completion {
    NSArray *key = @[target, text];
    NSString *cached = [_cache objectForKey:key];
    if (cached) { completion(cached); return; }
    if (_pending[key]) { [_pending[key] addObject:[completion copy]]; return; }
    _pending[key] = [NSMutableArray arrayWithObject:[completion copy]];
    [Translator translate:text to:target completion:^(NSString *result) {
        NSArray *callbacks = [self->_pending[key] copy];
        [self->_pending removeObjectForKey:key];
        if (result.length) [self->_cache setObject:result forKey:key];
        for (void (^callback)(NSString *) in callbacks) callback(result);
    }];
}
@end