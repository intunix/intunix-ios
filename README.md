# Intunix for iOS

Show [Intunix](https://intunix.com) feedback forms in your iOS app. Forms look and behave the
same as on the web (the Intunix web SDK 1.5) and on Android: the same questions, question pages,
conditional questions, icon styles, cadence, targeting and review requests.

- Swift, SwiftUI, iOS 15+
- No third-party dependencies

## Install

Swift Package Manager: in Xcode choose **File › Add Package Dependencies…** and enter

```
https://github.com/intunix/intunix-ios
```

or in `Package.swift`:

```swift
.package(url: "https://github.com/intunix/intunix-ios", from: "1.5.1")
```

## Set up

Call `initialize` once at launch:

```swift
import Intunix

@main
struct MyApp: App {
    init() {
        Intunix.initialize(apiKey: "ck_your_client_key", options: IntunixOptions(registerAll: true))
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

| Option | Default | What it does |
|---|---|---|
| `register` | `[]` | Form ids or slugs whose triggers are live |
| `registerAll` | `false` | Load every SDK-enabled form instead of only `register` |
| `screenTriggerDelayMs` | `600` | Wait before a screen-triggered form shows |
| `flushIntervalMs` | `5000` | How often events upload |
| `disableEventApi` | `false` | Keep events on the device (they still fire triggers) |
| `debug` | `false` | Print SDK logs |
| `apiHost` | `https://api.intunix.com` | API origin |

Forms marked auto-activate in the Intunix console are live without registering.

## API

```swift
Intunix.identify("user-42", traits: ["plan": "pro"])   // on every login
Intunix.reset()                                        // on logout
Intunix.track("checkout_completed", properties: ["total": 49.0])
Intunix.screen("Checkout")                             // drives "App screen" triggers
Intunix.setContext(["store": "dhaka-1"])               // sent with responses; nil clears
Intunix.showForm("nps-q4")                             // id or slug; still respects cadence
Intunix.register("nps-q4"); Intunix.unregister("nps-q4")
```

Every call is safe from any thread.

### Where forms appear

| Form type in the console | On iOS |
|---|---|
| Modal | Centered dialog |
| Popup, banner | Bottom sheet |
| Inline | Wherever you place `IntunixForm` |

```swift
IntunixForm(form: "post-order")
    .padding()
```

Only one form shows at a time; others wait their turn. A form waits for the app to be active.

### Triggers

Event (`track`), app screen (`screen`, matching exact / contains / regex), user trait
(`identify`), time after the form goes live, and manual (`showForm`). Web-only triggers (page URL,
exit intent) are ignored. A form set to show on **Web** only never shows in apps.

## What is sent

The same endpoints as the web SDK, with channel `mobile_sdk` and the header
`x-intunix-sdk: ios/<version>`. Events that fail to upload are kept on the device and retried
for a day. A session ends after 30 minutes in the background.

## Develop

```bash
swift test --filter IntunixCoreTests     # logic tests (ported from @intunix/core); runs on Linux too
cd Example && xcodegen generate          # sample app (set apiKey and formSlug in SampleApp.swift)
```

CI renders every question type on the iOS simulator and pushes the images to the
`snapshots` branch.
