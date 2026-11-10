// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscripts_prefs.h"

#include "components/pref_registry/pref_registry_syncable.h"

namespace userscripts {
namespace prefs {

const char kInstalledScripts[] = "userscripts.installed_scripts";

}  // namespace prefs

void RegisterProfilePrefs(user_prefs::PrefRegistrySyncable* registry) {
  registry->RegisterListPref(prefs::kInstalledScripts);
}

}  // namespace userscripts
