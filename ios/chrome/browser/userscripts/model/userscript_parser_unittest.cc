// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_parser.h"

#include "testing/gtest/include/gtest/gtest.h"

namespace userscripts {
namespace {

TEST(UserScriptParserTest, ParsesMetadataAndPreservesSource) {
  const std::string source =
      "// ==UserScript==\n"
      "// @name Example\n"
      "// @namespace example.test\n"
      "// @version 1.2.3\n"
      "// @description Example script\n"
      "// @author Aloha\n"
      "// @match https://example.com/*\n"
      "// @grant GM_log\n"
      "// @run-at document-start\n"
      "// ==/UserScript==\n"
      "console.log('body');\n";

  auto parsed = ParseUserScript(source);

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->source, source);
  EXPECT_EQ(parsed->metadata.name, "Example");
  EXPECT_EQ(parsed->metadata.name_space, "example.test");
  EXPECT_EQ(parsed->metadata.version, "1.2.3");
  EXPECT_EQ(parsed->metadata.description, "Example script");
  EXPECT_EQ(parsed->metadata.author, "Aloha");
  ASSERT_EQ(parsed->metadata.matches.size(), 1u);
  EXPECT_EQ(parsed->metadata.matches[0], "https://example.com/*");
  ASSERT_EQ(parsed->metadata.grants.size(), 1u);
  EXPECT_EQ(parsed->metadata.grants[0], "GM_log");
  EXPECT_EQ(parsed->metadata.run_at, UserScriptRunAt::kDocumentStart);
  EXPECT_EQ(parsed->source.substr(parsed->body_offset), "console.log('body');\n");
}

TEST(UserScriptParserTest, AcceptsBomAndCrLfWithoutChangingRawSource) {
  const std::string source =
      "\xEF\xBB\xBF// ==UserScript==\r\n"
      "// @name BOM script\r\n"
      "// @match https://example.com/*\r\n"
      "// ==/UserScript==\r\n"
      "run();\r\n";

  auto parsed = ParseUserScript(source);

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->source, source);
  EXPECT_EQ(parsed->metadata.name, "BOM script");
  EXPECT_EQ(parsed->source.substr(parsed->body_offset), "run();\r\n");
}

TEST(UserScriptParserTest, RejectsMissingHeader) {
  auto parsed = ParseUserScript("console.log('no header');\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(), UserScriptParseError::kHeaderMissing);
}

TEST(UserScriptParserTest, RejectsMissingTerminator) {
  auto parsed = ParseUserScript("// ==UserScript==\n// @name Missing end\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(), UserScriptParseError::kHeaderUnterminated);
}

TEST(UserScriptParserTest, RejectsMissingName) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @match https://example.com/*\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(), UserScriptParseError::kNameMissing);
}

TEST(UserScriptParserTest, FirstNonEmptyScalarWinsAndDuplicateIsReported) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name First\n// @name Second\n"
      "// @namespace \n// @namespace example.test\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->metadata.name, "First");
  EXPECT_EQ(parsed->metadata.name_space, "example.test");
  EXPECT_EQ(parsed->warnings.size(), 1u);
}

TEST(UserScriptParserTest, RepeatedListDirectivesAccumulate) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Lists\n"
      "// @match https://one.example/*\n"
      "// @match https://two.example/*\n"
      "// @grant GM_log\n// @grant GM_addStyle\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->metadata.matches,
            (std::vector<std::string>{"https://one.example/*",
                                      "https://two.example/*"}));
  EXPECT_EQ(parsed->metadata.grants,
            (std::vector<std::string>{"GM_log", "GM_addStyle"}));
}

TEST(UserScriptParserTest, ReportsUnknownDirectiveAndGrant) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Future\n"
      "// @future-directive value\n// @grant GM_future\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->unsupported_directives,
            (std::vector<std::string>{"future-directive"}));
  EXPECT_EQ(parsed->unsupported_grants,
            (std::vector<std::string>{"GM_future"}));
}

TEST(UserScriptParserTest, ReportsGrantsWithoutNativeBridgesAsUnsupported) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Partial grants\n"
      "// @grant GM_setValue\n// @grant GM_registerMenuCommand\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(parsed->metadata.grants,
            (std::vector<std::string>{"GM_setValue",
                                      "GM_registerMenuCommand"}));
  EXPECT_EQ(parsed->unsupported_grants,
            (std::vector<std::string>{"GM_registerMenuCommand"}));
}

TEST(UserScriptParserTest, RejectsUnknownRunAtValue) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Invalid timing\n"
      "// @run-at on-demand\n// ==/UserScript==\nrun();\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(), UserScriptParseError::kInvalidRunAt);
}

TEST(UserScriptParserTest, RejectsMalformedMatchPattern) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Invalid match\n"
      "// @match https://foo.*.example.com/*\n"
      "// ==/UserScript==\nrun();\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(), UserScriptParseError::kInvalidMatchPattern);
}

TEST(UserScriptParserTest, RejectsNonWebExcludeMatchPattern) {
  auto parsed = ParseUserScript(
      "// ==UserScript==\n// @name Invalid exclusion\n"
      "// @exclude-match file:///*\n// ==/UserScript==\nrun();\n");

  ASSERT_FALSE(parsed.has_value());
  EXPECT_EQ(parsed.error(),
            UserScriptParseError::kInvalidExcludeMatchPattern);
}

TEST(UserScriptParserTest, EnforcesSourceAndHeaderLimits) {
  std::string oversized_source(2 * 1024 * 1024 + 1, 'x');
  auto source_result = ParseUserScript(oversized_source);
  ASSERT_FALSE(source_result.has_value());
  EXPECT_EQ(source_result.error(), UserScriptParseError::kSourceTooLarge);

  std::string oversized_header = "// ==UserScript==\n// @name Huge\n// ";
  oversized_header.append(64 * 1024, 'x');
  auto header_result = ParseUserScript(oversized_header);
  ASSERT_FALSE(header_result.has_value());
  EXPECT_EQ(header_result.error(), UserScriptParseError::kHeaderTooLarge);
}

}  // namespace
}  // namespace userscripts
