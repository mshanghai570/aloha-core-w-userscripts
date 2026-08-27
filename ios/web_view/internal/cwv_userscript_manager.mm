// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript_manager.h"

#import "ios/web_view/public/cwv_user_content_controller.h"
#import "ios/web_view/public/cwv_user_script.h"
#import "ios/web_view/public/cwv_userscript.h"
#import "ios/web_view/public/cwv_userscript_metadata.h"

namespace {

NSString* const kCWVUserscriptManagerErrorDomain =
    @"org.alohabrowser.userscripts";
NSString* const kEnabledUserscriptsFilename = @"EnabledUserscripts.plist";
constexpr NSUInteger kMaximumUserscriptSizeBytes = 1024 * 1024;

NS_ENUM(NSInteger, CWVUserscriptManagerErrorCode) {
  CWVUserscriptManagerErrorInvalidFile = 1,
  CWVUserscriptManagerErrorInvalidMetadata = 2,
  CWVUserscriptManagerErrorUnknownScript = 3,
  CWVUserscriptManagerErrorUnableToPersistState = 4,
};

void SetError(NSError* _Nullable* error,
              CWVUserscriptManagerErrorCode code,
              NSString* description) {
  if (error) {
    *error = [NSError errorWithDomain:kCWVUserscriptManagerErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : description}];
  }
}

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
  NSURL* _enabledStateFileURL;
  NSMutableDictionary<NSString*, NSNumber*>* _enabledStates;
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
    _enabledStateFileURL = [_storageDirectory
        URLByAppendingPathComponent:kEnabledUserscriptsFilename];
    _enabledStates = [NSMutableDictionary dictionary];
    _userscripts = @[];
    _registeredUserScripts = @[];
    NSError* error = nil;
    if (![self reloadUserscriptsWithError:&error]) {
      NSLog(@"Unable to load userscripts: %@", error);
    }
  }
  return self;
}

- (nullable CWVUserscript*)previewUserscriptAtURL:(NSURL*)fileURL
                                             error:(NSError* _Nullable*)error {
  if (!fileURL.isFileURL ||
      ![[fileURL.pathExtension lowercaseString] isEqualToString:@"js"] ||
      [fileURL.lastPathComponent hasPrefix:@"."]) {
    SetError(error, CWVUserscriptManagerErrorInvalidFile,
             @"Choose a visible local JavaScript (.js) userscript file.");
    return nil;
  }

  NSNumber* size = nil;
  if (![fileURL getResourceValue:&size forKey:NSURLFileSizeKey error:error]) {
    return nil;
  }
  if (size.unsignedIntegerValue > kMaximumUserscriptSizeBytes) {
    SetError(error, CWVUserscriptManagerErrorInvalidFile,
             @"Userscript files must not exceed 1 MiB.");
    return nil;
  }

  CWVUserscript* preview =
      [[CWVUserscript alloc] initWithFileURL:fileURL enabled:YES error:error];
  if (!preview) {
    return nil;
  }
  if (!preview.metadata.includePatterns.count) {
    SetError(error, CWVUserscriptManagerErrorInvalidMetadata,
             @"The userscript must declare at least one @match or @include rule.");
    return nil;
  }
  return preview;
}

- (BOOL)installUserscriptAtURL:(NSURL*)fileURL
                         error:(NSError* _Nullable*)error {
  CWVUserscript* preview = [self previewUserscriptAtURL:fileURL error:error];
  if (!preview) {
    return NO;
  }
  NSFileManager* fileManager = [NSFileManager defaultManager];
  if (![fileManager createDirectoryAtURL:_storageDirectory
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:error]) {
    return NO;
  }

  NSData* sourceData = [NSData dataWithContentsOfURL:fileURL options:0 error:error];
  if (!sourceData) {
    return NO;
  }
  NSURL* destinationURL = [_storageDirectory
      URLByAppendingPathComponent:fileURL.lastPathComponent];
  BOOL destinationExisted = [fileManager fileExistsAtPath:destinationURL.path];
  NSData* previousSource = destinationExisted
                             ? [NSData dataWithContentsOfURL:destinationURL]
                             : nil;
  if (![sourceData writeToURL:destinationURL
                      options:NSDataWritingAtomic
                        error:error]) {
    return NO;
  }

  NSMutableDictionary<NSString*, NSNumber*>* previousStates =
      [_enabledStates mutableCopy];
  _enabledStates[fileURL.lastPathComponent] = @YES;
  if (![self saveEnabledStatesWithError:error]) {
    _enabledStates = previousStates;
    if (destinationExisted && previousSource) {
      [previousSource writeToURL:destinationURL
                         options:NSDataWritingAtomic
                           error:nil];
    } else {
      [fileManager removeItemAtURL:destinationURL error:nil];
    }
    return NO;
  }
  return [self reloadUserscriptsWithError:error];
}

