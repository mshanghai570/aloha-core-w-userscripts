// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_matcher.h"

#include "ios/web/public/js_messaging/java_script_feature.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"

namespace userscripts {
namespace {

TEST(UserScriptMatcherTest, MatchesExplicitHttpPattern) {
  UserScriptMetadata metadata;
  metadata.matches = {"https://example.com/docs/*"};

  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com/docs/a"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("http://example.com/docs/a"),
                                 /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://example.com/other"),
                                 /*is_main_frame=*/true));
}

TEST(UserScriptMatcherTest, WildcardSubdomainMatchesRootAndSubdomains) {
  UserScriptMetadata metadata;
  metadata.matches = {"*://*.example.com/*"};

  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                /*is_main_frame=*/true));
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("http://a.b.example.com/"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://notexample.com/"),
                                 /*is_main_frame=*/true));
}

TEST(UserScriptMatcherTest, SupportsExplicitPortAndDefaultAnyPort) {
  UserScriptMetadata metadata;
  metadata.matches = {"https://example.com:8443/*"};
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com:8443/a"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://example.com/a"),
                                 /*is_main_frame=*/true));

  metadata.matches = {"https://example.com/*"};
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com:8443/a"),
                                /*is_main_frame=*/true));
}

TEST(UserScriptMatcherTest, IncludesArePositivePatternsAndExclusionsWin) {
  UserScriptMetadata metadata;
  metadata.includes = {"https://*.example.com/*"};
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://www.example.com/a"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://elsewhere.test/a"),
                                 /*is_main_frame=*/true));

  metadata.matches = {"https://*.example.com/*"};
  metadata.excludes = {"https://private.example.com/*"};
  metadata.exclude_matches = {"https://*.example.com/admin/*"};
  EXPECT_FALSE(UserScriptMatches(metadata,
                                 GURL("https://private.example.com/page"),
                                 /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata,
                                 GURL("https://www.example.com/admin/page"),
                                 /*is_main_frame=*/true));
  EXPECT_TRUE(UserScriptMatches(metadata,
                                GURL("https://www.example.com/page"),
                                /*is_main_frame=*/true));
}

TEST(UserScriptMatcherTest, RequiresPositiveMatchAndBlocksNonWebSchemes) {
  UserScriptMetadata metadata;
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                 /*is_main_frame=*/true));
  metadata.matches = {"<all_urls>"};
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                /*is_main_frame=*/true));
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("http://example.com/"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("file:///tmp/page.html"),
                                 /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("chrome://settings/"),
                                 /*is_main_frame=*/true));
}

TEST(UserScriptMatcherTest, AppliesNoFrames) {
  UserScriptMetadata metadata;
  metadata.matches = {"https://example.com/*"};
  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                /*is_main_frame=*/false));
  metadata.noframes = true;

  EXPECT_TRUE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                /*is_main_frame=*/true));
  EXPECT_FALSE(UserScriptMatches(metadata, GURL("https://example.com/"),
                                 /*is_main_frame=*/false));
}

TEST(UserScriptMatcherTest, RejectsMalformedAndDisallowedPatterns) {
  UserScriptMetadata metadata;
  metadata.matches = {"https://*.bad.*.example.com/*"};
  auto invalid_match = ValidateUserScriptPatterns(metadata);
  ASSERT_FALSE(invalid_match.has_value());
  EXPECT_EQ(invalid_match.error(), UserScriptPatternError::kInvalidMatchPattern);

  metadata.matches = {"ftp://example.com/*"};
  invalid_match = ValidateUserScriptPatterns(metadata);
  ASSERT_FALSE(invalid_match.has_value());
  EXPECT_EQ(invalid_match.error(), UserScriptPatternError::kInvalidMatchPattern);

  metadata.matches.clear();
  metadata.exclude_matches = {"file:///*"};
  auto invalid_exclusion = ValidateUserScriptPatterns(metadata);
  ASSERT_FALSE(invalid_exclusion.has_value());
  EXPECT_EQ(invalid_exclusion.error(),
            UserScriptPatternError::kInvalidExcludeMatchPattern);
}

TEST(UserScriptMatcherTest, MapsRunAtToSupportedWebKitTimes) {
  using InjectionTime =
      web::JavaScriptFeature::FeatureScript::InjectionTime;
  EXPECT_EQ(InjectionTimeFor(UserScriptRunAt::kDocumentStart),
            InjectionTime::kDocumentStart);
  EXPECT_EQ(InjectionTimeFor(UserScriptRunAt::kDocumentEnd),
            InjectionTime::kDocumentEnd);
  // The runtime defers document-idle scripts after WebKit's document-end hook.
  EXPECT_EQ(InjectionTimeFor(UserScriptRunAt::kDocumentIdle),
            InjectionTime::kDocumentEnd);
}

}  // namespace
}  // namespace userscripts
