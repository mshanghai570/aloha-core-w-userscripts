// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_store.h"

#include <memory>
#include <string>
#include <string_view>

#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "components/prefs/testing_pref_service_simple.h"
#include "ios/chrome/browser/userscripts/model/userscripts_prefs.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"

namespace userscripts {
namespace {

std::string MakeScript(std::string_view version,
                       std::string_view body = "run();") {
  return "// ==UserScript==\n"
         "// @name Store test\n"
         "// @namespace store-test\n"
         "// @version " +
         std::string(version) +
         "\n// @match https://example.com/*\n"
         "// ==/UserScript==\n" +
         std::string(body) + "\n";
}

class UserScriptStoreTest : public testing::Test {
 protected:
  void SetUp() override {
    ASSERT_TRUE(temp_dir_.CreateUniqueTempDir());
    prefs_.registry()->RegisterListPref(prefs::kInstalledScripts);
    store_ = std::make_unique<UserScriptStore>(
        &prefs_, temp_dir_.GetPath().AppendASCII("Userscripts"));
  }

  base::ScopedTempDir temp_dir_;
  TestingPrefServiceSimple prefs_;
  std::unique_ptr<UserScriptStore> store_;
};

TEST_F(UserScriptStoreTest, InstallAndReopenProfileStore) {
  const std::string source = MakeScript("1.0");
  auto id = store_->InstallScript(source, GURL());
  ASSERT_TRUE(id.has_value());

  store_.reset();
  store_ = std::make_unique<UserScriptStore>(
      &prefs_, temp_dir_.GetPath().AppendASCII("Userscripts"));
  auto scripts = store_->GetScripts();

  ASSERT_TRUE(scripts.has_value());
  ASSERT_EQ(scripts->size(), 1u);
  EXPECT_EQ(scripts->front().id, id.value());
  EXPECT_EQ(scripts->front().parsed.source, source);
  EXPECT_TRUE(scripts->front().enabled);
}

TEST_F(UserScriptStoreTest,
       ReplacementPreservesEnabledStateAndDefersSourceCleanupUntilReopen) {
  auto id = store_->InstallScript(MakeScript("1.0"), GURL());
  ASSERT_TRUE(id.has_value());
  auto original_scripts = store_->GetScripts();
  ASSERT_TRUE(original_scripts.has_value());
  ASSERT_EQ(original_scripts->size(), 1u);
  const std::string old_source_file = original_scripts->front().source_file;
  ASSERT_TRUE(store_->SetEnabled(id.value(), false).has_value());

  auto replacement = store_->InstallScript(MakeScript("2.0"), GURL());
  ASSERT_TRUE(replacement.has_value());
  EXPECT_EQ(replacement.value(), id.value());

  auto scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  ASSERT_EQ(scripts->size(), 1u);
  EXPECT_FALSE(scripts->front().enabled);
  EXPECT_EQ(scripts->front().parsed.metadata.version, "2.0");
  const std::string new_source_file = scripts->front().source_file;
  const base::FilePath source_directory =
      temp_dir_.GetPath().AppendASCII("Userscripts");
  EXPECT_TRUE(base::PathExists(source_directory.AppendASCII(old_source_file)));

  EXPECT_TRUE(store_->RemoveScript(id.value()).has_value());
  auto empty = store_->GetScripts();
  ASSERT_TRUE(empty.has_value());
  EXPECT_TRUE(empty->empty());
  EXPECT_TRUE(base::PathExists(source_directory.AppendASCII(old_source_file)));
  EXPECT_TRUE(base::PathExists(source_directory.AppendASCII(new_source_file)));

  store_.reset();
  store_ = std::make_unique<UserScriptStore>(&prefs_, source_directory);
  auto reopened_empty = store_->GetScripts();
  ASSERT_TRUE(reopened_empty.has_value());
  EXPECT_TRUE(reopened_empty->empty());
  EXPECT_FALSE(base::PathExists(source_directory.AppendASCII(old_source_file)));
  EXPECT_FALSE(base::PathExists(source_directory.AppendASCII(new_source_file)));
}

TEST_F(UserScriptStoreTest, FailedReplacementPreservesInstalledVersion) {
  const std::string original = MakeScript("1.0");
  auto original_id = store_->InstallScript(original, GURL());
  ASSERT_TRUE(original_id.has_value());

  const base::FilePath blocker = temp_dir_.GetPath().AppendASCII("blocker");
  ASSERT_EQ(base::WriteFile(blocker, "not a directory"), 15);
  UserScriptStore blocked_store(
      &prefs_, blocker.AppendASCII("Userscripts"));

  auto replacement = blocked_store.InstallScript(MakeScript("2.0"), GURL());

  ASSERT_FALSE(replacement.has_value());
  EXPECT_EQ(replacement.error(), UserScriptError::kWriteFailed);
  auto scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  ASSERT_EQ(scripts->size(), 1u);
  EXPECT_EQ(scripts->front().id, original_id.value());
  EXPECT_EQ(scripts->front().parsed.source, original);
}

TEST_F(UserScriptStoreTest, OversizedReplacementKeepsPreviousVersion) {
  const std::string original = MakeScript("1.0");
  auto id = store_->InstallScript(original, GURL());
  ASSERT_TRUE(id.has_value());

  std::string oversized = MakeScript("2.0");
  oversized.append(2 * 1024 * 1024, 'x');
  auto replacement = store_->InstallScript(oversized, GURL());

  ASSERT_FALSE(replacement.has_value());
  EXPECT_EQ(replacement.error(), UserScriptError::kSourceTooLarge);
  auto scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  ASSERT_EQ(scripts->size(), 1u);
  EXPECT_EQ(scripts->front().parsed.source, original);
}

TEST_F(UserScriptStoreTest, SeparatePrefStoresDoNotShareScripts) {
  auto installed = store_->InstallScript(MakeScript("1.0"), GURL());
  ASSERT_TRUE(installed.has_value());

  TestingPrefServiceSimple other_prefs;
  other_prefs.registry()->RegisterListPref(prefs::kInstalledScripts);
  UserScriptStore other_store(
      &other_prefs, temp_dir_.GetPath().AppendASCII("OtherProfile"));
  auto other_scripts = other_store.GetScripts();

  ASSERT_TRUE(other_scripts.has_value());
  EXPECT_TRUE(other_scripts->empty());
}

TEST_F(UserScriptStoreTest, RejectsInvalidUtf8WithoutChangingIndex) {
  std::string invalid_source = MakeScript("1.0");
  invalid_source.push_back(static_cast<char>(0xFF));

  auto installed = store_->InstallScript(invalid_source, GURL());

  ASSERT_FALSE(installed.has_value());
  EXPECT_EQ(installed.error(), UserScriptError::kInvalidScript);
  EXPECT_TRUE(prefs_.GetList(prefs::kInstalledScripts).empty());
}

TEST_F(UserScriptStoreTest, GMValuesPersistAcrossReplacementAndCanBeDeleted) {
  auto id = store_->InstallScript(MakeScript("1.0"), GURL());
  ASSERT_TRUE(id.has_value());
  ASSERT_TRUE(store_->SetValue(id.value(), "theme", base::Value("dark"))
                  .has_value());

  auto replacement = store_->InstallScript(MakeScript("2.0"), GURL());
  ASSERT_TRUE(replacement.has_value());
  auto scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  ASSERT_EQ(scripts->size(), 1u);
  const std::string* theme = scripts->front().values.FindString("theme");
  ASSERT_NE(theme, nullptr);
  EXPECT_EQ(*theme, "dark");

  store_.reset();
  store_ = std::make_unique<UserScriptStore>(
      &prefs_, temp_dir_.GetPath().AppendASCII("Userscripts"));
  ASSERT_TRUE(store_->DeleteValue(id.value(), "theme").has_value());
  scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  EXPECT_TRUE(scripts->front().values.empty());
}

TEST_F(UserScriptStoreTest, RejectsOversizedGMValue) {
  auto id = store_->InstallScript(MakeScript("1.0"), GURL());
  ASSERT_TRUE(id.has_value());
  const std::string oversized(64 * 1024 + 1, 'x');

  auto result = store_->SetValue(id.value(), "large", base::Value(oversized));

  ASSERT_FALSE(result.has_value());
  EXPECT_EQ(result.error(), UserScriptError::kValueQuotaExceeded);
  auto scripts = store_->GetScripts();
  ASSERT_TRUE(scripts.has_value());
  EXPECT_TRUE(scripts->front().values.empty());
}

}  // namespace
}  // namespace userscripts
