// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscripts_service.h"

#include <utility>

#include "ios/chrome/browser/shared/model/profile/profile_ios.h"
#include "ios/chrome/browser/userscripts/model/userscripts_java_script_feature.h"
#include "url/gurl.h"

namespace userscripts {

UserscriptsService::UserscriptsService(ProfileIOS* profile)
    : store_(profile->GetPrefs(),
             profile->GetStatePath().AppendASCII("Userscripts")),
      java_script_feature_(
          std::make_unique<UserscriptsJavaScriptFeature>(profile, this)) {}

UserscriptsService::~UserscriptsService() = default;

base::expected<std::vector<StoredUserScript>, UserScriptError>
UserscriptsService::GetScripts() const {
  return store_.GetScripts();
}

base::expected<std::string, UserScriptError> UserscriptsService::InstallScript(
    std::string_view source,
    const GURL& source_url) {
  auto result = store_.InstallScript(source, source_url);
  if (result)
    NotifyChanged();
  return result;
}

base::expected<void, UserScriptError> UserscriptsService::SetEnabled(
    std::string_view id,
    bool enabled) {
  auto result = store_.SetEnabled(id, enabled);
  if (result)
    NotifyChanged();
  return result;
}

base::expected<void, UserScriptError> UserscriptsService::RemoveScript(
    std::string_view id) {
  auto result = store_.RemoveScript(id);
  if (result)
    NotifyChanged();
  return result;
}

base::expected<void, UserScriptError> UserscriptsService::SetScriptValue(
    std::string_view id,
    std::string_view key,
    base::Value value) {
  return store_.SetValue(id, key, std::move(value));
}

base::expected<void, UserScriptError> UserscriptsService::DeleteScriptValue(
    std::string_view id,
    std::string_view key) {
  return store_.DeleteValue(id, key);
}

web::JavaScriptFeature* UserscriptsService::GetJavaScriptFeature() const {
  return java_script_feature_.get();
}

void UserscriptsService::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void UserscriptsService::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

void UserscriptsService::NotifyChanged() {
  for (Observer& observer : observers_)
    observer.OnUserscriptsChanged();
}

}  // namespace userscripts
