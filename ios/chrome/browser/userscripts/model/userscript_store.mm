// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscript_store.h"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/important_file_writer.h"
#include "base/json/json_writer.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/values.h"
#include "components/prefs/pref_service.h"
#include "crypto/sha2.h"
#include "ios/chrome/browser/userscripts/model/userscript_matcher.h"
#include "ios/chrome/browser/userscripts/model/userscript_parser.h"
#include "ios/chrome/browser/userscripts/model/userscripts_prefs.h"
#include "url/gurl.h"

namespace userscripts {
namespace {

constexpr size_t kMaxSourceSize = 2 * 1024 * 1024;
constexpr int64_t kMaxProfileSourceSize = 50LL * 1024 * 1024;
constexpr size_t kMaxUserValueSize = 64 * 1024;
constexpr size_t kMaxScriptValuesSize = 1024 * 1024;
constexpr size_t kMaxProfileValuesSize = 8 * 1024 * 1024;
constexpr size_t kMaxScriptValueCount = 512;
constexpr size_t kMaxUserValueKeySize = 256;
constexpr char kIdKey[] = "id";
constexpr char kNameKey[] = "name";
constexpr char kNamespaceKey[] = "namespace";
constexpr char kVersionKey[] = "version";
constexpr char kEnabledKey[] = "enabled";
constexpr char kSourceSizeKey[] = "source_size";
constexpr char kSourceURLKey[] = "source_url";
constexpr char kSourceFileKey[] = "source_file";
constexpr char kValuesKey[] = "values";

bool SerializeValues(const base::Value::Dict& values, std::string* json) {
  return base::JSONWriter::Write(base::Value(values.Clone()), json);
}

std::string MakeScriptId(const UserScriptMetadata& metadata) {
  const std::string identity = metadata.name_space + "\n" + metadata.name;
  return base::HexEncode(crypto::SHA256HashString(identity));
}

std::string MakeSourceFilename(std::string_view id, std::string_view source) {
  return std::string(id) + "-" +
         base::HexEncode(crypto::SHA256HashString(source)) + ".user.js";
}

bool IsValidScriptId(std::string_view id) {
  if (id.size() != 64)
    return false;
  for (char c : id) {
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') ||
          (c >= 'a' && c <= 'f'))) {
      return false;
    }
  }
  return true;
}

bool IsValidSourceFilename(std::string_view id, std::string_view filename) {
  constexpr size_t kHashLength = 64;
  constexpr std::string_view kSuffix = ".user.js";
  const size_t hash_offset = id.size() + 1;
  if (filename.size() != hash_offset + kHashLength + kSuffix.size() ||
      filename.substr(0, id.size()) != id || filename[id.size()] != '-' ||
      filename.substr(filename.size() - kSuffix.size()) != kSuffix) {
    return false;
  }
  return IsValidScriptId(filename.substr(hash_offset, kHashLength));
}

UserScriptError StoreErrorForParseError(UserScriptParseError error) {
  if (error == UserScriptParseError::kSourceTooLarge)
    return UserScriptError::kSourceTooLarge;
  if (error == UserScriptParseError::kInvalidMatchPattern ||
      error == UserScriptParseError::kInvalidExcludeMatchPattern) {
    return UserScriptError::kInvalidPattern;
  }
  return UserScriptError::kInvalidScript;
}

bool IsValidSourceURL(const GURL& url) {
  return url.is_empty() ||
         (url.is_valid() && (url.SchemeIs("http") || url.SchemeIs("https")));
}

base::Value::Dict MakeIndexRecord(const StoredUserScript& script,
                                  int source_size) {
  base::Value::Dict record;
  record.Set(kIdKey, script.id);
  record.Set(kNameKey, script.parsed.metadata.name);
  record.Set(kNamespaceKey, script.parsed.metadata.name_space);
  record.Set(kVersionKey, script.parsed.metadata.version);
  record.Set(kEnabledKey, script.enabled);
  record.Set(kSourceSizeKey, source_size);
  record.Set(kSourceURLKey, script.source_url);
  record.Set(kSourceFileKey, script.source_file);
  record.Set(kValuesKey, script.values.Clone());
  return record;
}

}  // namespace

UserScriptStore::UserScriptStore(PrefService* prefs,
                                 base::FilePath source_directory)
    : prefs_(prefs), source_directory_(std::move(source_directory)) {}

UserScriptStore::~UserScriptStore() = default;

