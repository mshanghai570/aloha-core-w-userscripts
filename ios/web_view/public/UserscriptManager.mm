#import "ios/web_view/public/UserscriptManager.h"
#import <Foundation/Foundation.h>

@interface UserscriptManager () {
  NSURL* _storageDirectory;
}
@end

@implementation UserscriptManager

- (instancetype)initWithStorageDirectory:(NSURL*)dir {
  self = [super init];
  if (self) {
    _storageDirectory = [dir copy];
  }
  return self;
}

- (void)injectMatchingUserscriptsIntoWebView:(id)webView
                                      forURL:(const url::GURL&)url {
  // Stub implementation: no-op. Real implementation should load
  // userscripts from _storageDirectory, match against `url`, and
  // inject into the webView at the appropriate run-at timing.
  (void)webView;
  (void)&url;
}

@end
