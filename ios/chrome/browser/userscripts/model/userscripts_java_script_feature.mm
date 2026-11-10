// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscripts_java_script_feature.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/strings/sys_string_conversions.h"
#include "base/unguessable_token.h"
#include "ios/chrome/browser/shared/model/profile/profile_ios.h"
#include "ios/chrome/browser/userscripts/model/userscript_matcher.h"
#include "ios/web/js_messaging/page_script_util.h"
#include "ios/web/public/js_messaging/script_message.h"
#include "ios/web/public/web_state.h"
#include "ios/web/web_state/ui/wk_web_view_configuration_provider.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace userscripts {
namespace {

constexpr char kRuntimeConfigPlaceholder[] = "__ALOHA_USERSCRIPTS_CONFIG__";
constexpr char kMessageHandlerName[] = "alohaUserscripts";

base::Value::List StringList(const std::vector<std::string>& values) {
  base::Value::List list;
  for (const std::string& value : values)
    list.Append(value);
  return list;
}

const char* RunAtName(UserScriptRunAt run_at) {
  switch (run_at) {
    case UserScriptRunAt::kDocumentStart:
      return "document-start";
    case UserScriptRunAt::kDocumentEnd:
      return "document-end";
    case UserScriptRunAt::kDocumentIdle:
      return "document-idle";
  }
  return "document-end";
}

base::Value::Dict SerializeMetadata(const UserScriptMetadata& metadata) {
  base::Value::Dict result;
  result.Set("name", metadata.name);
  result.Set("namespace", metadata.name_space);
  result.Set("version", metadata.version);
  result.Set("description", metadata.description);
  result.Set("author", metadata.author);
  result.Set("matches", StringList(metadata.matches));
  result.Set("includes", StringList(metadata.includes));
  result.Set("excludes", StringList(metadata.excludes));
  result.Set("excludeMatches", StringList(metadata.exclude_matches));
  result.Set("grants", StringList(metadata.grants));
  result.Set("connect", StringList(metadata.connect));
  result.Set("requireUrls", StringList(metadata.require_urls));
  result.Set("runAt", RunAtName(metadata.run_at));
  result.Set("noframes", metadata.noframes);

  base::Value::List resources;
  for (const UserScriptResource& resource : metadata.resources) {
    base::Value::Dict item;
    item.Set("name", resource.name);
    item.Set("url", resource.url);
    resources.Append(std::move(item));
  }
  result.Set("resources", std::move(resources));
  return result;
}

bool HasGrant(const UserScriptMetadata& metadata,
              std::string_view modern,
              std::string_view legacy) {
  return std::find(metadata.grants.begin(), metadata.grants.end(), modern) !=
             metadata.grants.end() ||
         std::find(metadata.grants.begin(), metadata.grants.end(), legacy) !=
             metadata.grants.end();
}

const char* ErrorMessage(UserScriptError error) {
  switch (error) {
    case UserScriptError::kInvalidSourceURL:
      return "Invalid userscript source URL.";
    case UserScriptError::kSourceTooLarge:
      return "Userscript source exceeds the size limit.";
    case UserScriptError::kInvalidScript:
      return "Userscript source is invalid.";
    case UserScriptError::kInvalidPattern:
      return "Userscript URL pattern is invalid.";
    case UserScriptError::kProfileQuotaExceeded:
      return "Userscript profile storage limit exceeded.";
    case UserScriptError::kWriteFailed:
      return "Unable to write userscript data.";
    case UserScriptError::kInvalidStoredMetadata:
      return "Userscript profile data is invalid.";
    case UserScriptError::kReadFailed:
      return "Unable to read userscript data.";
    case UserScriptError::kNotFound:
      return "Userscript was removed or is unavailable.";
    case UserScriptError::kValueQuotaExceeded:
      return "Userscript value exceeds its storage limit.";
  }
  return "Userscript operation failed.";
}

}  // namespace

UserscriptsJavaScriptFeature::UserscriptsJavaScriptFeature(
    ProfileIOS* profile,
    UserscriptsService* service)
    : web::JavaScriptFeature(web::ContentWorld::kPageContentWorld, {}),
      profile_(profile),
      service_(service) {
  service_->AddObserver(this);
}

UserscriptsJavaScriptFeature::~UserscriptsJavaScriptFeature() {
  service_->RemoveObserver(this);
}

std::vector<UserscriptsJavaScriptFeature::FeatureScript>
UserscriptsJavaScriptFeature::GetScripts() const {
  std::vector<FeatureScript> scripts;
  scripts.push_back(FeatureScript::CreateWithFilename(
      "userscript_runtime", FeatureScript::InjectionTime::kDocumentStart,
      FeatureScript::TargetFrames::kAllFrames,
      FeatureScript::ReinjectionBehavior::kInjectOncePerWindow,
      base::BindRepeating(
          &UserscriptsJavaScriptFeature::GetPlaceholderReplacements,
          weak_factory_.GetWeakPtr())));
  return scripts;
}

std::optional<std::string>
UserscriptsJavaScriptFeature::GetScriptMessageHandlerName() const {
  return kMessageHandlerName;
}

bool UserscriptsJavaScriptFeature::GetFeatureRepliesToMessages() const {
  return true;
}

