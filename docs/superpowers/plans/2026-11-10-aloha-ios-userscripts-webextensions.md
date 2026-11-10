# Aloha iOS Userscripts and WebExtensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a profile-scoped userscript manager on iOS 18.0+ and a separately availability-gated WebKit WebExtension host/import path on iOS 18.4+, without merging away from the selected Aloha release branch.

**Architecture:** Keep userscripts on Chromium iOS's existing `JavaScriptFeature` and per-profile `WKWebViewConfigurationProvider` path. Keep WebExtensions as a distinct iOS 18.4+ adapter around Apple's WebKit extension runtime, backed by validated app-owned packages and explicit, profile-scoped permissions. The actual WebKit package-loader probe is a hard gate before production CRX/XPI importer implementation.

**Tech Stack:** Chromium iOS C++/Objective-C++, UIKit, existing profile keyed-service and PrefService patterns, WebKit `WKWebView`/`WKWebExtension` APIs, GN/Ninja, and Node's built-in test runner for the isolated JavaScript runtime.

**Spec:** `docs/superpowers/specs/2026-11-10-aloha-ios-userscripts-webextensions-design.md`

## Global Constraints

- The userscript feature must run on iOS 18.0–18.3 using the existing WebKit injection path; `WKWebExtension*` code and UI runtime behavior are gated at iOS 18.4+.
- Neither layer executes in an off-the-record profile; no state or permission grant is shared with private browsing.
- Source, dependencies, packages, metadata, and extension grants are profile-scoped; never persist security-scoped picker URLs.
- Do not force reload tabs after userscript edits; changes affect future document injections only.
- The required userscript metadata and `GM_*` API floor is exactly the list in the approved design's **Initial compatibility floor** section. Unsupported directives/APIs are visible, not silently ignored.
- Remote script installation and dependency fetching require a user-initiated action, bounded content, and explicit confirmation. Manual userscript update checks only; no automatic userscript or WebExtension update service.
- CRX support is CRX3 only; verify with `//components/crx_file:crx_file`, stage its ZIP payload, and do not label its self-signature as trusted publisher identity. Reject CRX2.
- Initial conservative bounds: user script source 2 MiB each; a single `@require` or `@resource` 5 MiB; aggregate source plus dependencies 10 MiB per script and 50 MiB per profile. CRX/XPI archive 50 MiB compressed, 128 MiB total uncompressed, 2,000 entries, 16 MiB per entry, root `manifest.json` 1 MiB, and CRX3 header 1 MiB. Enforce before allocation/extraction and surface limit-specific errors.
- **Hard gate:** before production archive-importer code is written, the package-shape test in Task 8 must pass against Apple's actual initializer on an iOS 18.4+ Xcode simulator/device. If it cannot be run or fails, stop at that gate, report the result, and do not substitute a docs-only claim.
- No Xcode/Apple-runtime pass may be claimed from this Linux sandbox. Do not merge Chromium `main` or another Aloha release into `abr-150.0.7871.46`.

## Review Focus

1. **Malformed, oversized, or ambiguous metadata** (BOM, CRLF, missing/duplicate scalar tags, repeated list tags, unknown grants): pin parse errors/warnings and installation refusal in `UserScriptParserTest` (Task 1).
2. **Host-pattern boundary cases** (malformed wildcard/regex, ports, punycode, include/exclude precedence, main-frame versus subframe): pin match/no-match behavior in `UserScriptMatcherTest` (Task 2).
3. **Untrusted script/dependency downloads** (redirect from HTTPS to HTTP, non-HTTP scheme, oversized response, network truncation): pin rejection and no execution before consent in `UserScriptInstallFlowTest` (Task 5).
4. **Archive attacks** (CRX2, bad CRX3 signature/header lengths, ZIP traversal, normalized-name collision, symlink, zip bomb, missing root manifest): pin rejection and cleanup in `WebExtensionArchiveImporterTest` (Task 9).
5. **Permission and runtime failure behavior** (denial, no prompt response, expired grant, unsupported API, extension in OTR): pin deny-by-default, expiry, compatibility reporting, and private-profile exclusion in `WebExtensionRuntimeTest` (Tasks 7 and 10).

