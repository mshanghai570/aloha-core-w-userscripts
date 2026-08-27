Contains code to build an Objective-C framework which renders web content with
`[CWVWebView]`. See the exposed API in `//ios/web_view/public/*` for more
details.

NOTE: This code is not used by Chrome for iOS (`//ios/chrome`), but is rather
a separate product/embedder of the `//ios/web` rendering layer.

[CWVWebView]: public/cwv_web_view.h

## Userscripts

`CWVWebViewConfiguration` exposes a configuration-scoped `userscriptManager`.
On initialization, it creates and loads the `Userscripts` directory beneath the
configuration's BrowserState directory. Add UTF-8 `.js` files to that directory
and call `reloadUserscriptsWithError:` after creating, replacing, or removing a
file.

The initial implementation supports standard `// ==UserScript==` metadata for
`@name`, `@match`, `@include`, `@exclude`, `@run-at`, and `@noframes`.
Scripts without an include or match rule are intentionally ignored. The
supported injection points are `document-start`, `document-end`, and
`document-idle`; idle scripts are scheduled from the document-end injection
point and run after the page's `load` event.

This is deliberately a local-script MVP. Greasemonkey/Tampermonkey privileged
APIs (`@grant`), remote dependencies (`@require`), resources, automatic
updates, and a script-management user interface remain future work.

### Installation and management

The manager exposes a product-facing workflow for local script files. Call
`previewUserscriptAtURL:error:` to validate a candidate `.js` file and read its
metadata. The embedder should display the name, timing, and URL rules and obtain
explicit confirmation before calling `installUserscriptAtURL:error:`. Installation
copies the script atomically into the manager directory, enables it by default,
and records the state in `EnabledUserscripts.plist` alongside the scripts.

Use `setUserscriptEnabled:forIdentifier:error:` and
`removeUserscriptWithIdentifier:error:` for ordinary management operations. Each
operation updates the content scripts; embedders should recreate existing web
views when their WebKit configuration needs to pick up revised page scripts.

The `ios_web_view_shell` target now includes a reference management interface in
its **User Scripts** menu. It provides a Files-based install flow, a clear
metadata/URL-rule confirmation screen, broad-access warnings, enabled/disabled
status, reload, and delete confirmation. This shell UI is intended as the
embedder integration example for Aloha's app layer.
