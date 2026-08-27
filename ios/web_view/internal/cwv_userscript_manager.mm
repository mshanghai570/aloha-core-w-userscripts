// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript_manager.h"

#import "ios/web_view/public/cwv_user_content_controller.h"
#import "ios/web_view/public/cwv_user_script.h"
#import "ios/web_view/public/cwv_userscript.h"
#import "ios/web_view/public/cwv_userscript_metadata.h"

namespace {

NSString* JSONString(id value) {
  NSData* data = [NSJSONSerialization dataWithJSONObject:value
                                                  options:0
                                                    error:nil];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

NSString* GuardedSource(CWVUserscript* userscript) {
  CWVUserscriptMetadata* metadata = userscript.metadata;
  NSDictionary* rules = @{
    @"includePatterns" : metadata.includePatterns,
    @"excludePatterns" : metadata.excludePatterns,
  };
  NSString* rulesJSON = JSONString(rules);
  NSString* source = userscript.source;
  NSString* invocation = [NSString
      stringWithFormat:@"(function() {\\n%@\\n}).call(window);", source];
  if ([metadata.runAt isEqualToString:@"document-idle"]) {
    invocation = [NSString stringWithFormat:
        @"if (document.readyState === 'complete') {\\n%@\\n} else {\\n"
         "  window.addEventListener('load', function() {\\n%@\\n}, {once: true});\\n"
         "}",
        invocation, invocation];
  }

  return [NSString stringWithFormat:
      @"(function() {\\n"
       "  const rules = %@;\\n"
       "  const patternMatches = function(pattern, value) {\\n"
       "    if (pattern === '<all_urls>') return /^(https?|file|ftp):/.test(value);\\n"
       "    const escaped = pattern.replace(/[.+?^${}()|[\\]\\\\]/g, '\\\\$&');\\n"
       "    const expression = '^' + escaped.replace('://*\\\\.', '://(?:[^/]+\\\\.)?')"
       ".replace(/\\*/g, '.*') + '$';\\n"
       "    return new RegExp(expression).test(value);\\n"
       "  };\\n"
       "  const currentURL = window.location.href;\\n"
       "  if (!rules.includePatterns.some(function(pattern) { return patternMatches(pattern, currentURL); }) ||\\n"
       "      rules.excludePatterns.some(function(pattern) { return patternMatches(pattern, currentURL); })) {\\n"
       "    return;\\n"
       "  }\\n"
       "  %@\\n"
       "})();",
      rulesJSON, invocation];
}

CWVUserScriptInjectionTime InjectionTimeForMetadata(
    CWVUserscriptMetadata* metadata) {
  return [metadata.runAt isEqualToString:@"document-start"]
             ? CWVUserScriptInjectionTimeAtDocumentStart
             : CWVUserScriptInjectionTimeAtDocumentEnd;
}

}  // namespace

@interface CWVUserscriptManager () {
  CWVUserContentController* _userContentController;
  NSArray<CWVUserScript*>* _registeredUserScripts;
}
@end

@implementation CWVUserscriptManager

@synthesize storageDirectory = _storageDirectory;
@synthesize userscripts = _userscripts;

- (instancetype)initWithStorageDirectory:(NSURL*)storageDirectory
                   userContentController:
                       (CWVUserContentController*)userContentController {
  self = [super init];
  if (self) {
    _storageDirectory = [storageDirectory copy];
    _userContentController = userContentController;
    _userscripts = @[];
    _registeredUserScripts = @[];
    NSError* error = nil;
    if (![self reloadUserscriptsWithError:&error]) {
      NSLog(@"Unable to load userscripts: %@", error);
    }
  }
  return self;
}

- (BOOL)reloadUserscriptsWithError:(NSError* _Nullable*)error {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  if (![fileManager createDirectoryAtURL:_storageDirectory
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:error]) {
    return NO;
  }

  NSArray<NSURL*>* fileURLs = [fileManager
      contentsOfDirectoryAtURL:_storageDirectory
     includingPropertiesForKeys:@[ NSURLIsRegularFileKey ]
                        options:NSDirectoryEnumerationSkipsHiddenFiles
                          error:error];
  if (!fileURLs) {
    return NO;
  }

  NSArray<NSURL*>* sortedFileURLs = [fileURLs sortedArrayUsingComparator:
      ^NSComparisonResult(NSURL* left, NSURL* right) {
        return [left.lastPathComponent
            compare:right.lastPathComponent
            options:NSCaseInsensitiveSearch];
      }];

  NSMutableArray<CWVUserscript*>* loadedUserscripts = [NSMutableArray array];
  NSMutableArray<CWVUserScript*>* newRegisteredScripts = [NSMutableArray array];
  for (NSURL* fileURL in sortedFileURLs) {
    NSNumber* isRegularFile = nil;
    if (![fileURL getResourceValue:&isRegularFile
                            forKey:NSURLIsRegularFileKey
                             error:nil] || !isRegularFile.boolValue ||
        ![[fileURL.pathExtension lowercaseString] isEqualToString:@"js"]) {
      continue;
    }

    NSError* readError = nil;
    CWVUserscript* userscript = [[CWVUserscript alloc] initWithFileURL:fileURL
                                                                   error:&readError];
    if (!userscript) {
      NSLog(@"Skipping unreadable userscript %@: %@", fileURL, readError);
      continue;
    }
    if (!userscript.metadata.includePatterns.count) {
      NSLog(@"Skipping userscript %@ because it has no @match or @include rule.",
            userscript.fileURL.lastPathComponent);
      continue;
    }

    CWVUserScript* injectedScript = [[CWVUserScript alloc]
        initWithSource:GuardedSource(userscript)
        forMainFrameOnly:userscript.metadata.isForMainFrameOnly
        injectionTime:InjectionTimeForMetadata(userscript.metadata)];
    [loadedUserscripts addObject:userscript];
    [newRegisteredScripts addObject:injectedScript];
  }

  for (CWVUserScript* oldScript in _registeredUserScripts) {
    [_userContentController removeUserScript:oldScript];
  }
  for (CWVUserScript* newScript in newRegisteredScripts) {
    [_userContentController addUserScript:newScript];
  }
  _registeredUserScripts = [newRegisteredScripts copy];
  _userscripts = [loadedUserscripts copy];
  return YES;
}

@end