## File Map

| Area | Files and responsibility |
|---|---|
| Userscript model | New `ios/chrome/browser/userscripts/model/` target: `userscript.{h,mm}` for records and metadata, `userscript_parser.{h,mm}` for header parsing, `userscript_matcher.{h,mm}` for URL/frame policy, and unit tests. |
| Profile persistence | New `userscript_store.{h,mm}`, `userscripts_service.{h,mm}`, `userscripts_service_factory.{h,mm}`, and `userscripts_prefs.{h,mm}`. Register the profile pref in `ios/chrome/browser/shared/model/prefs/browser_prefs.mm`; source files live under `ProfileIOS::GetStatePath()/Userscripts/`. |
| Injection/runtime | New `userscript_runtime.js` plus Node tests; `userscript_java_script_feature.{h,mm}` owns a stable page-world feature and serialized injection payload; `userscript_script_message_handler.{h,mm}` validates GM API messages and performs native operations. Wire `ChromeWebClient::GetJavaScriptFeatures` in `ios/chrome/browser/web/model/chrome_web_client.mm` and refresh scripts through `WKWebViewConfigurationProvider::UpdateScripts()`. |
| Userscript UI | New `ios/chrome/browser/userscripts/ui/` manager/editor/coordinator and unit tests. Use `UIDocumentPickerViewController` for local `.user.js` files and a user-confirmed HTTPS URL install flow; cache bounded `@require`/`@resource` responses. |
| Settings and toolbar | Modify `ios/chrome/browser/settings/ui_bundled/settings_table_view_controller.{mm,h}`, `settings_table_view_controller_constants.h`, `settings/ui_bundled/BUILD.gn`, `ios/chrome/app/strings/ios_strings.grd`, `ios/chrome/browser/shared/public/commands/settings_commands.h`, and its settings-navigation implementation. Add an overflow-menu destination via `overflow_menu_constants.h`, `overflow_menu_mediator.mm`, `overflow_menu_metrics.h`, and `tools/metrics/histograms/metadata/ios/enums.xml`. |
| WebExtension runtime | New `ios/chrome/browser/web_extensions/model/` and `runtime/` targets for `WebExtensionService`, package/context lifecycle, `WKWebExtensionControllerDelegate`, and Chromium `WebState` tab/window adapters. Attach the controller before WebViews are created through `WKWebViewConfigurationProvider`. |
| WebExtension tests/import/UI | New iOS 18.4+ initializer probe and runtime tests; new archive validator/importer with test-only fixtures; extension manager UI for install, enable, disable, manual replacement, remove, permissions, and errors. Add targets to `ios/chrome/test/BUILD.gn` and relevant existing test aggregators. |

## Tasks

### Task 1: Parse and preserve userscript metadata

**Files:** Create `userscript.{h,mm}`, `userscript_parser.{h,mm}`, `userscript_parser_unittest.mm`, and `ios/chrome/browser/userscripts/model/BUILD.gn`; add `//ios/chrome/browser/userscripts/model:unit_tests` to `ios/chrome/test/BUILD.gn`.

**Interfaces:** Produce `ParsedUserScript { std::string source; UserScriptMetadata metadata; std::vector<std::string> unsupported_directives; std::vector<std::string> unsupported_grants; }` and `base::expected<ParsedUserScript, UserScriptParseError> ParseUserScript(std::string_view source)`. Keep the raw source exactly as imported; use the approved design's directive list. Repeated list directives accumulate; first non-empty scalar value wins; unsupported values are reported and recognized malformed values reject installation.

