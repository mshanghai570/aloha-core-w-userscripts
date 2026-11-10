// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180400
#import <WebKit/WKWebExtension.h>

@interface WKWebExtensionProbeResult : NSObject API_AVAILABLE(ios(18.4))
@property(nonatomic, strong) WKWebExtension* extension;
@property(nonatomic, strong) NSError* error;
@end

@implementation WKWebExtensionProbeResult
@end
#endif

#include <stdint.h>

#include <optional>
#include <string>

#import "base/base_paths.h"
#import "base/files/file_util.h"
#import "base/files/scoped_temp_dir.h"
#import "base/logging.h"
#import "base/path_service.h"
#import "base/run_loop.h"
#import "base/strings/sys_string_conversions.h"
#import "testing/gtest/include/gtest/gtest.h"
#import "testing/platform_test.h"

namespace {

using WKWebExtensionPackageLoadTest = PlatformTest;

base::FilePath GetProbeDataPath(const char* file_name) {
  base::FilePath source_root;
  CHECK(base::PathService::Get(base::DIR_SRC_TEST_DATA_ROOT, &source_root));
  return source_root.Append(FILE_PATH_LITERAL("web_extensions/test/data"))
      .AppendASCII(file_name);
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180400

WKWebExtensionProbeResult* LoadExtension(NSURL* resource_url)
    API_AVAILABLE(ios(18.4)) {
  WKWebExtensionProbeResult* result = [[WKWebExtensionProbeResult alloc] init];
  base::RunLoop run_loop;
  base::RunLoop* run_loop_ptr = &run_loop;
  [WKWebExtension extensionWithResourceBaseURL:resource_url
                             completionHandler:^(WKWebExtension* extension,
                                                 NSError* error) {
                               result.extension = extension;
                               result.error = error;
                               run_loop_ptr->Quit();
                             }];
  run_loop.Run();
  return result;
}

NSURL* FileURL(const base::FilePath& path) {
  return [NSURL fileURLWithPath:base::SysUTF8ToNSString(path.value())];
}

uint32_t ReadLittleEndian32(const std::string& bytes, size_t offset) {
  return static_cast<uint32_t>(static_cast<uint8_t>(bytes[offset])) |
         (static_cast<uint32_t>(static_cast<uint8_t>(bytes[offset + 1])) << 8) |
         (static_cast<uint32_t>(static_cast<uint8_t>(bytes[offset + 2])) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(bytes[offset + 3])) << 24);
}

// This bounded parser is test-only and operates on a checked-in, signed CRX3
// fixture. It intentionally does not verify signatures; production must use
// crx_file::Verify before extracting any user-selected package.
std::optional<std::string> ExtractFixtureCrx3Payload(
    const base::FilePath& crx_path) {
  constexpr int64_t kMaxFixtureBytes = 50 * 1024 * 1024;
  constexpr uint32_t kMaxHeaderBytes = 1024 * 1024;
  int64_t file_size = 0;
  if (!base::GetFileSize(crx_path, &file_size) || file_size < 12 ||
      file_size > kMaxFixtureBytes) {
    return std::nullopt;
  }

  std::string crx_bytes;
  if (!base::ReadFileToString(crx_path, &crx_bytes) ||
      crx_bytes.size() != static_cast<size_t>(file_size) ||
      crx_bytes.compare(0, 4, "Cr24") != 0 ||
      ReadLittleEndian32(crx_bytes, 4) != 3) {
    return std::nullopt;
  }

  const uint32_t header_size = ReadLittleEndian32(crx_bytes, 8);
  if (header_size > kMaxHeaderBytes) {
    return std::nullopt;
  }
  const size_t payload_offset = 12u + static_cast<size_t>(header_size);
  if (payload_offset >= crx_bytes.size()) {
    return std::nullopt;
  }
  return crx_bytes.substr(payload_offset);
}

std::string ErrorDescription(WKWebExtensionProbeResult* result)
    API_AVAILABLE(ios(18.4)) {
  if (!result.error.localizedDescription) {
    return "<no NSError description>";
  }
  return base::SysNSStringToUTF8(result.error.localizedDescription);
}

void ExpectRejectedWithDescription(NSURL* url) API_AVAILABLE(ios(18.4)) {
  WKWebExtensionProbeResult* result = LoadExtension(url);
  EXPECT_FALSE(result.extension)
      << "Unexpectedly loaded: " << base::SysNSStringToUTF8(url.absoluteString);
  ASSERT_TRUE(result.error) << "Expected an initializer error for "
                            << base::SysNSStringToUTF8(url.absoluteString);
  EXPECT_FALSE(result.error.localizedDescription.length == 0)
      << "Initializer returned an error without a localized description";
  LOG(INFO) << "WKWebExtension rejected "
            << base::SysNSStringToUTF8(url.absoluteString) << ": "
            << ErrorDescription(result);
}

TEST_F(WKWebExtensionPackageLoadTest, ProbesZipAndXpiPackageNames) {
  if (@available(iOS 18.4, *)) {
    const base::FilePath zip_path =
        GetProbeDataPath("aloha_wkwebextension_probe_mv3.zip");
    const base::FilePath xpi_path =
        GetProbeDataPath("aloha_wkwebextension_probe_mv3.xpi");

    WKWebExtensionProbeResult* zip_result = LoadExtension(FileURL(zip_path));
    ASSERT_TRUE(zip_result.extension) << ErrorDescription(zip_result);
    LOG(INFO) << "WKWebExtension ZIP control: accepted";

    WKWebExtensionProbeResult* xpi_result = LoadExtension(FileURL(xpi_path));
    if (xpi_result.extension) {
      LOG(INFO) << "WKWebExtension .xpi suffix: accepted";
    } else {
      LOG(INFO) << "WKWebExtension .xpi suffix: rejected: "
                << ErrorDescription(xpi_result);
      base::ScopedTempDir staging_dir;
      ASSERT_TRUE(staging_dir.CreateUniqueTempDir());
      const base::FilePath staged_zip_path =
          staging_dir.GetPath().AppendASCII("staged_xpi_bytes.zip");
      ASSERT_TRUE(base::CopyFile(xpi_path, staged_zip_path));
      WKWebExtensionProbeResult* staged_result =
          LoadExtension(FileURL(staged_zip_path));
      ASSERT_TRUE(staged_result.extension) << ErrorDescription(staged_result);
      LOG(INFO) << "WKWebExtension byte-identical staged .zip fallback: accepted";
    }
  } else {
    GTEST_SKIP() << "WKWebExtension requires iOS 18.4 or later";
  }
}

TEST_F(WKWebExtensionPackageLoadTest, ProbesCrx3PayloadAndRawCrx) {
  if (@available(iOS 18.4, *)) {
    const base::FilePath crx_path =
        GetProbeDataPath("aloha_wkwebextension_probe_valid_mv3.crx");
    std::optional<std::string> payload = ExtractFixtureCrx3Payload(crx_path);
    ASSERT_TRUE(payload.has_value());

    base::ScopedTempDir staging_dir;
    ASSERT_TRUE(staging_dir.CreateUniqueTempDir());
    const base::FilePath payload_zip_path =
        staging_dir.GetPath().AppendASCII("verified_fixture_payload.zip");
    ASSERT_TRUE(base::WriteFile(payload_zip_path, *payload));

    WKWebExtensionProbeResult* payload_result =
        LoadExtension(FileURL(payload_zip_path));
    if (payload_result.extension) {
      LOG(INFO) << "WKWebExtension extracted CRX3 ZIP payload: accepted";
    } else {
      LOG(INFO) << "WKWebExtension extracted CRX3 ZIP payload: rejected: "
                << ErrorDescription(payload_result);
    }
    EXPECT_TRUE(payload_result.extension) << ErrorDescription(payload_result);

    WKWebExtensionProbeResult* raw_crx_result = LoadExtension(FileURL(crx_path));
    if (raw_crx_result.extension) {
      LOG(INFO) << "WKWebExtension raw CRX3 package: accepted";
    } else {
      LOG(INFO) << "WKWebExtension raw CRX3 package: rejected: "
                << ErrorDescription(raw_crx_result);
    }
    EXPECT_FALSE(raw_crx_result.extension)
        << "Do not pass raw CRX bytes to WebKit without revisiting the importer gate";
    if (!raw_crx_result.extension) {
      EXPECT_TRUE(raw_crx_result.error);
    }
  } else {
    GTEST_SKIP() << "WKWebExtension requires iOS 18.4 or later";
  }
}

TEST_F(WKWebExtensionPackageLoadTest, ReportsMissingManifestAndMalformedZip) {
  if (@available(iOS 18.4, *)) {
    ExpectRejectedWithDescription(FileURL(GetProbeDataPath(
        "aloha_wkwebextension_probe_missing_manifest.zip")));
    ExpectRejectedWithDescription(FileURL(GetProbeDataPath(
        "aloha_wkwebextension_probe_malformed.zip")));
  } else {
    GTEST_SKIP() << "WKWebExtension requires iOS 18.4 or later";
  }
}

#else

TEST_F(WKWebExtensionPackageLoadTest, RequiresIOS184SDK) {
  GTEST_SKIP() << "Build this probe with an iOS 18.4 or later SDK";
}

#endif  // __IPHONE_OS_VERSION_MAX_ALLOWED >= 180400

}  // namespace
