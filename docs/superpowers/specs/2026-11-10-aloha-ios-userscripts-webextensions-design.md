# Aloha iOS Userscripts and WebExtensions — Design Draft

**Status:** Approved by the user on 2026-11-10.

## Intent

Add a real, profile-scoped userscript manager to the iOS browser in this Aloha release checkout. Users can install, inspect, edit, enable/disable, and remove userscripts in Settings, and open that manager directly from the browser toolbar menu. Keep this layer working on the app's existing iOS 18.0 minimum. Add a separate Apple WebKit WebExtension host for compatible extension packages on iOS 18.4 and later, with `.crx` and `.xpi` import, explicit permission decisions, and honest compatibility/error reporting.

The goal is to extend the existing Chromium-derived iOS WebView stack, not replace it or merge a different Chromium history into the Aloha release.

## Goals

- Use a focused profile service/store for user scripts, with source and metadata isolated per regular profile; scripts do not run in off-the-record profiles by default.
- Support `.user.js` installation from a local file or a user-confirmed web link, plus in-app edit/manage actions, metadata-based URL matching and run timing, and the explicit compatibility floor below. Parse and report unknown/unsupported directives and APIs rather than silently claiming complete Tampermonkey/Greasemonkey parity.
- Inject userscripts through the existing `JavaScriptFeature` / `WKWebViewConfigurationProvider` lifecycle. When a script changes, update future document injections; do not unexpectedly reload open tabs or claim to undo effects already run.
- Add a localized **Userscripts** settings row and a global overflow-menu destination that opens the manager directly. Keep extension package management in the same feature area, separated from the userscript list.
- On iOS 18.4+, use `WKWebExtension`, `WKWebExtensionContext`, and `WKWebExtensionController`, attached through `WKWebViewConfiguration.webExtensionController`, rather than implementing a second browser-extension engine.
- Keep basic userscript behavior on iOS 18.0–18.3; clearly explain that extension packages require iOS 18.4+.
- Validate extension archives before installation. Show requested permissions, obtain user consent, and present import, permission, manifest, runtime, and compatibility failures with actionable messages.
- Add unit tests for parser/matcher/storage/injection policy, archive validation and error mapping, profile isolation, and the iOS 18.4+ WebKit runtime integration.

## Non-goals and explicit limits

- No merge of upstream Chromium `main` or another Aloha branch. The checkout is clean at `abr-150.0.7871.46`, and its `HEAD` exactly matches the public Aloha branch head. Revisit upstreaming only against a newer Aloha release branch when one exists.
- No claim that every Chrome or Firefox extension works. The WebKit runtime implements a supported subset; import success is not proof of runtime/API parity. Compatibility reporting must distinguish parser acceptance from actual behavior.
- No raw `.crx` pass-through. Apple's documented initializer accepts a directory with a root `manifest.json` or a ZIP archive with a root `manifest.json`.
- No CRX2 support in the initial importer. This branch's `components/crx_file::Verify` accepts CRX3 and rejects CRX2. CRX3 signature verification proves package integrity and key/ID consistency; with no independently trusted publisher key it does not establish publisher identity.
- No silent permission grants, arbitrary remote-code fetching, auto-update network service, or userscript execution in private browsing in the first implementation.
- No Xcode build or runtime success claim from this Linux sandbox. A genuine iOS 18.4+ test of Apple's initializer is a required verification step before calling XPI/CRX WebExtension import verified.

## Approaches considered

1. **Userscript-only via existing WebKit user-script injection.** Lowest implementation risk and can retain iOS 18.0 support, but does not address Chrome/Firefox WebExtension packages or `.crx` imports.
2. **Apple WebKit WebExtension runtime only.** Uses platform support for ZIP/directory packages on iOS 18.4+, but does not supply the native userscript manager requested and would leave iOS 18.0–18.3 without the main feature.
3. **Two layers (selected).** Implement the native userscript manager on the existing `JavaScriptFeature` path for iOS 18.0+, then host compatible WebExtensions in Apple's runtime on iOS 18.4+. This preserves the existing WebView architecture and keeps the OS-specific functionality isolated behind availability checks.

## Chosen architecture

### Userscript manager (first)

Add a small feature area under `ios/chrome/browser/userscripts/` with a profile-keyed service, focused storage/parser/matcher components, and a Settings UI. Register the service's non-syncable profile preference(s) during normal profile-pref registration; keep script source and metadata profile-scoped and do not store them in Local State or global `NSUserDefaults`. Use the established profile directory where source files are needed. The service owns stable `JavaScriptFeature` objects and notifies the associated WebKit configuration provider when the active script set changes.