- [ ] Add `UserScriptParserTest` cases for a valid metadata block, BOM/CRLF normalization, missing terminator/name, duplicate scalar tags, repeated `@match`/`@grant`, unknown directive, and unknown grant.
- [ ] Run `ios/tools/run_unittests.py --out-dir out/Debug-iphonesimulator --test-target ios_chrome_unittests --gtest_filter='UserScriptParserTest.*'` on macOS after the iOS simulator output directory is configured; expected: the new tests fail before implementation and pass after it. Here, record that GN/Ninja/Xcode are absent.
- [ ] Implement only the parser and data types needed for these cases; do not add a code editor or runtime behavior in this task.
- [ ] Run `git diff --check`; inspect the parser/test diff.

### Task 2: Implement URL, frame, and run-location policy

**Files:** Create `userscript_matcher.{h,mm}` and `userscript_matcher_unittest.mm`; modify the model `BUILD.gn`.

**Interfaces:** `bool UserScriptMatches(const UserScriptMetadata& metadata, const GURL& url, bool is_main_frame)` and `web::JavaScriptFeature::FeatureScript::InjectionTime InjectionTimeFor(UserScriptRunAt run_at)`. Use Chromium `URLPattern` for `@match` and existing glob matching for `@include`; compile patterns during parse so bad patterns have an actionable error. Map `document-idle` to `kDocumentEnd` and defer the JavaScript runner with `requestIdleCallback` plus a `setTimeout` fallback.

- [ ] Add `UserScriptMatcherTest` coverage for `@match`, `@include`, both exclusion forms, exclusion precedence, wildcard subdomains, ports, malformed patterns, main-frame/all-frame, and `@noframes`.
- [ ] Define no-positive-match behavior as **do not run**; block browser-internal, extension, and file URLs; cover these in tests.
- [ ] Map `document-start`, `document-end`, and `document-idle` to WebKit timing/ready-state behavior; test each mapping and its fallback when the DOM has already advanced.
- [ ] Implement and run the tests on macOS; run `git diff --check` here.

### Task 3: Persist scripts through a profile service

**Files:** Create `userscript_store.{h,mm}`, `userscripts_service.{h,mm}`, `userscripts_service_factory.{h,mm}`, `userscripts_prefs.{h,mm}`, `userscript_store_unittest.mm`, and model GN entries; modify `ios/chrome/browser/shared/model/prefs/browser_prefs.mm` to register the non-syncable profile pref.

**Interfaces:** `UserscriptsService::GetForProfile(ProfileIOS*)`, `GetScripts()`, `InstallScript(std::string_view source, const GURL& source_url) -> base::expected<std::string, UserScriptError>`, `SetEnabled(std::string_view id, bool)`, `RemoveScript(std::string_view id)`, and observer add/remove methods. Use a stable ID derived from `@namespace` plus `@name`; write each source to a temporary file and atomically replace the stored file and metadata record. Keep metadata/index in profile PrefService and source/dependencies under `GetStatePath()/Userscripts/`.

- [ ] Add store tests for install, edit/replacement, enable/disable, removal cleanup, failed write rollback, and reopening the profile store.
- [ ] Add a service test proving separate regular profiles do not share scripts and off-the-record profiles cannot install, read, or execute scripts.
- [ ] Enforce the per-script/profile limits from Global Constraints before writing; verify that a rejected oversized write leaves the previous version intact.
- [ ] Implement the profile factory using `ProfileKeyedServiceFactoryIOS`; register prefs in the existing eager profile-pref path to avoid factory-registration order errors.
- [ ] Run service/store tests on macOS and `git diff --check` here.

### Task 4: Inject scripts and expose the approved GM API floor

**Files:** Create `userscript_runtime.js`, `userscript_runtime.test.js`, `userscript_java_script_feature.{h,mm}`, `userscript_script_message_handler.{h,mm}`, and the userscripts model GN entries; modify `ios/chrome/browser/web/model/chrome_web_client.{mm,BUILD.gn}` and extend `ios/web/web_state/ui/wk_web_view_configuration_provider_unittest.mm` / `ios/web/BUILD.gn` as appropriate.

