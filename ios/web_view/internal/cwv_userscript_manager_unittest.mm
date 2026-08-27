// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript_manager.h"

#import "ios/web_view/public/cwv_userscript.h"
#import "ios/web_view/public/cwv_userscript_metadata.h"

#import "testing/gtest/include/gtest/gtest.h"
#import "testing/gtest_mac.h"

namespace ios_web_view {
namespace {

NSURL* CreateTemporaryDirectory() {
  NSURL* directory = [NSURL
      fileURLWithPath:[NSTemporaryDirectory()
                          stringByAppendingPathComponent:
                              [NSUUID UUID].UUIDString]
           isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  return directory;
}

NSURL* WriteUserscript(NSURL* directory, NSString* name, NSString* source) {
  NSURL* fileURL = [directory URLByAppendingPathComponent:name];
  [source writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
  return fileURL;
}

NSString* ValidUserscriptSource(NSString* name) {
  return [NSString stringWithFormat:
      @"// ==UserScript==\n"
       "// @name %@\n"
       "// @match https://example.com/*\n"
       "// @run-at document-end\n"
       "// ==/UserScript==\n"
       "window.__alohaUserscriptTest = true;",
      name];
}

TEST(CWVUserscriptManagerTest, InstallsAndPersistsEnabledState) {
  NSURL* temporaryDirectory = CreateTemporaryDirectory();
  NSURL* storageDirectory =
      [temporaryDirectory URLByAppendingPathComponent:@"Userscripts" isDirectory:YES];
  NSURL* sourceURL = WriteUserscript(temporaryDirectory, @"example.js",
                                     ValidUserscriptSource(@"Example"));

  CWVUserscriptManager* manager = [[CWVUserscriptManager alloc]
      initWithStorageDirectory:storageDirectory
          userContentController:nil];
  NSError* error = nil;
  ASSERT_TRUE([manager installUserscriptAtURL:sourceURL error:&error]);
  ASSERT_EQ(1u, manager.userscripts.count);
  CWVUserscript* userscript = manager.userscripts.firstObject;
  EXPECT_NSEQ(@"example.js", userscript.identifier);
  EXPECT_NSEQ(@"Example", userscript.metadata.name);
  EXPECT_TRUE(userscript.enabled);

  ASSERT_TRUE([manager setUserscriptEnabled:NO
                              forIdentifier:userscript.identifier
                                      error:&error]);
  ASSERT_EQ(1u, manager.userscripts.count);
  EXPECT_FALSE(manager.userscripts.firstObject.enabled);

  CWVUserscriptManager* reloadedManager = [[CWVUserscriptManager alloc]
      initWithStorageDirectory:storageDirectory
          userContentController:nil];
  ASSERT_EQ(1u, reloadedManager.userscripts.count);
  EXPECT_FALSE(reloadedManager.userscripts.firstObject.enabled);

  [[NSFileManager defaultManager] removeItemAtURL:temporaryDirectory error:nil];
}

TEST(CWVUserscriptManagerTest, RejectsScriptsWithoutURLRules) {
  NSURL* temporaryDirectory = CreateTemporaryDirectory();
  NSURL* storageDirectory =
      [temporaryDirectory URLByAppendingPathComponent:@"Userscripts" isDirectory:YES];
  NSURL* sourceURL = WriteUserscript(temporaryDirectory, @"invalid.js",
                                     @"console.log('missing metadata');");

  CWVUserscriptManager* manager = [[CWVUserscriptManager alloc]
      initWithStorageDirectory:storageDirectory
          userContentController:nil];
  NSError* error = nil;
  EXPECT_FALSE([manager installUserscriptAtURL:sourceURL error:&error]);
  EXPECT_NE(nil, error);
  EXPECT_EQ(0u, manager.userscripts.count);

  [[NSFileManager defaultManager] removeItemAtURL:temporaryDirectory error:nil];
}

TEST(CWVUserscriptManagerTest, RemovesInstalledScript) {
  NSURL* temporaryDirectory = CreateTemporaryDirectory();
  NSURL* storageDirectory =
      [temporaryDirectory URLByAppendingPathComponent:@"Userscripts" isDirectory:YES];
  NSURL* sourceURL = WriteUserscript(temporaryDirectory, @"remove-me.js",
                                     ValidUserscriptSource(@"Remove me"));

  CWVUserscriptManager* manager = [[CWVUserscriptManager alloc]
      initWithStorageDirectory:storageDirectory
          userContentController:nil];
  NSError* error = nil;
  ASSERT_TRUE([manager installUserscriptAtURL:sourceURL error:&error]);
  NSString* identifier = manager.userscripts.firstObject.identifier;

  ASSERT_TRUE([manager removeUserscriptWithIdentifier:identifier error:&error]);
  EXPECT_EQ(0u, manager.userscripts.count);
  EXPECT_FALSE([[NSFileManager defaultManager]
      fileExistsAtPath:[storageDirectory URLByAppendingPathComponent:identifier].path]);

  [[NSFileManager defaultManager] removeItemAtURL:temporaryDirectory error:nil];
}

}  // namespace
}  // namespace ios_web_view
