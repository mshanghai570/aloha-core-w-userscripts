// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_PARSER_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_PARSER_H_

#include <string_view>

#include "base/types/expected.h"
#include "ios/chrome/browser/userscripts/model/userscript.h"

namespace userscripts {

enum class UserScriptParseError {
  kSourceTooLarge,
  kHeaderMissing,
  kHeaderTooLarge,
  kHeaderUnterminated,
  kNameMissing,
  kMissingDirectiveValue,
  kMalformedHeaderLine,
  kInvalidRunAt,
  kInvalidMatchPattern,
  kInvalidExcludeMatchPattern,
};

// Parses only the leading ==UserScript== block. Source and header sizes are
// bounded before copying or parsing untrusted input.
base::expected<ParsedUserScript, UserScriptParseError> ParseUserScript(
    std::string_view source);

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_PARSER_H_