**Interfaces:** Keep one stable profile-owned `JavaScriptFeature` in the page content world. Its `GetScripts()` returns the runtime resource with a placeholder replacement containing the currently enabled script definitions and per-script synchronous-storage snapshot; its named message handler accepts `{scriptId, operation, arguments}` and rejects calls not declared by that script's `@grant`/`@connect` policy. On service changes call that BrowserState's `WKWebViewConfigurationProvider::UpdateScripts()`.

- [ ] Add Node tests for script match/injection timing, page-world `unsafeWindow`, `@noframes`, `GM_info`, modern and legacy storage aliases, menu-command registration, resource lookup, and unsupported grant reporting.
- [ ] Add native handler tests for per-script value isolation, storage persistence after reinjection, `@connect` allow/deny, clipboard/notification permission denial, request abort/error mapping, and `GM_openInTab` command routing.
- [ ] Implement `GM.xmlHttpRequest`/`GM_xmlhttpRequest` over the existing profile network loader, enforce declared `@connect` hosts and response bounds, and seed the legacy synchronous value cache through the feature placeholder; persist write-throughs via the message handler.
- [ ] Wire the feature into `ChromeWebClient::GetJavaScriptFeatures(browser_state)` and call `UpdateScripts()` on store changes. Test that updates affect a subsequent document, do not retroactively change an already-running document, and never inject into OTR.
- [ ] Run `node --test ios/chrome/browser/userscripts/model/userscript_runtime.test.js`; expected: all tests pass on this sandbox. Run native tests on macOS when available.

### Task 5: Build the userscript manager and install/edit flow

**Files:** Create `userscripts_manager_view_controller.{h,mm}`, `userscript_editor_view_controller.{h,mm}`, `userscript_install_mediator.{h,mm}`, and their UI `BUILD.gn`/unit tests; add `//ios/chrome/browser/userscripts/ui:unit_tests` to `ios/chrome/test/BUILD.gn`; reuse the shared table-view multiline edit cell and the established document-picker pattern.

**Interfaces:** The manager observes `UserscriptsService`; editor save calls `InstallScript`/replace and remove/toggle calls the service API from Task 3. File import starts security-scoped access, copies bytes to staging, and releases access on every success/error/cancel path. URL install accepts an explicit HTTP(S) URL entered by the user, presents the script metadata and requested grants before saving, and uses a profile-scoped URL loader.

- [ ] Add UI/mediator tests for empty/populated lists, edit/save/cancel, enable/disable, delete confirmation, file-picker cancellation, security-scope cleanup, and invalid metadata.
- [ ] Test HTTP-to-HTTPS redirect handling and reject HTTPS-to-HTTP downgrade, non-HTTP(S) redirect targets, oversized/truncated body, invalid UTF-8, and dependency fetch failure; no script runs before the user confirms.
- [ ] Resolve `@require`/`@resource` only during explicit install/manual update; enforce dependency bounds, cache under the script ID, and show failure instead of installing a partially fetched script.
- [ ] Add manual update-check/apply behavior using `@updateURL`/`@downloadURL`; replacement with new grants or match hosts requires renewed user consent. Do not add background auto-update.
- [ ] Run focused UI/mediator tests on macOS and the JavaScript tests here.

### Task 6: Add Settings root and direct toolbar destination

**Files:** Modify `settings_table_view_controller.{h,mm}`, `settings_table_view_controller_constants.h`, `settings/ui_bundled/BUILD.gn`, `ios_strings.grd`, `settings_commands.h`, and the settings navigation command implementation. Modify overflow `overflow_menu_constants.h`, `overflow_menu_mediator.mm`, `overflow_menu_metrics.h`, and `tools/metrics/histograms/metadata/ios/enums.xml`; add/extend the settings and overflow unit tests and their GN target dependencies.

