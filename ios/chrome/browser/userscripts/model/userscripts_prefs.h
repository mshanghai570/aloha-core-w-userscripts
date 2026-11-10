// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_PREFS_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_PREFS_H_

namespace user_prefs {
class PrefRegistrySyncable;
}

namespace userscripts {
namespace prefs {
extern const char kInstalledScripts[];
}  // namespace prefs

void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry);

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_PREFS_H_
