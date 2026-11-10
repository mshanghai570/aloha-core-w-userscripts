// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_parser.h"

#include <algorithm>
#include <array>
#include <string>
#include <string_view>

#include "extensions/common/url_pattern.h"

namespace userscripts {
namespace {

constexpr size_t kMaxSourceSize = 2 * 1024 * 1024;
constexpr size_t kMaxHeaderSize = 64 * 1024;
constexpr std::string_view kHeaderStart = "// ==UserScript==";
constexpr std::string_view kHeaderEnd = "// ==/UserScript==";
constexpr int kUserScriptSchemes =
    URLPattern::SCHEME_HTTP | URLPattern::SCHEME_HTTPS;

bool IsValidUserScriptURLPattern(std::string_view pattern_string) {
  URLPattern pattern(kUserScriptSchemes);
  return pattern.Parse(pattern_string) == URLPattern::ParseResult::kSuccess;
}

bool IsWhitespace(char c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' ||
         c == '\v';
}

std::string_view Trim(std::string_view value) {
  while (!value.empty() && IsWhitespace(value.front()))
    value.remove_prefix(1);
  while (!value.empty() && IsWhitespace(value.back()))
    value.remove_suffix(1);
  return value;
}

void AppendUnique(std::vector<std::string>& values, std::string_view value) {
  if (std::find(values.begin(), values.end(), value) == values.end())
    values.emplace_back(value);
}

bool IsKnownDirective(std::string_view directive) {
  constexpr std::array<std::string_view, 17> kKnownDirectives = {
      "name",        "namespace", "version",    "description",
      "author",      "match",     "include",    "exclude",
      "exclude-match", "run-at",  "noframes",   "grant",
      "connect",     "require",   "resource",   "updateURL",
      "downloadURL",
  };
  return std::find(kKnownDirectives.begin(), kKnownDirectives.end(),
                   directive) != kKnownDirectives.end();
}

bool RequiresValue(std::string_view directive) {
  return directive == "match" || directive == "include" ||
         directive == "exclude" || directive == "exclude-match" ||
         directive == "run-at" || directive == "grant" ||
         directive == "connect" || directive == "require" ||
         directive == "resource";
}

bool IsSupportedGrant(std::string_view grant) {
  constexpr std::array<std::string_view, 12> kSupportedGrants = {
      "none",
      "GM_info",
      "unsafeWindow",
      "GM_addStyle",
      "GM_log",
      "GM.getValue",
      "GM.setValue",
      "GM.deleteValue",
      "GM.listValues",
      "GM_getValue",
      "GM_setValue",
      "GM_deleteValue",
      "GM_listValues",
  };
  return std::find(kSupportedGrants.begin(), kSupportedGrants.end(), grant) !=
         kSupportedGrants.end();
}

void SetScalar(std::string_view value,
               std::string& destination,
               std::vector<std::string>& warnings,
               std::string_view directive) {
  if (value.empty())
    return;
  if (destination.empty()) {
    destination = value;
    return;
  }
  warnings.emplace_back(std::string("Duplicate @") + std::string(directive) +
                        "; first value retained.");
}

base::expected<void, UserScriptParseError> ParseDirective(
    std::string_view directive,
    std::string_view value,
    ParsedUserScript& parsed,
    bool& run_at_seen) {
  if (!IsKnownDirective(directive)) {
    AppendUnique(parsed.unsupported_directives, directive);
    return {};
  }
  if (RequiresValue(directive) && value.empty())
    return base::unexpected(UserScriptParseError::kMissingDirectiveValue);

  UserScriptMetadata& metadata = parsed.metadata;
  if (directive == "name") {
    SetScalar(value, metadata.name, parsed.warnings, directive);
  } else if (directive == "namespace") {
    SetScalar(value, metadata.name_space, parsed.warnings, directive);
  } else if (directive == "version") {
    SetScalar(value, metadata.version, parsed.warnings, directive);
  } else if (directive == "description") {
    SetScalar(value, metadata.description, parsed.warnings, directive);
  } else if (directive == "author") {
    SetScalar(value, metadata.author, parsed.warnings, directive);
  } else if (directive == "match") {
    if (!IsValidUserScriptURLPattern(value))
      return base::unexpected(UserScriptParseError::kInvalidMatchPattern);
    metadata.matches.emplace_back(value);
  } else if (directive == "include") {
    metadata.includes.emplace_back(value);
  } else if (directive == "exclude") {
    metadata.excludes.emplace_back(value);
  } else if (directive == "exclude-match") {
    if (!IsValidUserScriptURLPattern(value)) {
      return base::unexpected(
          UserScriptParseError::kInvalidExcludeMatchPattern);
    }
    metadata.exclude_matches.emplace_back(value);
  } else if (directive == "grant") {
    metadata.grants.emplace_back(value);
    if (!IsSupportedGrant(value))
      AppendUnique(parsed.unsupported_grants, value);
  } else if (directive == "connect") {
    metadata.connect.emplace_back(value);
  } else if (directive == "require") {
    metadata.require_urls.emplace_back(value);
  } else if (directive == "resource") {
    const size_t separator = value.find_first_of(" \t");
    if (separator == std::string_view::npos)
      return base::unexpected(UserScriptParseError::kMissingDirectiveValue);
    const std::string_view name = Trim(value.substr(0, separator));
    const std::string_view url = Trim(value.substr(separator));
    if (name.empty() || url.empty())
      return base::unexpected(UserScriptParseError::kMissingDirectiveValue);
    metadata.resources.push_back(
        {.name = std::string(name), .url = std::string(url)});
  } else if (directive == "updateURL") {
    SetScalar(value, metadata.update_url, parsed.warnings, directive);
  } else if (directive == "downloadURL") {
    SetScalar(value, metadata.download_url, parsed.warnings, directive);
  } else if (directive == "run-at") {
    if (run_at_seen) {
      parsed.warnings.emplace_back("Duplicate @run-at; first value retained.");
    } else if (value == "document-start") {
      metadata.run_at = UserScriptRunAt::kDocumentStart;
      run_at_seen = true;
    } else if (value == "document-end") {
      metadata.run_at = UserScriptRunAt::kDocumentEnd;
      run_at_seen = true;
    } else if (value == "document-idle") {
      metadata.run_at = UserScriptRunAt::kDocumentIdle;
      run_at_seen = true;
    } else {
      return base::unexpected(UserScriptParseError::kInvalidRunAt);
    }
  } else if (directive == "noframes") {
    if (!value.empty())
      return base::unexpected(UserScriptParseError::kMalformedHeaderLine);
    metadata.noframes = true;
  }
  return {};
}

}  // namespace

base::expected<ParsedUserScript, UserScriptParseError> ParseUserScript(
    std::string_view source) {
  if (source.size() > kMaxSourceSize)
    return base::unexpected(UserScriptParseError::kSourceTooLarge);

  ParsedUserScript parsed;
  parsed.source.assign(source);
  size_t line_start = source.starts_with("\xEF\xBB\xBF") ? 3 : 0;

  bool found_start = false;
  while (line_start < source.size()) {
    const size_t newline = source.find('\n', line_start);
    const size_t line_end = newline == std::string_view::npos ? source.size()
                                                              : newline;
    const size_t next_line = newline == std::string_view::npos ? source.size()
                                                               : newline + 1;
    if (line_end > kMaxHeaderSize || next_line > kMaxHeaderSize)
      return base::unexpected(UserScriptParseError::kHeaderTooLarge);

    const std::string_view line =
        Trim(source.substr(line_start, line_end - line_start));
    if (line.empty()) {
      line_start = next_line;
      continue;
    }
    if (line != kHeaderStart)
      return base::unexpected(UserScriptParseError::kHeaderMissing);

    found_start = true;
    line_start = next_line;
    break;
  }

  if (!found_start)
    return base::unexpected(UserScriptParseError::kHeaderMissing);

  bool run_at_seen = false;
  while (line_start < source.size()) {
    const size_t newline = source.find('\n', line_start);
    const size_t line_end = newline == std::string_view::npos ? source.size()
                                                              : newline;
    const size_t next_line = newline == std::string_view::npos ? source.size()
                                                               : newline + 1;
    if (line_end > kMaxHeaderSize || next_line > kMaxHeaderSize)
      return base::unexpected(UserScriptParseError::kHeaderTooLarge);

    const std::string_view line =
        Trim(source.substr(line_start, line_end - line_start));
    if (line == kHeaderEnd) {
      parsed.body_offset = next_line;
      if (parsed.metadata.name.empty())
        return base::unexpected(UserScriptParseError::kNameMissing);
      return parsed;
    }

    if (!line.empty()) {
      if (!line.starts_with("//"))
        return base::unexpected(UserScriptParseError::kMalformedHeaderLine);

      std::string_view comment = Trim(line.substr(2));
      if (comment.starts_with('@')) {
        comment.remove_prefix(1);
        const size_t separator = comment.find_first_of(" \t");
        const std::string_view directive =
            separator == std::string_view::npos ? comment
                                                : comment.substr(0, separator);
        const std::string_view value =
            separator == std::string_view::npos
                ? std::string_view()
                : Trim(comment.substr(separator));
        if (directive.empty())
          return base::unexpected(UserScriptParseError::kMalformedHeaderLine);

        auto result = ParseDirective(directive, value, parsed, run_at_seen);
        if (!result.has_value())
          return base::unexpected(result.error());
      }
    }
    line_start = next_line;
  }

  if (source.size() > kMaxHeaderSize)
    return base::unexpected(UserScriptParseError::kHeaderTooLarge);
  return base::unexpected(UserScriptParseError::kHeaderUnterminated);
}

}  // namespace userscripts