**Interfaces:** Add a localized **Userscripts** Settings row that pushes the manager. Add a new global `overflow_menu::Destination` with a stable appended metric value; its handler calls `SettingsCommands::showUserscriptsManager` and presents the manager directly, not merely the Settings root. Add the string-name and histogram mappings in every `LINT.ThenChange` partner without renumbering existing values.

- [ ] Add a Settings controller test proving row presence, accessibility ID, and navigation to the manager.
- [ ] Add an overflow mediator test proving the destination is present and invokes the direct manager route; ensure existing destinations/metrics remain unchanged.
- [ ] Run the existing focused Settings and overflow unit tests on macOS; run `git diff --check` and `python3 buildtools/checkdeps/checkdeps.py` here.

### Task 7: Add the iOS 18.4+ WebExtension host/runtime adapter

**Files:** Create `ios/chrome/browser/web_extensions/model/web_extension_service.{h,mm}`, `runtime/web_extension_controller_delegate.{h,mm}`, `runtime/web_extension_tab_adapter.{h,mm}`, and runtime unit tests/BUILD.gn; modify `WKWebViewConfigurationProvider` setup, `ios/web/BUILD.gn`, `ios/chrome/test/BUILD.gn`, and the WebExtension module's aggregate dependencies.

**Interfaces:** `WebExtensionService::GetForProfile(ProfileIOS*)` owns extension contexts, app-owned resource URLs, a `WKWebExtensionController`, permission records, and tab/window adapters. Gate every WebKit extension call with `@available(iOS 18.4, *)`. Set the controller on each regular-profile `WKWebViewConfiguration` before WebViews are created. Implement only delegate operations mapped to Chromium `WebStateList`/`Browser`; reject unsupported operations and surface `context.errors` and `context.unsupportedAPIs`.

- [ ] Add runtime tests for iOS availability behavior, controller association before WebView construction, tab/window mapping and close/focus/create requests, multiple regular profiles, and OTR exclusion.
- [ ] Add permission delegate tests for requested API and host patterns, explicit allow/deny, unanswered prompt denial, persisted per-profile grants, expiry restoration, and revoke.
- [ ] Load a minimal test extension from an app-owned directory fixture and confirm content injection in a real WebView on iOS 18.4+; do not treat unimplemented Chrome/Firefox APIs as success.
- [ ] Compile/run this target on a current Xcode/iOS 18.4+ SDK; this sandbox cannot verify availability declarations or Objective-C selector compatibility.

### Task 8: Probe Apple's actual package initializer (mandatory pre-import gate)

**Files:** Create `runtime/wk_web_extension_package_load_unittest.mm`, minimal manifest/ZIP/XPI fixtures, and its GN test-data registration. A test-only helper may extract a bounded ZIP payload from the existing signed CRX3 fixture; do not add production importer code in this task.

- [ ] Test `WKWebExtension(resourceBaseURL:)` on a minimal root-manifest ZIP and the same bytes with an `.xpi` suffix; if direct `.xpi` loading fails, test a byte-identical staged `.zip` filename.
- [ ] Test the ZIP payload from a valid CRX3 fixture through the same initializer and confirm that a raw `.crx` is not accepted as though it were ZIP.
- [ ] Test missing-root-manifest and malformed ZIP cases produce an actionable initializer error.
- [ ] Run only on iOS 18.4+ simulator/device with Xcode. **Do not start Task 9 unless this actual-runtime test passes.** If it fails or cannot be run, stop and report the evidence rather than implementing importer code on assumption.

### Task 9: Implement bounded CRX3/XPI archive validation and import

**Files:** Create `ios/chrome/browser/web_extensions/import/web_extension_archive_validator.{h,mm}`, `web_extension_package_importer.{h,mm}`, importer unit tests, and test data/build entries; add dependencies on `//components/crx_file:crx_file` and `//third_party/zlib/google:zip` only if GN confirms them available for iOS.

