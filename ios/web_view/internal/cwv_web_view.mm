// Copyright 2014 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <WebKit/WebKit.h>

#import <memory>
#import <utility>
#import <vector>

#import "base/apple/foundation_util.h"
#import "base/check.h"
#import "base/bind.h"
#import "base/functional/bind.h"
#import "base/json/json_writer.h"
#import "base/notreached.h"
#import "base/strings/sys_string_conversions.h"
#import "components/autofill/ios/browser/autofill_agent.h"
#import "components/password_manager/core/browser/password_manager.h"
#import "components/password_manager/ios/password_controller_driver_helper.h"
#import "components/safe_browsing/ios/browser/safe_browsing_url_allow_list.h"
#import "components/url_formatter/elide_url.h"
#import "ios/components/security_interstitials/lookalikes/lookalike_url_container.h"
#import "ios/components/security_interstitials/lookalike_url_tab_allow_list.h"
#import "ios/components/security_interstitials/lookalike_url_tab_helper.h"
#import "ios/web/navigation/nscodeer_util.h"
#import "ios/web/public/favicon/favicon_url.h"
#import "ios/web/public/js_messaging/web_frame.h"
#import "ios/web/public/js_messaging/web_frames_manager.h"
#import "ios/web/public/navigation/navigation_context.h"
#import "ios/web/public/navigation/navigation_item.h"
#import "ios/web/public/navigation/navigation_manager.h"
#import "ios/web/public/navigation/referrer.h"
#import "ios/web/public/navigation/reload_type.h"
#import "ios/web/public/navigation/restore_type.h"
#import "ios/web/public/session/proto/metadata.pb.h"
#import "ios/web/public/session/proto/storage.pb.h"
#import "ios/web/public/ui/context_menu_params.h"
#import "ios/web/public/ui/cwv_web_view_proxy.h"
#import "ios/web/public/ui/cwv_web_view_scroll_view_proxy.h"
#import "ios/web/public/web_client.h"
#import "ios/web/public/web_state.h"
#import "ios/web/public/web_view.h"
#import "ios/web/public/web_view_state.h"
#import "ios/web/public/web_view_user_data_holder.h"
#import "ios/web/public/web_view_user_data.h"
#import "ios/web/public/cwv_web_view_configuration.h"

#import "cwv_preferences.h"
#import "cwv_user_content_controller.h"
#import "cwv_autofill_data_manager.h"
#import "cwv_leak_check_service.h"
#import "cwv_reuse_check_service.h"

// Userscripts manager import
#import "ios/web_view/public/UserscriptManager.h"

@interface CWVWebView ()
// ... existing ivars and declarations ...
@end

@implementation CWVWebView

// (The rest of the file remains; we'll modify two navigation callbacks below.)

// === webState:didStartNavigation: ===
- (void)webState:(web::WebState*)webState
    didStartNavigation:(web::NavigationContext*)navigation {
  [self updateNavigationAvailability];
  if (!navigation->IsSameDocument()) {
    SEL oldSelector = @selector(webViewDidStartProvisionalNavigation:);
    if ([_navigationDelegate respondsToSelector:oldSelector]) {
      [_navigationDelegate webViewDidStartProvisionalNavigation:self];
    }
    SEL newSelector = @selector(webViewDidStartNavigation:);
    if ([_navigationDelegate respondsToSelector:newSelector]) {
      [_navigationDelegate webViewDidStartNavigation:self];
    }
  }
  // Inject userscripts at document-start
  if (navigation && !navigation->IsSameDocument()) {
    [_configuration.userscriptManager
        injectMatchingUserscriptsIntoWebView:self
        forURL:webState->GetVisibleURL()];
  }
}

// === webState:didFinishNavigation: ===
- (void)webState:(web::WebState*)webState
    didFinishNavigation:(web::NavigationContext*)navigation {
  [self updateNavigationAvailability];
  [self updateCurrentURLs];
  // TODO(crbug.com/41422373): Remove this once crbug.com/898357 is fixed.
  [self updateVisibleSSLStatus];
  if (navigation->HasCommitted() && !navigation->IsSameDocument() &&
      [_navigationDelegate
          respondsToSelector:@selector(webViewDidCommitNavigation:)]) {
    [_navigationDelegate webViewDidCommitNavigation:self];
  }
  NSError* error = navigation->GetError();
  SEL selector = @selector(webView:didFailNavigationWithError:);
  if (error && [_navigationDelegate respondsToSelector:selector]) {
    [_navigationDelegate webView:self didFailNavigationWithError:error];
  }
  // Inject userscripts at document-end
  if (navigation && navigation->HasCommitted()) {
    [_configuration.userscriptManager
        injectMatchingUserscriptsIntoWebView:self
        forURL:webState->GetVisibleURL()];
  }
}

// (Remaining implementation unchanged)

@end
