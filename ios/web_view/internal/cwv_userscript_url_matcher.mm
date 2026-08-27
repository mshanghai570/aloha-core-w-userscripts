// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ios/web_view/internal/cwv_userscript_url_matcher.h"

#include <utility>

#include "base/strings/pattern.h"
#include "url/gurl.h"

namespace ios_web_view {

CWVUserscriptURLMatcher::CWVUserscriptURLMatcher(std::string pattern)
    : pattern_(std::move(pattern)) {}

CWVUserscriptURLMatcher::~CWVUserscriptURLMatcher() = default;

bool CWVUserscriptURLMatcher::Matches(const url::GURL& url) const {
  if (!url.is_valid()) {
    return false;
  }

  if (pattern_ == "<all_urls>") {
    return url.SchemeIsHTTPOrHTTPS() || url.SchemeIsFile() ||
           url.SchemeIs("ftp");
  }

  if (base::MatchPattern(url.spec(), pattern_)) {
    return true;
  }

  // Chrome-style wildcard hosts such as `*.example.com` also cover the base
  // host. `base::MatchPattern` alone treats the wildcard as one-or-more
  // characters, so check the equivalent base-host pattern explicitly.
  const size_t wildcardHost = pattern_.find("://*.");
  if (wildcardHost == std::string::npos) {
    return false;
  }
  const std::string baseHostPattern =
      pattern_.substr(0, wildcardHost + 3) + pattern_.substr(wildcardHost + 5);
  return base::MatchPattern(url.spec(), baseHostPattern);
}

}  // namespace ios_web_view
