#import <Foundation/Foundation.h>

namespace url { class GURL; }
@class CWVWebView;

NS_ASSUME_NONNULL_BEGIN

@interface UserscriptManager : NSObject
- (instancetype)initWithStorageDirectory:(NSURL*)dir;
- (void)injectMatchingUserscriptsIntoWebView:(CWVWebView*)webView
                                      forURL:(const url::GURL&)url;
@end

NS_ASSUME_NONNULL_END
