// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript.h"

#import "ios/web_view/public/cwv_userscript_metadata.h"

@implementation CWVUserscript

@synthesize fileURL = _fileURL;
@synthesize identifier = _identifier;
@synthesize source = _source;
@synthesize metadata = _metadata;
@synthesize enabled = _enabled;

- (nullable instancetype)initWithFileURL:(NSURL*)fileURL
                                 enabled:(BOOL)enabled
                                   error:(NSError* _Nullable*)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSError* readError = nil;
  NSString* source = [NSString stringWithContentsOfURL:fileURL
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
  if (!source) {
    if (error) {
      *error = readError;
    }
    return nil;
  }

  _fileURL = [fileURL copy];
  _identifier = [fileURL.lastPathComponent copy];
  _source = [source copy];
  _enabled = enabled;
  _metadata = [[CWVUserscriptMetadata alloc]
      initWithUserscriptSource:source
                   fallbackName:fileURL.lastPathComponent];
  return self;
}

@end
