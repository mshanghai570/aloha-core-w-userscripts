// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/internal/cwv_userscript_url_matcher.h"

#import "testing/gtest/include/gtest/gtest.h"
#import "url/gurl.h"

namespace ios_web_view {
namespace {

TEST(CWVUserscriptURLMatcherTest, MatchesWildcardURLPatterns) {
  CWVUserscriptURLMatcher matcher("https://*.example.com/*");

  EXPECT_TRUE(matcher.Matches(GURL("https://example.com/")));
  EXPECT_TRUE(matcher.Matches(GURL("https://docs.example.com/path?q=1")));
  EXPECT_FALSE(matcher.Matches(GURL("http://docs.example.com/path")));
  EXPECT_FALSE(matcher.Matches(GURL("https://example.org/path")));
}

TEST(CWVUserscriptURLMatcherTest, MatchesAllSupportedURLSchemes) {
  CWVUserscriptURLMatcher matcher("<all_urls>");

  EXPECT_TRUE(matcher.Matches(GURL("https://example.com/")));
  EXPECT_TRUE(matcher.Matches(GURL("http://example.com/")));
  EXPECT_TRUE(matcher.Matches(GURL("file:///tmp/example.html")));
  EXPECT_FALSE(matcher.Matches(GURL("data:text/plain,example")));
}

TEST(CWVUserscriptURLMatcherTest, RejectsInvalidURL) {
  CWVUserscriptURLMatcher matcher("https://example.com/*");

  EXPECT_FALSE(matcher.Matches(GURL("not a valid URL")));
}

}  // namespace
}  // namespace ios_web_view
