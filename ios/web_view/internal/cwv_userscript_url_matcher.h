// Copyright 2026 The Aloha Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_WEB_VIEW_INTERNAL_CWV_USERSCRIPT_URL_MATCHER_H_
#define IOS_WEB_VIEW_INTERNAL_CWV_USERSCRIPT_URL_MATCHER_H_

#include <string>

namespace url {
class GURL;
}

namespace ios_web_view {

// Matches the MVP userscript pattern syntax used by @match, @include, and
// @exclude. '*' matches any number of characters and '<all_urls>' accepts
// HTTP(S), file, and FTP URLs.
class CWVUserscriptURLMatcher {
 public:
  explicit CWVUserscriptURLMatcher(std::string pattern);
  CWVUserscriptURLMatcher(const CWVUserscriptURLMatcher&) = delete;
  CWVUserscriptURLMatcher& operator=(const CWVUserscriptURLMatcher&) = delete;
  ~CWVUserscriptURLMatcher();

  bool Matches(const url::GURL& url) const;

 private:
  std::string pattern_;
};

}  // namespace ios_web_view

#endif  // IOS_WEB_VIEW_INTERNAL_CWV_USERSCRIPT_URL_MATCHER_H_