void UserscriptsJavaScriptFeature::ScriptMessageReceivedWithReply(
    web::WebState* web_state,
    const web::ScriptMessage& message,
    ScriptMessageReplyCallback callback) {
  auto fail = [&callback](const char* error) {
    std::move(callback).Run(nullptr, base::SysUTF8ToNSString(error));
  };

  if (!web_state || !message.body()) {
    fail("Malformed userscript message.");
    return;
  }
  const base::Value::Dict* body = message.body()->GetIfDict();
  if (!body) {
    fail("Malformed userscript message.");
    return;
  }

  const std::string* script_id = body->FindString("scriptId");
  const std::string* token = body->FindString("token");
  const std::string* operation = body->FindString("operation");
  const base::Value::Dict* arguments = body->FindDict("arguments");
  if (!script_id || !token || !operation || !arguments) {
    fail("Malformed userscript message.");
    return;
  }

  auto token_it = script_tokens_.find(*script_id);
  if (token_it == script_tokens_.end() || token_it->second != *token) {
    fail("Userscript context expired; reload the page.");
    return;
  }

  const std::optional<GURL> request_url = message.request_url();
  if (!request_url || !request_url->is_valid() ||
      !request_url->SchemeIsHTTPOrHTTPS() ||
      message.security_origin().opaque() ||
      url::Origin::Create(*request_url) != message.security_origin()) {
    fail("Userscript message origin could not be verified.");
    return;
  }

  auto metadata = script_metadata_.find(*script_id);
  if (metadata == script_metadata_.end() ||
      !UserScriptMatches(metadata->second, *request_url,
                         message.is_main_frame())) {
    fail("Userscript is not enabled for this page or frame.");
    return;
  }

  if (*operation == "setValue") {
    if (!HasGrant(metadata->second, "GM.setValue", "GM_setValue")) {
      fail("Userscript did not request GM.setValue permission.");
      return;
    }
    const std::string* key = arguments->FindString("key");
    const base::Value* value = arguments->Find("value");
    if (!key || !value) {
      fail("Userscript value message is incomplete.");
      return;
    }
    auto result = service_->SetScriptValue(*script_id, *key, value->Clone());
    if (!result) {
      fail(ErrorMessage(result.error()));
      return;
    }
    base::Value reply(true);
    std::move(callback).Run(&reply, nil);
    return;
  }

  if (*operation == "deleteValue") {
    if (!HasGrant(metadata->second, "GM.deleteValue", "GM_deleteValue")) {
      fail("Userscript did not request GM.deleteValue permission.");
      return;
    }
    const std::string* key = arguments->FindString("key");
    if (!key) {
      fail("Userscript value key is missing.");
      return;
    }
    auto result = service_->DeleteScriptValue(*script_id, *key);
    if (!result) {
      fail(ErrorMessage(result.error()));
      return;
    }
    base::Value reply(true);
    std::move(callback).Run(&reply, nil);
    return;
  }

  fail("Unsupported userscript native operation.");
}

void UserscriptsJavaScriptFeature::OnUserscriptsChanged() {
  auto scripts = service_->GetScripts();
  if (scripts) {
    UpdatePolicyCache(scripts.value());
  } else {
    script_tokens_.clear();
    script_metadata_.clear();
  }
  web::WKWebViewConfigurationProvider::FromBrowserState(profile_)
      .UpdateScripts();
}

web::JavaScriptFeature::FeatureScript::PlaceholderReplacements
UserscriptsJavaScriptFeature::GetPlaceholderReplacements() const {
  base::Value::Dict config;
  base::Value::List script_list;
  auto scripts = service_->GetScripts();
  if (scripts) {
    UpdatePolicyCache(scripts.value());
    for (StoredUserScript& stored : scripts.value()) {
      if (!stored.enabled)
        continue;
      base::Value::Dict script;
      script.Set("id", stored.id);
      script.Set("enabled", true);
      script.Set("source", stored.parsed.source);
      script.Set("bodyOffset",
                 static_cast<int>(stored.parsed.body_offset));
      script.Set("metadata", SerializeMetadata(stored.parsed.metadata));
      script.Set("values", std::move(stored.values));
      script.Set("nativeToken", TokenForScript(stored.id));
      script_list.Append(std::move(script));
    }
  } else {
    script_tokens_.clear();
    script_metadata_.clear();
  }
  config.Set("scripts", std::move(script_list));

  std::string json;
  if (!base::JSONWriter::Write(base::Value(std::move(config)), &json))
    json = R"({"scripts":[]})";
  NSString* placeholder =
      base::SysUTF8ToNSString(kRuntimeConfigPlaceholder);
  return @{placeholder : base::SysUTF8ToNSString(json)};
}

std::string UserscriptsJavaScriptFeature::TokenForScript(
    std::string_view id) const {
  auto [it, inserted] = script_tokens_.try_emplace(std::string(id));
  if (inserted)
    it->second = base::UnguessableToken::Create().ToString();
  return it->second;
}

void UserscriptsJavaScriptFeature::UpdatePolicyCache(
    const std::vector<StoredUserScript>& scripts) const {
  std::map<std::string, UserScriptMetadata> active_scripts;
  for (const StoredUserScript& script : scripts) {
    if (script.enabled)
      active_scripts.emplace(script.id, script.parsed.metadata);
  }
  script_metadata_ = std::move(active_scripts);

  for (auto token = script_tokens_.begin(); token != script_tokens_.end();) {
    if (!script_metadata_.contains(token->first))
      token = script_tokens_.erase(token);
    else
      ++token;
  }
}

}  // namespace userscripts
