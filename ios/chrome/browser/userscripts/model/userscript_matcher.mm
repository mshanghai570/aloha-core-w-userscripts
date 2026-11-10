// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_matcher.h"

#include <string>
#include <string_view>

#include "base/strings/pattern.h"
#include "extensions/common/url_pattern.h"
#include "url/gurl.h"

namespace userscripts {
namespace {

constexpr int kUserScriptSchemes =
    URLPattern::SCHEME_HTTP | URLPattern::SCHEME_HTTPS;

bool IsWebURL(const GURL& url) {
  return url.is_valid() && (url.SchemeIs("http") || url.SchemeIs("https"));
}

bool MatchesAnyURLPattern(const std::vector<std::string>& patterns,
                          const GURL& url) {
  for (const std::string& pattern_string : patterns) {
    URLPattern pattern(kUserScriptSchemes);
    if (pattern.Parse(pattern_string) == URLPattern::ParseResult::kSuccess &&
        pattern.MatchesURL(url)) {
      return true;
    }
  }
  return false;
}

bool MatchesAnyGlob(const std::vector<std::string>& patterns,
                    const GURL& url) {
  for (const std::string& pattern : patterns) {
    if (base::MatchPattern(url.spec(), pattern))
      return true;
  }
  return false;
}

}  // namespace

base::expected<void, UserScriptPatternError> ValidateUserScriptPatterns(
    const UserScriptMetadata& metadata) {
  for (const std::string& pattern_string : metadata.matches) {
    URLPattern pattern(kUserScriptSchemes);
    if (pattern.Parse(pattern_string) != URLPattern::ParseResult::kSuccess)
      return base::unexpected(UserScriptPatternError::kInvalidMatchPattern);
  }

  for (const std::string& pattern_string : metadata.exclude_matches) {
    URLPattern pattern(kUserScriptSchemes);
    if (pattern.Parse(pattern_string) != URLPattern::ParseResult::kSuccess) {
      return base::unexpected(
          UserScriptPatternError::kInvalidExcludeMatchPattern);
    }
  }
  return {};
}

bool UserScriptMatches(const UserScriptMetadata& metadata,
                       const GURL& url,
                       bool is_main_frame) {
  if (!IsWebURL(url) || (metadata.noframes && !is_main_frame))
    return false;

  const bool has_positive_pattern =
      !metadata.matches.empty() || !metadata.includes.empty();
  if (!has_positive_pattern ||
      !(MatchesAnyURLPattern(metadata.matches, url) ||
        MatchesAnyGlob(metadata.includes, url))) {
    return false;
  }

  return !MatchesAnyURLPattern(metadata.exclude_matches, url) &&
         !MatchesAnyGlob(metadata.excludes, url);
}

web::JavaScriptFeature::FeatureScript::InjectionTime InjectionTimeFor(
    UserScriptRunAt run_at) {
  using InjectionTime =
      web::JavaScriptFeature::FeatureScript::InjectionTime;
  switch (run_at) {
    case UserScriptRunAt::kDocumentStart:
      return InjectionTime::kDocumentStart;
    case UserScriptRunAt::kDocumentEnd:
    case UserScriptRunAt::kDocumentIdle:
      return InjectionTime::kDocumentEnd;
  }
  return InjectionTime::kDocumentEnd;
}

}  // namespace userscripts
