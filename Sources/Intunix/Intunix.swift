#if os(iOS)
import Foundation
import UIKit
import IntunixCore

/// Options for ``Intunix/initialize(apiKey:options:)``. Names follow the web SDK.
public struct IntunixOptions {
    /// API origin. Leave as is unless Intunix gave you another host.
    public var apiHost: String
    /// Forms (ids or slugs) whose triggers should be live. Forms flagged auto-activate are live anyway.
    public var register: [String]
    /// Load the whole SDK-enabled catalog instead of only `register`.
    public var registerAll: Bool
    /// How often buffered events upload, in milliseconds.
    public var flushIntervalMs: UInt64
    public var maxQueueSize: Int
    /// Wait before a screen-triggered form shows, in milliseconds.
    public var screenTriggerDelayMs: UInt64
    /// Keep tracked events on the device (they still fire event triggers).
    public var disableEventApi: Bool
    /// Print SDK logs to the console.
    public var debug: Bool

    public init(apiHost: String = "https://api.intunix.com", register: [String] = [], registerAll: Bool = false,
                flushIntervalMs: UInt64 = 5000, maxQueueSize: Int = 100, screenTriggerDelayMs: UInt64 = 600,
                disableEventApi: Bool = false, debug: Bool = false) {
        self.apiHost = apiHost; self.register = register; self.registerAll = registerAll; self.flushIntervalMs = flushIntervalMs
        self.maxQueueSize = maxQueueSize; self.screenTriggerDelayMs = screenTriggerDelayMs
        self.disableEventApi = disableEventApi; self.debug = debug
    }
}

/// Intunix feedback forms for iOS. Call ``initialize(apiKey:options:)`` once at launch.
/// Every call is safe from any thread.
public enum Intunix {
    public static let version = "1.5.1"

    @MainActor static var client: IntunixClient?
    @MainActor private static var presenter: OverlayPresenter?

    public static func initialize(apiKey: String, options: IntunixOptions = IntunixOptions()) {
        main {
            guard client == nil else { return }
            let p = OverlayPresenter()
            presenter = p
            let cfg = ClientConfig(apiKey: apiKey, apiHost: options.apiHost.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                                   registerAll: options.registerAll, register: options.register,
                                   flushIntervalMs: options.flushIntervalMs, maxQueueSize: options.maxQueueSize,
                                   screenTriggerDelayMs: options.screenTriggerDelayMs, disableEventApi: options.disableEventApi,
                                   sdkVersion: version)
            let debug = options.debug
            let c = IntunixClient(cfg: cfg, store: DefaultsStore(), presenter: p) { if debug { print("[Intunix] \($0)") } }
            client = c
            let nc = NotificationCenter.default
            nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { client?.onForeground() }
            }
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { client?.onBackground() }
            }
            c.start()
        }
    }

    /// Identify the signed-in user. Call on every login.
    public static func identify(_ userId: String, traits: [String: Any] = [:]) { main { client?.identify(userId, traits) } }

    /// Call on logout: forgets the user, rotates the anonymous id and ends the session.
    public static func reset() { main { client?.reset() } }

    public static func track(_ event: String, properties: [String: Any] = [:]) { main { client?.track(event, properties) } }

    /// Tell Intunix which screen is showing. Drives "App screen" triggers and screen targeting.
    public static func screen(_ name: String) { main { client?.screen(name) } }

    /// Merge values into the session context sent with responses; nil clears it.
    public static func setContext(_ context: [String: Any]?) { main { client?.setContext(context) } }

    public static func clearContext() { main { client?.setContext(nil) } }

    /// Show a form now (still subject to its cadence and targeting). Accepts the form id or slug.
    public static func showForm(_ idOrSlug: String, context: [String: Any]? = nil) { main { client?.showForm(idOrSlug, context: context) } }

    /// Make a form's triggers live.
    public static func register(_ idOrSlug: String) { main { client?.register(idOrSlug) } }

    public static func unregister(_ idOrSlug: String) { main { client?.unregister(idOrSlug) } }

    private static func main(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(block) }
        else { DispatchQueue.main.async { MainActor.assumeIsolated(block) } }
    }
}

#endif
