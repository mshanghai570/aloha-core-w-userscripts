# Apple WKWebExtension API facts

Apple’s WebKit extension host is available on iOS/iPadOS 18.4 and later. `WKWebExtension` has an asynchronous throwing initializer using a file URL. Apple documents that this URL may point either to a directory containing `manifest.json` or to a ZIP archive containing `manifest.json`; invalid/missing manifests, unsupported formats, and invalid archives produce an error. This establishes ZIP support at the API-contract level, but does **not** establish whether an `.xpi` filename is accepted, whether a CRX3 payload is acceptable after extraction, or how Apple handles particular archive edge cases. Those remain Task 8 device/simulator probes.

A `WKWebExtensionController` manages loaded extension contexts. The application associates the controller with a `WKWebViewConfiguration` through its `webExtensionController` property. The association must be set on each applicable configuration before the `WKWebView` is constructed. The host application is also responsible for notifying the controller about tab/window lifecycle changes through its documented methods.

`WKWebExtensionControllerDelegate` is available from iOS 18.4 and includes callbacks for opening tabs/windows, listing/focusing windows, permission and host-access prompts, extension messaging, options pages, and action popups. Correct integration therefore needs explicit Chromium tab/window adapters and deny-by-default permission mediation; loading an extension alone is not a complete browser integration.

`WKWebExtensionContext` exposes current/granted/denied permission sets and host-pattern grants, plus `errors` and `unsupportedAPIs`. These are suitable for surfacing partial compatibility instead of claiming Chrome/Firefox API parity.

## References

- [1]: https://developer.apple.com/documentation/webkit/wkwebextension "WKWebExtension documentation"
- [2]: https://developer.apple.com/documentation/webkit/wkwebextension/init%28resourcebaseurl%3A%29 "WKWebExtension resourceBaseURL initializer"
- [3]: https://developer.apple.com/documentation/webkit/wkwebextensioncontroller "WKWebExtensionController documentation"
- [4]: https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller "WKWebViewConfiguration.webExtensionController documentation"
- [5]: https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate "WKWebExtensionControllerDelegate documentation"
- [6]: https://developer.apple.com/documentation/webkit/wkwebextensioncontext "WKWebExtensionContext documentation"
- [7]: https://webkit.org/blog/16574/webkit-features-in-safari-18-4/ "WebKit features in Safari 18.4"


The upstream Objective-C headers confirm the selectors used by the framework: `+[WKWebExtension extensionWithResourceBaseURL:completionHandler:]`, `-initForExtension:`, `-initWithConfiguration:`, and `-loadExtensionContext:error:`. WebKit marks the tab protocol methods optional, but its header specifically warns that returning no `WKWebView` can disable critical capabilities such as content injection. Chromium's own `WebViewPassKey` documentation strongly discourages raw `WKWebView` access except when passing the object to another WebKit API that explicitly requires it; this extension adapter is such a case, but access should remain narrowly scoped.

- [8]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtension.h "WebKit WKWebExtension Objective-C header"
- [9]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtensionContext.h "WebKit WKWebExtensionContext Objective-C header"
- [10]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtensionController.h "WebKit WKWebExtensionController Objective-C header"
- [11]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtensionControllerDelegate.h "WebKit WKWebExtensionControllerDelegate Objective-C header"
- [12]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtensionTab.h "WebKit WKWebExtensionTab Objective-C header"
- [13]: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtensionWindow.h "WebKit WKWebExtensionWindow Objective-C header"
