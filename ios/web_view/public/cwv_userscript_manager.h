// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_MANAGER_H_
#define IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_MANAGER_H_

#import <Foundation/Foundation.h>

@class CWVUserContentController;
@class CWVUserscript;

NS_ASSUME_NONNULL_BEGIN

// Loads local userscripts and registers their guarded source with the user
// content controller associated with a web-view configuration.
@interface CWVUserscriptManager : NSObject

@property(nonatomic, copy, readonly) NSURL* storageDirectory;
@property(nonatomic, copy, readonly) NSArray<CWVUserscript*>* userscripts;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageDirectory:(NSURL*)storageDirectory
                   userContentController:
                       (CWVUserContentController*)userContentController;

// Re-enumerates .js files in |storageDirectory|. Scripts without an @match or
// @include directive, unreadable files, and directories are ignored. Returns
// NO only when the directory itself cannot be prepared or enumerated.
- (BOOL)reloadUserscriptsWithError:(NSError* _Nullable*)error;

@end

NS_ASSUME_NONNULL_END

#endif  // IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_MANAGER_H_