**Interfaces:** `ValidateWebExtensionArchive(const base::FilePath&) -> base::expected<ValidatedPackage, ImportError>` and `ImportWebExtensionPackage(ProfileIOS*, const base::FilePath&) -> base::expected<InstalledExtension, ImportError>`. `ValidatedPackage` includes a staged app-owned ZIP URL, root manifest data, package format, CRX3 verified status, requested permissions, and visible warnings.

- [ ] Add tests for XPI ZIP success, valid signed CRX3 success, CRX2 rejection, invalid/corrupt signature, malformed/truncated CRX header, unsafe/duplicate paths, symlink entries, excessive entry counts, compressed/uncompressed/entry/manifest limits, nested-only manifest, and staging cleanup.
- [ ] Verify CRX3 with `crx_file::Verify` before reading payload framing; cap the declared header before allocation and copy only the ZIP payload into a `.zip` file. Never pass raw CRX bytes to WebKit.
- [ ] Preflight ZIP entry names, link types, sizes, duplicate normalized paths, and root `manifest.json` without extracting untrusted paths. Normalize an XPI into a byte-identical staged `.zip` if the Task 8 result requires it.
- [ ] Map invalid signature, unsupported CRX2, malformed archive, unsupported manifest/API, and permission refusal to distinct user-visible errors. Tell users that CRX3 self-signature verifies integrity, not trusted publisher identity.
- [ ] Run importer tests and the package-load test again on iOS 18.4+ Xcode after implementation; run static source/dependency checks here.

### Task 10: Finish extension management UI and integrated verification

**Files:** Create `ios/chrome/browser/web_extensions/ui/` extension list/details/permission prompt controllers and tests; add `//ios/chrome/browser/web_extensions/ui:unit_tests` to `ios/chrome/test/BUILD.gn`; add strings and GN dependencies; integrate the Extensions section into the Userscripts manager and its direct toolbar route.

- [ ] Add manager tests for install preview, requested permission display, explicit grant/deny, persisted/revoked grant status, enable/disable, manual replacement, remove/package cleanup, unsupported iOS version, `unsupportedAPIs`, and initializer errors.
- [ ] Confirm grant records are per-extension/per-regular-profile, re-applied with saved expiration, and removed with the extension; never load or grant in OTR.
- [ ] On iOS 18.0–18.3, verify the userscript page remains available and extension actions show a clear 18.4+ requirement without referencing unavailable WebKit symbols.
- [ ] Final macOS verification: `autoninja -C out/Debug-iphonesimulator ios_chrome_unittests ios_web_unittests`; run `ios/tools/run_unittests.py --out-dir out/Debug-iphonesimulator --test-target ios_chrome_unittests --gtest_filter='UserScript*:WebExtension*:SettingsTableViewControllerTest.*:OverflowMenuMediatorTest.*'` and `ios/tools/run_unittests.py --out-dir out/Debug-iphonesimulator --test-target ios_web_unittests --gtest_filter='WKWebViewConfigurationProviderTest.*'`; run package-load/runtime tests on iOS 18.4+.
- [ ] Final sandbox verification: `node --test ios/chrome/browser/userscripts/model/userscript_runtime.test.js`, `git diff --check`, `python3 buildtools/checkdeps/checkdeps.py`, targeted source/availability searches, and a complete diff review. Report all Xcode-only checks as pending until run on Apple tooling.

## Execution Boundary

Tasks 1–6 are the first implementation tranche and preserve the approved iOS 18.0 userscript fallback. Task 7 prepares the distinct WebKit host. Task 8 is a hard external verification gate; because this workspace has no Xcode, the approved plan does **not** authorize guessing past that gate. Tasks 9–10 may be implemented only after the user or an available macOS/Xcode environment confirms the Task 8 package-loader result. No upstream merge, external release, or commit is part of this plan.
