// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_H_

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "base/observer_list.h"
#include "base/types/expected.h"
#include "components/keyed_service/core/keyed_service.h"
#include "ios/chrome/browser/userscripts/model/userscript_store.h"

class GURL;
class ProfileIOS;

namespace web {
class JavaScriptFeature;
}

namespace userscripts {

class UserscriptsJavaScriptFeature;

class UserscriptsService final : public KeyedService {
 public:
  class Observer : public base::CheckedObserver {
   public:
    virtual void OnUserscriptsChanged() = 0;
  };

  explicit UserscriptsService(ProfileIOS* profile);
  ~UserscriptsService() override;

  UserscriptsService(const UserscriptsService&) = delete;
  UserscriptsService& operator=(const UserscriptsService&) = delete;

  base::expected<std::vector<StoredUserScript>, UserScriptError> GetScripts()
      const;
  base::expected<std::string, UserScriptError> InstallScript(
      std::string_view source,
      const GURL& source_url);
  base::expected<void, UserScriptError> SetEnabled(std::string_view id,
                                                   bool enabled);
  base::expected<void, UserScriptError> RemoveScript(std::string_view id);
  base::expected<void, UserScriptError> SetScriptValue(std::string_view id,
                                                      std::string_view key,
                                                      base::Value value);
  base::expected<void, UserScriptError> DeleteScriptValue(
      std::string_view id,
      std::string_view key);
  web::JavaScriptFeature* GetJavaScriptFeature() const;

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  void NotifyChanged();

  UserScriptStore store_;
  base::ObserverList<Observer> observers_;
  std::unique_ptr<UserscriptsJavaScriptFeature> java_script_feature_;
};

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_H_
