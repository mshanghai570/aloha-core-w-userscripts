// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "ios/chrome/browser/userscripts/model/userscripts_service_factory.h"

#include "ios/chrome/browser/shared/model/profile/profile_ios.h"
#include "ios/chrome/browser/userscripts/model/userscripts_service.h"

namespace userscripts {

// static
UserscriptsService* UserscriptsServiceFactory::GetForProfile(
    ProfileIOS* profile) {
  if (!profile || profile->IsOffTheRecord())
    return nullptr;
  return GetInstance()->GetServiceForProfileAs<UserscriptsService>(
      profile, /*create=*/true);
}

// static
UserscriptsServiceFactory* UserscriptsServiceFactory::GetInstance() {
  static base::NoDestructor<UserscriptsServiceFactory> instance;
  return instance.get();
}

UserscriptsServiceFactory::UserscriptsServiceFactory()
    : ProfileKeyedServiceFactoryIOS("UserscriptsService",
                                    ProfileSelection::kNoInstanceInIncognito) {}

UserscriptsServiceFactory::~UserscriptsServiceFactory() = default;

std::unique_ptr<KeyedService>
UserscriptsServiceFactory::BuildServiceInstanceFor(ProfileIOS* profile) const {
  return std::make_unique<UserscriptsService>(profile);
}

}  // namespace userscripts