Integrate through `ChromeWebClient::GetJavaScriptFeatures(browser_state)` and the browser-state `WKWebViewConfigurationProvider`. New or subsequently navigated documents receive the current enabled-script set. Existing document execution is not retroactively changed; disabling a script does not undo page-side effects. Do not force-reload tabs automatically. Execute in the page content world when userscripts need page globals/DOM access, and apply URL/match checks before evaluating each script. Use explicit frame and `@run-at` handling. OTR profiles are excluded unless an explicit future product decision changes that policy.

The compatibility goal is broad userscript support, not a blanket parity claim. The compatibility floor below is required and must be covered by fixtures; unsupported APIs/metadata are surfaced instead of silently ignored. The implementation plan will set concrete source/dependency size and permission limits after checking repository conventions.

#### Initial compatibility floor

The metadata parser must handle `@name`, `@namespace`, `@version`, `@description`, `@author`, `@match`, `@include`, `@exclude`, `@exclude-match`, `@run-at`, `@noframes`, `@grant`, `@connect`, `@require`, `@resource`, `@updateURL`, and `@downloadURL`. Matching covers eligible HTTP/HTTPS pages; browser-internal, extension, and file URLs are excluded unless separately approved and proven safe. Support document-start, document-end, and document-idle semantics, main-frame/all-frame policies, and `@noframes`.

The tested API floor must include `GM_info`, `unsafeWindow`, `GM_addStyle`, `GM_log`, modern `GM.getValue` / `setValue` / `deleteValue` / `listValues` plus compatible `GM_getValue` / `GM_setValue` / `GM_deleteValue` / `GM_listValues` forms, `GM.xmlHttpRequest` and `GM_xmlhttpRequest` (bounded by `@connect` and explicit user consent), `GM_openInTab`, `GM_registerMenuCommand` / `GM_unregisterMenuCommand`, `GM_setClipboard`, `GM_notification`, and `GM_getResourceText` / `GM_getResourceURL`. `@require` and `@resource` payloads are fetched and cached only during user-initiated installation or manual update, with bounds and visible failure; they are not fetched on every page load. `GM_registerMenuCommand` entries are surfaced for the active tab. Manual update checks use `@updateURL` / `@downloadURL`; unattended userscript updates are out of scope for the first implementation. Replacing a script that requests new grants or match hosts prompts again.

### WebExtension runtime (second)

Keep extension model/installer/controller adaptation separate from the userscript service. Gate all direct `WKWebExtension*` references and functionality at iOS 18.4. Attach one appropriately scoped `WKWebExtensionController` to the relevant `WKWebViewConfiguration` before WebViews are created. Map Chromium tab/window lifecycles to the WebKit extension controller's delegates only for behaviors the host can actually provide; unsupported features must be identified rather than stubbed as successful.

Present package installation, per-extension status, requested permissions, and WebKit errors in the same feature area. Grant only the user-selected permissions and match patterns, and honor expiration/denial. Keep the user's original package and staged resources in app-owned, profile-scoped storage; never retain a security-scoped document-picker URL as the installed resource URL.

### Lifecycle and privacy defaults (design decisions)

Neither userscripts nor WebExtensions run in off-the-record profiles by default, and extension state or grants are never shared with private browsing. The manager supports install, enable, disable, remove, and explicit manual replacement/re-import; automatic network updates are out of scope. Removal clears the extension's staged package and profile-scoped grant record.

Permission decisions are explicit and scoped to an extension and regular profile. A user-approved grant lasts until revoked unless WebKit supplies an expiration; persist the decision and expiration in the profile service, reapply it to the `WKWebExtensionContext` with `setPermissionStatus(_:for:expirationDate:)`, and expose a revoke control. A denial or an unanswered prompt remains denied. Do not rely on WebKit to persist app-level choices across relaunches. Use `WKWebExtensionContext.unsupportedAPIs` and `errors` for compatibility/error reporting where available; successful package parsing alone is not presented as full runtime support.

### Import and archive policy

