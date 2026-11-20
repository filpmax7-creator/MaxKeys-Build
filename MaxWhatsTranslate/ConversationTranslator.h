#import <Foundation/Foundation.h>
@interface ConversationTranslator : NSObject
// Invoke on the main thread. Supply the stable conversation identifier.
- (void)setLanguage:(NSString *)language forChat:(NSString *)chat;
- (void)translateDraft:(NSString *)draft chat:(NSString *)chat completion:(void (^)(NSString *))completion;
- (void)translateIncoming:(NSString *)text completion:(void (^)(NSString *))completion;
@end