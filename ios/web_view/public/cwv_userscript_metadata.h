// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_METADATA_H_
#define IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_METADATA_H_

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Parsed metadata from a Greasemonkey-compatible userscript header.
@interface CWVUserscriptMetadata : NSObject

// The user-visible name. Defaults to the script filename when the header does
// not declare @name.
@property(nonatomic, copy, readonly) NSString* name;

// URL patterns declared through @match or @include. A script with no include
// pattern is not injected.
@property(nonatomic, copy, readonly) NSArray<NSString*>* includePatterns;

// URL patterns declared through @exclude.
@property(nonatomic, copy, readonly) NSArray<NSString*>* excludePatterns;

// One of document-start, document-end, or document-idle. Unsupported values
// fall back to document-end.
@property(nonatomic, copy, readonly) NSString* runAt;

// Whether the script is restricted to the top-level document.
@property(nonatomic, readonly, getter=isForMainFrameOnly) BOOL forMainFrameOnly;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithUserscriptSource:(NSString*)source
                             fallbackName:(NSString*)fallbackName;

@end

NS_ASSUME_NONNULL_END

#endif  // IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_METADATA_H_
