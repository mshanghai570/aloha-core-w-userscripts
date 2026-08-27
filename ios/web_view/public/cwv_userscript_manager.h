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

// Parses a prospective local script without installing it. Callers should show
// the parsed name and URL rules and obtain explicit user approval before calling
// |installUserscriptAtURL:error:|.
- (nullable CWVUserscript*)previewUserscriptAtURL:(NSURL*)fileURL
                                             error:(NSError* _Nullable*)error;

// Copies a validated UTF-8 `.js` script into |storageDirectory| and enables it.
// An existing file with the same name is replaced only after the source is
// successfully parsed. The caller should obtain explicit user approval first.
- (BOOL)installUserscriptAtURL:(NSURL*)fileURL
                         error:(NSError* _Nullable*)error;

// Persists the enabled state of an installed script and refreshes the registered
// content scripts. Returns NO if |identifier| does not refer to an installed
// script.
- (BOOL)setUserscriptEnabled:(BOOL)enabled
               forIdentifier:(NSString*)identifier
                       error:(NSError* _Nullable*)error;

// Removes an installed script and its persisted enabled-state entry. Returns NO
// if |identifier| does not refer to an installed script.
- (BOOL)removeUserscriptWithIdentifier:(NSString*)identifier
                                  error:(NSError* _Nullable*)error;

// Re-enumerates .js files in |storageDirectory|. Scripts without an @match or
// @include directive, unreadable files, and directories are ignored. Returns
// NO only when the directory itself cannot be prepared or enumerated.
- (BOOL)reloadUserscriptsWithError:(NSError* _Nullable*)error;

@end

NS_ASSUME_NONNULL_END

#endif  // IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_MANAGER_H_
