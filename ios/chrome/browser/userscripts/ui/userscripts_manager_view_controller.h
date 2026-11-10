// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_UI_USERSCRIPTS_MANAGER_VIEW_CONTROLLER_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_UI_USERSCRIPTS_MANAGER_VIEW_CONTROLLER_H_

#import <UIKit/UIKit.h>

#import "ios/chrome/browser/settings/ui_bundled/settings_controller_protocol.h"
#import "ios/chrome/browser/settings/ui_bundled/settings_root_view_controlling.h"

class ProfileIOS;

@interface UserscriptsManagerViewController
    : UITableViewController <UIDocumentPickerDelegate,
                             SettingsControllerProtocol,
                             SettingsRootViewControlling>

@property(nonatomic, weak) id<SceneCommands> sceneHandler;
@property(nonatomic, weak) id<BrowserCommands> browserHandler;
@property(nonatomic, weak) id<SettingsCommands> settingsHandler;
@property(nonatomic, weak) id<SnackbarCommands> snackbarHandler;

- (instancetype)initWithProfile:(ProfileIOS*)profile;

- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_UI_USERSCRIPTS_MANAGER_VIEW_CONTROLLER_H_
