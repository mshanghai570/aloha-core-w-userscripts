// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_STORE_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_STORE_H_

#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/types/expected.h"
#include "base/values.h"
#include "ios/chrome/browser/userscripts/model/userscript.h"

class GURL;
class PrefService;

namespace userscripts {

enum class UserScriptError {
  kInvalidSourceURL,
  kSourceTooLarge,
  kInvalidScript,
  kInvalidPattern,
  kProfileQuotaExceeded,
  kWriteFailed,
  kInvalidStoredMetadata,
  kReadFailed,
  kNotFound,
  kValueQuotaExceeded,
};

struct StoredUserScript {
  std::string id;
  bool enabled = true;
  std::string source_url;
  std::string source_file;
  ParsedUserScript parsed;
  base::Value::Dict values;
};

// Stores profile metadata in PrefService and source files in an app-owned
// Userscripts directory. The store must be used on the profile's owning
// sequence.
class UserScriptStore {
 public:
  UserScriptStore(PrefService* prefs, base::FilePath source_directory);
  ~UserScriptStore();

  UserScriptStore(const UserScriptStore&) = delete;
  UserScriptStore& operator=(const UserScriptStore&) = delete;

  base::expected<std::vector<StoredUserScript>, UserScriptError> GetScripts()
      const;
  base::expected<std::string, UserScriptError> InstallScript(
      std::string_view source,
      const GURL& source_url);
  base::expected<void, UserScriptError> SetEnabled(std::string_view id,
                                                   bool enabled);
  base::expected<void, UserScriptError> RemoveScript(std::string_view id);
  base::expected<void, UserScriptError> SetValue(std::string_view id,
                                                std::string_view key,
                                                base::Value value);
  base::expected<void, UserScriptError> DeleteValue(std::string_view id,
                                                   std::string_view key);

 private:
  void CleanupOrphanedFiles() const;
  base::FilePath ScriptPath(std::string_view source_file) const;

  raw_ptr<PrefService> prefs_;
  const base::FilePath source_directory_;
  mutable bool needs_orphan_cleanup_ = true;
};

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_STORE_H_