- **CRX:** accept CRX3 only. First bound and verify the file using the existing `//components/crx_file:crx_file` verifier. Then parse the bounded CRX3 framing and copy only the ZIP payload into an app-owned staged `.zip`; run archive/path/resource checks and root-manifest preflight before calling Apple's initializer. Reject invalid signatures, malformed/oversized headers, CRX2, malformed ZIPs, path-traversal or duplicate normalized paths, unsafe/symlink entries, excessive file counts, and decompression/resource-limit violations. A valid CRX3 self-signature is not a trusted publisher badge.
- **XPI:** Mozilla documents XPI as a ZIP containing the extension files themselves, with `manifest.json` at the archive root. Copy the selected XPI into app-owned storage; if Apple's archive loader needs a `.zip` URL suffix, rename/copy without changing archive bytes. Preflight as ZIP, then pass the staged ZIP URL to Apple's `WKWebExtension(resourceBaseURL:)` initializer. Do not assume all Firefox-specific manifest keys/APIs are implemented by WebKit.
- **Apple-runtime verification gate:** add an iOS 18.4+ test that calls Apple's actual `WKWebExtension(resourceBaseURL:)` initializer with a minimal root-manifest ZIP, a real XPI-format fixture, and the ZIP payload extracted from a valid CRX3 fixture. The test must confirm accepted package shape and capture initializer errors for invalid/missing-root-manifest inputs. This sandbox cannot run that test; until a macOS/Xcode 18.4+ simulator/device run passes, report XPI/package-loader behavior as documented and test-pending, not runtime-verified.

## Existing seams to preserve

- JavaScript feature aggregation: `ios/chrome/browser/web/model/chrome_web_client.{h,mm}`.
- Per-`BrowserState` WebKit configuration and script updates: `ios/web/web_state/ui/wk_web_view_configuration_provider.{h,mm}`; WebView construction: `ios/web/web_state/ui/crw_web_controller.mm`.
- Profile preferences and factories: `ProfileIOS` / `ProfileKeyedServiceFactoryIOS`, with registration in the established profile-pref path.
- Settings root insertion and navigation: `ios/chrome/browser/settings/ui_bundled/settings_table_view_controller.mm` and its existing settings UI/build targets.
- Direct toolbar route: overflow-menu `Destination` patterns in `ios/chrome/browser/popup_menu/overflow_menu/`; append metric enum values without renumbering existing entries.
- File picker pattern: `UIDocumentPickerViewController` with security-scoped URL access, followed by immediate staging in app-owned storage.
- Existing CRX verifier: `components/crx_file/crx_verifier.{h,cc}` and the existing CRX3 fixtures/tests. The verifier verifies but does not extract the ZIP payload.
- Existing ZIP reader: `third_party/zlib/google:zip`, after checking safe paths/links and size/resource bounds.

## Verification and honesty contract

- First, write/run platform-independent tests for parsing, matching, metadata, storage, permission mapping, and archive validation where this environment allows.
- Add native iOS unit tests for JavaScript configuration updates, profile/OTR separation, settings/toolbar routing, WebExtension controller wiring, and permission decisions.
- Add an iOS 18.4+ runtime test using Apple's actual initializer as described above. Record its result separately from parser/unit tests.
- Run `git diff --check` and source/dependency boundary checks available in this environment. Do not report an iOS build, XCTest, or Apple-runtime test as passed unless actually run on macOS/Xcode.
- Final reporting must separate: **implemented**, **verified here**, **requires Xcode/iOS 18.4 validation**, **not implemented/unsupported**.

## Verified research references

- Apple, [`WKWebExtension.init(resourceBaseURL:)`](https://developer.apple.com/documentation/webkit/wkwebextension/init(resourcebaseurl:)): iOS/iPadOS 18.4+; accepts a file URL to a directory with root `manifest.json` or a ZIP archive containing root `manifest.json`.
- Apple, [`WKWebViewConfiguration.webExtensionController`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller): associates a WebExtension controller with a WebView configuration; iOS/iPadOS 18.4+.
- Apple, [`WKWebExtensionContext`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext) and [`WKWebExtensionControllerDelegate`](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate): extension context and permission/controller integration points; iOS/iPadOS 18.4+.
- Apple, [`WKWebExtensionContext.setPermissionStatus`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/setpermissionstatus%28_%3Afor%3Aexpirationdate%3A%29-692ui) and [`unsupportedAPIs`](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/unsupportedapis): app-controlled permission status/expiration and unsupported-API reporting; a `nil` expiration is treated as a distant-future date.
- Chromium, [`components/crx_file/crx3.proto`](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/crx_file/crx3.proto) and [`crx_verifier.cc`](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/crx_file/crx_verifier.cc): CRX3 framing and signature verification behavior.
- Mozilla, [Package your extension](https://extensionworkshop.com/documentation/publish/package-your-extension/): XPI is a ZIP package; extension files (not only the containing folder) must be at the archive root.
- Repository branch evidence: local `HEAD` `d0c38ae81ddc5eb07b48675215c2c859782c8a29` equals `AlohaBrowser/aloha-core` branch `abr-150.0.7871.46`; the checkout is clean. Linux sandbox has no `xcodebuild`, `gn`, or `autoninja`.
