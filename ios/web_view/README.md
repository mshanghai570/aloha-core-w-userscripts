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
