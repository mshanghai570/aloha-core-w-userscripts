// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_FACTORY_H_
#define IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_FACTORY_H_

#include <memory>

#include "base/no_destructor.h"
#include "ios/chrome/browser/shared/model/profile/profile_keyed_service_factory_ios.h"

class ProfileIOS;

namespace userscripts {
class UserscriptsService;

class UserscriptsServiceFactory final : public ProfileKeyedServiceFactoryIOS {
 public:
  static UserscriptsService* GetForProfile(ProfileIOS* profile);
  static UserscriptsServiceFactory* GetInstance();

 private:
  friend class base::NoDestructor<UserscriptsServiceFactory>;

  UserscriptsServiceFactory();
  ~UserscriptsServiceFactory() override;

  std::unique_ptr<KeyedService> BuildServiceInstanceFor(
      ProfileIOS* profile) const override;
};

}  // namespace userscripts

#endif  // IOS_CHROME_BROWSER_USERSCRIPTS_MODEL_USERSCRIPTS_SERVICE_FACTORY_H_
