// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_MATCHER_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_MATCHER_H_

#include "base/types/expected.h"
#include "ios/chrome/browser/userscripts/model/userscript.h"
#include "ios/web/public/js_messaging/java_script_feature.h"

class GURL;

namespace userscripts {

enum class UserScriptPatternError {
  kInvalidMatchPattern,
  kInvalidExcludeMatchPattern,
};

// Validates all @match and @exclude-match patterns before a script is stored.
base::expected<void, UserScriptPatternError> ValidateUserScriptPatterns(
    const UserScriptMetadata& metadata);

// Returns false for invalid/non-HTTP(S) URLs, unmatched scripts, and excluded
// URLs. `@noframes` scripts are only eligible in the main frame.
bool UserScriptMatches(const UserScriptMetadata& metadata,
                       const GURL& url,
                       bool is_main_frame);

web::JavaScriptFeature::FeatureScript::InjectionTime InjectionTimeFor(
    UserScriptRunAt run_at);

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPT_MATCHER_H_
