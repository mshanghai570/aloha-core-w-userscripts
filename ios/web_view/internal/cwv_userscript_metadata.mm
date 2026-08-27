// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript_metadata.h"

namespace {

NSString* TrimmedString(NSString* string) {
  return [string stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

}  // namespace

@implementation CWVUserscriptMetadata

@synthesize name = _name;
@synthesize includePatterns = _includePatterns;
@synthesize excludePatterns = _excludePatterns;
@synthesize runAt = _runAt;
@synthesize forMainFrameOnly = _forMainFrameOnly;

- (instancetype)initWithUserscriptSource:(NSString*)source
                             fallbackName:(NSString*)fallbackName {
  self = [super init];
  if (!self) {
    return nil;
  }

  NSMutableArray<NSString*>* includePatterns = [NSMutableArray array];
  NSMutableArray<NSString*>* excludePatterns = [NSMutableArray array];
  NSString* name = fallbackName;
  NSString* runAt = @"document-end";
  BOOL forMainFrameOnly = NO;

  NSRange openingMarker = [source rangeOfString:@"// ==UserScript=="];
  if (openingMarker.location != NSNotFound) {
    NSRange searchRange = NSMakeRange(
        NSMaxRange(openingMarker), source.length - NSMaxRange(openingMarker));
    NSRange closingMarker = [source rangeOfString:@"// ==/UserScript=="
                                            options:0
                                              range:searchRange];
    if (closingMarker.location != NSNotFound) {
      NSRange blockRange = NSMakeRange(
          NSMaxRange(openingMarker), closingMarker.location - NSMaxRange(openingMarker));
      NSString* block = [source substringWithRange:blockRange];
      NSArray<NSString*>* lines = [block
          componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
      for (NSString* rawLine in lines) {
        NSString* line = TrimmedString(rawLine);
        if (![line hasPrefix:@"//"]) {
          continue;
        }
        NSString* directive = TrimmedString([line substringFromIndex:2]);
        if (![directive hasPrefix:@"@"]) {
          continue;
        }
        NSRange whitespace = [directive rangeOfCharacterFromSet:
                                               [NSCharacterSet whitespaceCharacterSet]];
        NSString* key = whitespace.location == NSNotFound
                            ? directive
                            : [directive substringToIndex:whitespace.location];
        NSString* value = whitespace.location == NSNotFound
                             ? @""
                             : TrimmedString([directive substringFromIndex:
                                                   whitespace.location]);
        if ([key isEqualToString:@"@name"] && value.length) {
          name = value;
        } else if (([key isEqualToString:@"@match"] ||
                    [key isEqualToString:@"@include"]) && value.length) {
          [includePatterns addObject:value];
        } else if ([key isEqualToString:@"@exclude"] && value.length) {
          [excludePatterns addObject:value];
        } else if ([key isEqualToString:@"@run-at"] &&
                   ([value isEqualToString:@"document-start"] ||
                    [value isEqualToString:@"document-end"] ||
                    [value isEqualToString:@"document-idle"])) {
          runAt = value;
        } else if ([key isEqualToString:@"@noframes"]) {
          forMainFrameOnly = YES;
        }
      }
    }
  }

  _name = [name copy];
  _includePatterns = [includePatterns copy];
  _excludePatterns = [excludePatterns copy];
  _runAt = [runAt copy];
  _forMainFrameOnly = forMainFrameOnly;
  return self;
}

@end
