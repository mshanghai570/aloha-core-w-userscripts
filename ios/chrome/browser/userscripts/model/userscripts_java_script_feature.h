// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_JAVA_SCRIPT_FEATURE_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_JAVA_SCRIPT_FEATURE_H_

#include <map>
#include <string>
#include <string_view>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "ios/chrome/browser/userscripts/model/userscripts_service.h"
#include "ios/web/public/js_messaging/java_script_feature.h"

class ProfileIOS;

namespace userscripts {

// Injects enabled scripts into eligible pages and validates native storage
// messages against the current profile, script grants, URL, frame and token.
class UserscriptsJavaScriptFeature final : public web::JavaScriptFeature,
                                           public UserscriptsService::Observer {
 public:
  UserscriptsJavaScriptFeature(ProfileIOS* profile,
                               UserscriptsService* service);
  ~UserscriptsJavaScriptFeature() override;

  UserscriptsJavaScriptFeature(const UserscriptsJavaScriptFeature&) = delete;
  UserscriptsJavaScriptFeature& operator=(
      const UserscriptsJavaScriptFeature&) = delete;

  std::vector<FeatureScript> GetScripts() const override;
  std::optional<std::string> GetScriptMessageHandlerName() const override;
  bool GetFeatureRepliesToMessages() const override;
  void ScriptMessageReceivedWithReply(
      web::WebState* web_state,
      const web::ScriptMessage& message,
      ScriptMessageReplyCallback callback) override;
  void OnUserscriptsChanged() override;

 private:
  FeatureScript::PlaceholderReplacements GetPlaceholderReplacements() const;
  std::string TokenForScript(std::string_view id) const;
  void UpdatePolicyCache(
      const std::vector<StoredUserScript>& scripts) const;

  raw_ptr<ProfileIOS> profile_;
  raw_ptr<UserscriptsService> service_;
  mutable std::map<std::string, std::string> script_tokens_;
  mutable std::map<std::string, UserScriptMetadata> script_metadata_;
  base::WeakPtrFactory<UserscriptsJavaScriptFeature> weak_factory_{this};
};

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_JAVA_SCRIPT_FEATURE_H_