void UserScriptStore::CleanupOrphanedFiles() const {
  if (!needs_orphan_cleanup_)
    return;

  std::vector<base::FilePath> active_files;
  for (const base::Value& value :
       prefs_->GetList(prefs::kInstalledScripts)) {
    const base::Value::Dict* record = value.GetIfDict();
    if (!record)
      return;
    const std::string* id = record->FindString(kIdKey);
    const std::string* source_file = record->FindString(kSourceFileKey);
    if (!id || !IsValidScriptId(*id) || !source_file ||
        !IsValidSourceFilename(*id, *source_file)) {
      return;
    }
    active_files.push_back(ScriptPath(*source_file));
  }

  if (base::DirectoryExists(source_directory_)) {
    base::FileEnumerator files(source_directory_, /*recursive=*/false,
                               base::FileEnumerator::FILES, "*.user.js");
    for (base::FilePath path = files.Next(); !path.empty();
         path = files.Next()) {
      if (std::find(active_files.begin(), active_files.end(), path) ==
          active_files.end()) {
        base::DeleteFile(path);
      }
    }
  }
  needs_orphan_cleanup_ = false;
}

base::expected<std::vector<StoredUserScript>, UserScriptError>
UserScriptStore::GetScripts() const {
  CleanupOrphanedFiles();
  std::vector<StoredUserScript> scripts;
  int64_t total_source_size = 0;
  size_t total_values_size = 0;
  for (const base::Value& value :
       prefs_->GetList(prefs::kInstalledScripts)) {
    const base::Value::Dict* record = value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);

    const std::string* id = record->FindString(kIdKey);
    const std::string* source_url = record->FindString(kSourceURLKey);
    const std::string* source_file = record->FindString(kSourceFileKey);
    const std::optional<bool> enabled = record->FindBool(kEnabledKey);
    const std::optional<int> recorded_size = record->FindInt(kSourceSizeKey);
    if (!id || !IsValidScriptId(*id) || !source_url || !enabled ||
        !source_file || !IsValidSourceFilename(*id, *source_file) ||
        !recorded_size || *recorded_size < 0 ||
        *recorded_size > static_cast<int>(kMaxSourceSize)) {
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    }
    if (!IsValidSourceURL(GURL(*source_url)))
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);

    base::Value::Dict script_values;
    if (const base::Value* value_data = record->Find(kValuesKey)) {
      const base::Value::Dict* stored_values = value_data->GetIfDict();
      std::string serialized_values;
      if (!stored_values || stored_values->size() > kMaxScriptValueCount ||
          !SerializeValues(*stored_values, &serialized_values) ||
          serialized_values.size() > kMaxScriptValuesSize) {
        return base::unexpected(UserScriptError::kInvalidStoredMetadata);
      }
      total_values_size += serialized_values.size();
      if (total_values_size > kMaxProfileValuesSize)
        return base::unexpected(UserScriptError::kInvalidStoredMetadata);
      script_values = stored_values->Clone();
    }

    const base::FilePath source_path = ScriptPath(*source_file);
    int64_t actual_size = 0;
    if (!base::GetFileSize(source_path, &actual_size) || actual_size < 0 ||
        actual_size > static_cast<int64_t>(kMaxSourceSize) ||
        actual_size != *recorded_size) {
      return base::unexpected(UserScriptError::kReadFailed);
    }

    std::string source;
    if (!base::ReadFileToString(source_path, &source) ||
        source.size() != static_cast<size_t>(actual_size)) {
      return base::unexpected(UserScriptError::kReadFailed);
    }
    if (!base::IsStringUTF8(source))
      return base::unexpected(UserScriptError::kInvalidScript);
    if (MakeSourceFilename(*id, source) != *source_file)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);

    auto parsed = ParseUserScript(source);
    if (!parsed)
      return base::unexpected(StoreErrorForParseError(parsed.error()));
    if (!ValidateUserScriptPatterns(parsed->metadata))
      return base::unexpected(UserScriptError::kInvalidPattern);
    if (MakeScriptId(parsed->metadata) != *id)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);

    total_source_size += actual_size;
    if (total_source_size > kMaxProfileSourceSize)
      return base::unexpected(UserScriptError::kProfileQuotaExceeded);

    scripts.push_back({.id = *id,
                       .enabled = *enabled,
                       .source_url = *source_url,
                       .source_file = *source_file,
                       .parsed = std::move(parsed.value()),
                       .values = std::move(script_values)});
  }
  return scripts;
}