- (BOOL)setUserscriptEnabled:(BOOL)enabled
               forIdentifier:(NSString*)identifier
                       error:(NSError* _Nullable*)error {
  if (![self userscriptWithIdentifier:identifier]) {
    SetError(error, CWVUserscriptManagerErrorUnknownScript,
             @"The userscript is no longer installed.");
    return NO;
  }

  NSMutableDictionary<NSString*, NSNumber*>* previousStates =
      [_enabledStates mutableCopy];
  _enabledStates[identifier] = @(enabled);
  if (![self saveEnabledStatesWithError:error]) {
    _enabledStates = previousStates;
    return NO;
  }
  return [self reloadUserscriptsWithError:error];
}

- (BOOL)removeUserscriptWithIdentifier:(NSString*)identifier
                                  error:(NSError* _Nullable*)error {
  CWVUserscript* userscript = [self userscriptWithIdentifier:identifier];
  if (!userscript) {
    SetError(error, CWVUserscriptManagerErrorUnknownScript,
             @"The userscript is no longer installed.");
    return NO;
  }

  NSMutableDictionary<NSString*, NSNumber*>* previousStates =
      [_enabledStates mutableCopy];
  [_enabledStates removeObjectForKey:identifier];
  if (![self saveEnabledStatesWithError:error]) {
    _enabledStates = previousStates;
    return NO;
  }

  if (![[NSFileManager defaultManager] removeItemAtURL:userscript.fileURL
                                                  error:error]) {
    _enabledStates = previousStates;
    [self saveEnabledStatesWithError:nil];
    return NO;
  }
  return [self reloadUserscriptsWithError:error];
}

- (BOOL)reloadUserscriptsWithError:(NSError* _Nullable*)error {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  if (![fileManager createDirectoryAtURL:_storageDirectory
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:error]) {
    return NO;
  }
  if (![self loadEnabledStatesWithError:error]) {
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

    BOOL enabled = _enabledStates[fileURL.lastPathComponent]
                       ? _enabledStates[fileURL.lastPathComponent].boolValue
                       : YES;
    NSError* readError = nil;
    CWVUserscript* userscript = [[CWVUserscript alloc] initWithFileURL:fileURL
                                                                 enabled:enabled
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

    [loadedUserscripts addObject:userscript];
    if (!userscript.enabled) {
      continue;
    }
    CWVUserScript* injectedScript = [[CWVUserScript alloc]
        initWithSource:GuardedSource(userscript)
        forMainFrameOnly:userscript.metadata.isForMainFrameOnly
        injectionTime:InjectionTimeForMetadata(userscript.metadata)];
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

- (nullable CWVUserscript*)userscriptWithIdentifier:(NSString*)identifier {
  for (CWVUserscript* userscript in _userscripts) {
    if ([userscript.identifier isEqualToString:identifier]) {
      return userscript;
    }
  }
  return nil;
}

- (BOOL)loadEnabledStatesWithError:(NSError* _Nullable*)error {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  if (![fileManager fileExistsAtPath:_enabledStateFileURL.path]) {
    _enabledStates = [NSMutableDictionary dictionary];
    return YES;
  }

  NSDictionary<NSString*, NSNumber*>* states =
      [NSDictionary dictionaryWithContentsOfURL:_enabledStateFileURL];
  if (!states) {
    SetError(error, CWVUserscriptManagerErrorUnableToPersistState,
             @"The userscript enabled-state file could not be read.");
    return NO;
  }

  NSMutableDictionary<NSString*, NSNumber*>* validatedStates =
      [NSMutableDictionary dictionary];
  [states enumerateKeysAndObjectsUsingBlock:^(NSString* identifier,
                                               NSNumber* enabled,
                                               BOOL* stop) {
    if ([identifier isKindOfClass:[NSString class]] &&
        [enabled isKindOfClass:[NSNumber class]]) {
      validatedStates[identifier] = @([enabled boolValue]);
    }
  }];
  _enabledStates = validatedStates;
  return YES;
}

- (BOOL)saveEnabledStatesWithError:(NSError* _Nullable*)error {
  if ([_enabledStates writeToURL:_enabledStateFileURL atomically:YES]) {
    return YES;
  }
  SetError(error, CWVUserscriptManagerErrorUnableToPersistState,
           @"The userscript enabled state could not be saved.");
  return NO;
}

@end
