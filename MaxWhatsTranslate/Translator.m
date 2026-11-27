// Copyright (c) 2026 ZERo. All rights reserved.
#import <Foundation/Foundation.h>

typedef void (^TranslationHandler)(NSString * _Nullable result);

@interface Translator : NSObject
+ (void)translate:(NSString *)text to:(NSString *)language completion:(TranslationHandler)completion;
@end

@implementation Translator

static const int kMaxAttempts = 4;

+ (NSArray<NSString *> *)hosts {
    return @[ @"translate.googleapis.com", @"translate.google.com" ];
}

+ (NSString *)encode:(NSString *)string {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

+ (NSString *)parse:(NSData *)data response:(NSURLResponse *)response {
    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
    if (!data || http.statusCode != 200) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSArray.class] || ![[root firstObject] isKindOfClass:NSArray.class]) return nil;
    NSMutableString *result = [NSMutableString string];
    for (id segment in [root firstObject]) {
        id piece = [segment isKindOfClass:NSArray.class] ? [segment firstObject] : nil;
        if ([piece isKindOfClass:NSString.class]) [result appendString:piece];
    }
    return result.length ? result : nil;
}

+ (void)translate:(NSString *)text to:(NSString *)language attempt:(int)attempt completion:(TranslationHandler)completion {
    if (attempt >= kMaxAttempts) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSArray *hosts = [self hosts];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/translate_a/single", hosts[attempt % hosts.count]]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 8;
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    NSString *body = [NSString stringWithFormat:@"client=gtx&sl=auto&tl=%@&dt=t&q=%@", language, [self encode:text]];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *result = error ? nil : [self parse:data response:response];
        if (result) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
            return;
        }
        int64_t delay = (int64_t)(0.4 * (attempt + 1) * NSEC_PER_SEC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self translate:text to:language attempt:attempt + 1 completion:completion];
        });
    }] resume];
}

+ (void)translate:(NSString *)text to:(NSString *)language completion:(TranslationHandler)completion {
    // In a chat greeting the following word is often a person's name.
    NSRegularExpression *greeting = [NSRegularExpression regularExpressionWithPattern:@"^(هلو|هلا|مرحبا|مرحبًا|أهلًا|اهلا|أهلا)[،, ]+([اآأ]يات)([!.؟، ]*)$" options:0 error:nil];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSTextCheckingResult *match = [greeting firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (match && [language isEqualToString:@"en"]) {
        NSString *reply = [@"Hello Ayat" stringByAppendingString:[trimmed substringWithRange:[match rangeAtIndex:3]]];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(reply); });
        return;
    }
    [self translate:text to:language attempt:0 completion:completion];
}

@end