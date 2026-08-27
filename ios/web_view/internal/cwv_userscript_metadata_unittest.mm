// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/public/cwv_userscript_metadata.h"

#import "testing/gtest/include/gtest/gtest.h"
#import "testing/gtest_mac.h"

namespace ios_web_view {
namespace {

TEST(CWVUserscriptMetadataTest, ParsesSupportedMetadata) {
  NSString* source =
      @"// ==UserScript==\n"
       "// @name Example enhancer\n"
       "// @match https://example.com/*\n"
       "// @include https://*.example.org/*\n"
       "// @exclude https://example.com/private/*\n"
       "// @run-at document-start\n"
       "// @noframes\n"
       "// ==/UserScript==\n"
       "document.body.dataset.enhanced = 'true';";

  CWVUserscriptMetadata* metadata =
      [[CWVUserscriptMetadata alloc] initWithUserscriptSource:source
                                                  fallbackName:@"fallback.js"];

  EXPECT_NSEQ(@"Example enhancer", metadata.name);
  ASSERT_EQ(2u, metadata.includePatterns.count);
  EXPECT_NSEQ(@"https://example.com/*", metadata.includePatterns[0]);
  EXPECT_NSEQ(@"https://*.example.org/*", metadata.includePatterns[1]);
  ASSERT_EQ(1u, metadata.excludePatterns.count);
  EXPECT_NSEQ(@"https://example.com/private/*", metadata.excludePatterns[0]);
  EXPECT_NSEQ(@"document-start", metadata.runAt);
  EXPECT_TRUE(metadata.isForMainFrameOnly);
}

TEST(CWVUserscriptMetadataTest, UsesSafeDefaultsForMissingOrInvalidMetadata) {
  NSString* source =
      @"// ==UserScript==\n"
       "// @run-at unsupported-value\n"
       "// ==/UserScript==\n"
       "console.log('hello');";

  CWVUserscriptMetadata* metadata =
      [[CWVUserscriptMetadata alloc] initWithUserscriptSource:source
                                                  fallbackName:@"fallback.js"];

  EXPECT_NSEQ(@"fallback.js", metadata.name);
  EXPECT_EQ(0u, metadata.includePatterns.count);
  EXPECT_EQ(0u, metadata.excludePatterns.count);
  EXPECT_NSEQ(@"document-end", metadata.runAt);
  EXPECT_FALSE(metadata.isForMainFrameOnly);
}

TEST(CWVUserscriptMetadataTest, SupportsDocumentIdle) {
  NSString* source =
      @"// ==UserScript==\n"
       "// @match <all_urls>\n"
       "// @run-at document-idle\n"
       "// ==/UserScript==";

  CWVUserscriptMetadata* metadata =
      [[CWVUserscriptMetadata alloc] initWithUserscriptSource:source
                                                  fallbackName:@"fallback.js"];

  EXPECT_NSEQ(@"document-idle", metadata.runAt);
  ASSERT_EQ(1u, metadata.includePatterns.count);
  EXPECT_NSEQ(@"<all_urls>", metadata.includePatterns[0]);
}

}  // namespace
}  // namespace ios_web_view
