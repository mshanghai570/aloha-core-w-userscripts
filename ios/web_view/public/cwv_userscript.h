// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_H_
#define IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_H_

#import <Foundation/Foundation.h>

@class CWVUserscriptMetadata;

NS_ASSUME_NONNULL_BEGIN

// A local userscript available to a CWVWebViewConfiguration.
@interface CWVUserscript : NSObject

@property(nonatomic, copy, readonly) NSURL* fileURL;
@property(nonatomic, copy, readonly) NSString* source;
@property(nonatomic, readonly) CWVUserscriptMetadata* metadata;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithFileURL:(NSURL*)fileURL
                                   error:(NSError* _Nullable*)error;

@end

NS_ASSUME_NONNULL_END

#endif  // IOS_WEB_VIEW_PUBLIC_CWV_USERSCRIPT_H_
