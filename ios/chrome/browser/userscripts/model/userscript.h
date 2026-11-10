// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_H_

#include <cstddef>
#include <string>
#include <vector>

namespace userscripts {

enum class UserScriptRunAt {
  kDocumentStart,
  kDocumentEnd,
  kDocumentIdle,
};

struct UserScriptResource {
  std::string name;
  std::string url;
};

struct UserScriptMetadata {
  std::string name;
  std::string name_space;
  std::string version;
  std::string description;
  std::string author;
  std::vector<std::string> matches;
  std::vector<std::string> includes;
  std::vector<std::string> excludes;
  std::vector<std::string> exclude_matches;
  std::vector<std::string> grants;
  std::vector<std::string> connect;
  std::vector<std::string> require_urls;
  std::vector<UserScriptResource> resources;
  std::string update_url;
  std::string download_url;
  UserScriptRunAt run_at = UserScriptRunAt::kDocumentEnd;
  bool noframes = false;
};

struct ParsedUserScript {
  // The exact imported source is retained; `body_offset` identifies the code
  // after the metadata block without normalizing the stored bytes.
  std::string source;
  UserScriptMetadata metadata;
  std::vector<std::string> unsupported_directives;
  std::vector<std::string> unsupported_grants;
  std::vector<std::string> warnings;
  size_t body_offset = 0;
};

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_H_