base::expected<std::string, UserScriptError> UserScriptStore::InstallScript(
    std::string_view source,
    const GURL& source_url) {
  if (source.size() > kMaxSourceSize)
    return base::unexpected(UserScriptError::kSourceTooLarge);
  if (!base::IsStringUTF8(source))
    return base::unexpected(UserScriptError::kInvalidScript);
  if (!IsValidSourceURL(source_url))
    return base::unexpected(UserScriptError::kInvalidSourceURL);
  CleanupOrphanedFiles();

  auto parsed = ParseUserScript(source);
  if (!parsed)
    return base::unexpected(StoreErrorForParseError(parsed.error()));
  if (!ValidateUserScriptPatterns(parsed->metadata))
    return base::unexpected(UserScriptError::kInvalidPattern);

  const std::string id = MakeScriptId(parsed->metadata);
  base::Value::List records =
      prefs_->GetList(prefs::kInstalledScripts).Clone();
  std::optional<size_t> existing_index;
  int64_t total_source_size = 0;
  int previous_size = 0;
  bool was_enabled = true;

  for (size_t i = 0; i < records.size(); ++i) {
    const base::Value::Dict* record = records[i].GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const std::string* existing_id = record->FindString(kIdKey);
    const std::string* existing_source_file =
        record->FindString(kSourceFileKey);
    const std::optional<int> recorded_size = record->FindInt(kSourceSizeKey);
    const std::optional<bool> enabled = record->FindBool(kEnabledKey);
    if (!existing_id || !IsValidScriptId(*existing_id) || !recorded_size ||
        *recorded_size < 0 ||
        *recorded_size > static_cast<int>(kMaxSourceSize) || !enabled ||
        !existing_source_file ||
        !IsValidSourceFilename(*existing_id, *existing_source_file) ||
        (record->Find(kValuesKey) &&
         !record->Find(kValuesKey)->is_dict())) {
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    }
    total_source_size += *recorded_size;
    if (*existing_id == id) {
      if (existing_index)
        return base::unexpected(UserScriptError::kInvalidStoredMetadata);
      existing_index = i;
      previous_size = *recorded_size;
      was_enabled = *enabled;
    }
  }

  const int source_size = static_cast<int>(source.size());
  if (total_source_size - previous_size + source_size >
      kMaxProfileSourceSize) {
    return base::unexpected(UserScriptError::kProfileQuotaExceeded);
  }

  StoredUserScript stored{.id = id,
                          .enabled = was_enabled,
                          .source_url = source_url.spec(),
                          .source_file = MakeSourceFilename(id, source),
                          .parsed = std::move(parsed.value())};
  if (existing_index) {
    const base::Value::Dict* existing_record =
        records[*existing_index].GetIfDict();
    const base::Value::Dict* existing_values =
        existing_record->FindDict(kValuesKey);
    if (existing_values)
      stored.values = existing_values->Clone();
  }
  if (!base::CreateDirectory(source_directory_) ||
      !base::ImportantFileWriter::WriteFileAtomically(
          ScriptPath(stored.source_file), source)) {
    return base::unexpected(UserScriptError::kWriteFailed);
  }

  base::Value replacement(MakeIndexRecord(stored, source_size));
  if (existing_index) {
    records[*existing_index] = std::move(replacement);
  } else {
    records.Append(std::move(replacement));
  }
  prefs_->Set(prefs::kInstalledScripts, base::Value(std::move(records)));
  return id;
}

base::expected<void, UserScriptError> UserScriptStore::SetEnabled(
    std::string_view id,
    bool enabled) {
  if (!IsValidScriptId(id))
    return base::unexpected(UserScriptError::kNotFound);
  CleanupOrphanedFiles();
  base::Value::List records =
      prefs_->GetList(prefs::kInstalledScripts).Clone();
  for (base::Value& value : records) {
    base::Value::Dict* record = value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const std::string* existing_id = record->FindString(kIdKey);
    if (existing_id && *existing_id == id) {
      record->Set(kEnabledKey, enabled);
      prefs_->Set(prefs::kInstalledScripts, base::Value(std::move(records)));
      return {};
    }
  }
  return base::unexpected(UserScriptError::kNotFound);
}

