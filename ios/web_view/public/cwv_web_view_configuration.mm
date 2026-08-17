// Copyright 2017 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_web_view_configuration.h"

#import "cwv_preferences.h"
#import "cwv_user_content_controller.h"
#import "cwv_autofill_data_manager.h"
#import "cwv_leak_check_service.h"
#import "cwv_reuse_check_service.h"

#import "ios/web_view/public/UserscriptManager.h"

@interface CWVWebViewConfiguration () {
  // The BrowserState for this configuration.
  std::unique_ptr<ios_web_view::WebViewBrowserState> _browserState;
  // Holds all CWVWebViews created with this class. Weak references.
  NSHashTable* _webViews;
  // The userscript manager for this configuration.
  UserscriptManager* _userscriptManager;
}
@end

@implementation CWVWebViewConfiguration

@synthesize autofillDataManager = _autofillDataManager;
@synthesize leakCheckService = _leakCheckService;
@synthesize reuseCheckService = _reuseCheckService;
@synthesize preferences = _preferences;
@synthesize syncController = _syncController;
@synthesize userContentController = _userContentController;
@synthesize userscriptManager = _userscriptManager;

- (instancetype)initWithBrowserState:
    (std::unique_ptr<ios_web_view::WebViewBrowserState>)browserState {
  self = [super init];
  if (self) {
    _browserState = std::move(browserState);
    _preferences =
        [[CWVPreferences alloc] initWithPrefService:_browserState->GetPrefs()];
    _userContentController =
        [[CWVUserContentController alloc] initWithConfiguration:self];
    _webViews = [NSHashTable weakObjectsHashTable];
    // Initialize userscript manager
    _userscriptManager = [[UserscriptManager alloc]
        initWithStorageDirectory:[self _userscriptsStorageDirectory]];
  }
  return self;
}

- (NSURL*)_userscriptsStorageDirectory {
  NSURL* browserStateDir = [NSURL fileURLWithPath:_browserState->GetStatePath().path];
  return [browserStateDir URLByAppendingPathComponent:@"Userscripts"];
}

@end