base::expected<void, UserScriptError> UserScriptStore::RemoveScript(
    std::string_view id) {
  if (!IsValidScriptId(id))
    return base::unexpected(UserScriptError::kNotFound);
  CleanupOrphanedFiles();

  const base::Value::List& current =
      prefs_->GetList(prefs::kInstalledScripts);
  bool found = false;
  base::Value::List remaining;
  for (const base::Value& value : current) {
    const base::Value::Dict* record = value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const std::string* existing_id = record->FindString(kIdKey);
    const std::string* existing_source_file =
        record->FindString(kSourceFileKey);
    if (!existing_id || !IsValidScriptId(*existing_id) ||
        !existing_source_file ||
        !IsValidSourceFilename(*existing_id, *existing_source_file)) {
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    }
    if (*existing_id == id) {
      if (found)
        return base::unexpected(UserScriptError::kInvalidStoredMetadata);
      found = true;
      continue;
    }
    remaining.Append(value.Clone());
  }
  if (!found)
    return base::unexpected(UserScriptError::kNotFound);

  prefs_->Set(prefs::kInstalledScripts, base::Value(std::move(remaining)));
  return {};
}

base::expected<void, UserScriptError> UserScriptStore::SetValue(
    std::string_view id,
    std::string_view key,
    base::Value value) {
  if (!IsValidScriptId(id))
    return base::unexpected(UserScriptError::kNotFound);
  std::string serialized_value;
  if (key.size() > kMaxUserValueKeySize || !base::IsStringUTF8(key) ||
      !base::JSONWriter::Write(value, &serialized_value) ||
      serialized_value.size() > kMaxUserValueSize) {
    return base::unexpected(UserScriptError::kValueQuotaExceeded);
  }

  base::Value::List records =
      prefs_->GetList(prefs::kInstalledScripts).Clone();
  bool updated = false;
  for (base::Value& record_value : records) {
    base::Value::Dict* record = record_value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const std::string* record_id = record->FindString(kIdKey);
    if (!record_id || !IsValidScriptId(*record_id))
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    if (*record_id != id)
      continue;
    if (updated)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    base::Value::Dict* values = record->FindDict(kValuesKey);
    if (!values) {
      if (record->Find(kValuesKey))
        return base::unexpected(UserScriptError::kInvalidStoredMetadata);
      record->Set(kValuesKey, base::Value::Dict());
      values = record->FindDict(kValuesKey);
    }
    values->Set(key, std::move(value));
    std::string serialized_values;
    if (values->size() > kMaxScriptValueCount ||
        !SerializeValues(*values, &serialized_values) ||
        serialized_values.size() > kMaxScriptValuesSize) {
      return base::unexpected(UserScriptError::kValueQuotaExceeded);
    }
    updated = true;
  }
  if (!updated)
    return base::unexpected(UserScriptError::kNotFound);

  size_t total_values_size = 0;
  for (const base::Value& record_value : records) {
    const base::Value::Dict* record = record_value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const base::Value* values_value = record->Find(kValuesKey);
    if (!values_value)
      continue;
    const base::Value::Dict* values = values_value->GetIfDict();
    std::string serialized_values;
    if (!values || !SerializeValues(*values, &serialized_values))
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    total_values_size += serialized_values.size();
    if (total_values_size > kMaxProfileValuesSize)
      return base::unexpected(UserScriptError::kValueQuotaExceeded);
  }

  prefs_->Set(prefs::kInstalledScripts, base::Value(std::move(records)));
  return {};
}

base::expected<void, UserScriptError> UserScriptStore::DeleteValue(
    std::string_view id,
    std::string_view key) {
  if (!IsValidScriptId(id))
    return base::unexpected(UserScriptError::kNotFound);
  if (key.size() > kMaxUserValueKeySize || !base::IsStringUTF8(key))
    return base::unexpected(UserScriptError::kValueQuotaExceeded);

  base::Value::List records =
      prefs_->GetList(prefs::kInstalledScripts).Clone();
  bool found = false;
  for (base::Value& record_value : records) {
    base::Value::Dict* record = record_value.GetIfDict();
    if (!record)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    const std::string* record_id = record->FindString(kIdKey);
    if (!record_id || !IsValidScriptId(*record_id))
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    if (*record_id != id)
      continue;
    if (found)
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    found = true;
    base::Value::Dict* values = record->FindDict(kValuesKey);
    if (!values && record->Find(kValuesKey))
      return base::unexpected(UserScriptError::kInvalidStoredMetadata);
    if (values) {
      values->Remove(key);
      if (values->empty())
        record->Remove(kValuesKey);
    }
  }
  if (!found)
    return base::unexpected(UserScriptError::kNotFound);
  prefs_->Set(prefs::kInstalledScripts, base::Value(std::move(records)));
  return {};
}

base::FilePath UserScriptStore::ScriptPath(
    std::string_view source_file) const {
  return source_directory_.AppendASCII(std::string(source_file));
}

}  // namespace userscripts
