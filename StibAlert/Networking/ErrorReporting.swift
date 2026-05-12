import Foundation

/// Production crash + error reporting wrapper.
///
/// Today: prints to console + logs to UserDefaults (last 50 events for support).
/// Plug-in point ready for Sentry / Crashlytics / Bugsnag — add the SDK call
/// in `capture(_:)` and `setUser(_:)` once the team picks one.
///
/// To enable Sentry later:
///   1. `swift package add github.com/getsentry/sentry-cocoa`
///   2. In `StibAlertApp.init()`:
///        SentrySDK.start { o in
///          o.dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"]
///          o.tracesSampleRate = 0.1
///        }
///   3. Uncomment the Sentry block in this file.
enum ErrorReporting {
    private static let recentEventsKey = "errorReporting.recent.v1"
    private static let maxRecent = 50

    static func setUp() {
        NSSetUncaughtExceptionHandler { exception in
            ErrorReporting.capture(
                NSError(
                    domain: "StibAlert.UncaughtException",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: exception.reason ?? exception.name.rawValue,
                        "callStackSymbols": exception.callStackSymbols.joined(separator: "\n"),
                    ]
                ),
                tag: "uncaughtException",
                isFatal: true
            )
        }
    }

    static func capture(
        _ error: Error,
        tag: String = "generic",
        isFatal: Bool = false,
        context: [String: Any] = [:],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let nsErr = error as NSError
        let event: [String: Any] = [
            "tag": tag,
            "fatal": isFatal,
            "domain": nsErr.domain,
            "code": nsErr.code,
            "message": nsErr.localizedDescription,
            "file": String(describing: file).components(separatedBy: "/").last ?? "?",
            "line": line,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "context": context,
        ]

        #if DEBUG
        print("⚠️ ErrorReporting [\(tag)] \(nsErr.localizedDescription)")
        #endif

        persist(event)

        // Future:
        // SentrySDK.capture(error: error) { scope in
        //     scope.setTag(value: tag, key: "tag")
        //     for (k, v) in context { scope.setExtra(value: v, key: k) }
        // }
    }

    static func captureMessage(
        _ message: String,
        tag: String = "info",
        context: [String: Any] = [:]
    ) {
        let event: [String: Any] = [
            "tag": tag,
            "fatal": false,
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "context": context,
        ]
        #if DEBUG
        print("ℹ️ ErrorReporting [\(tag)] \(message)")
        #endif
        persist(event)
    }

    static func setUser(userId: String?, email: String? = nil) {
        // Future:
        // SentrySDK.setUser(SentryUser(id: userId ?? "anonymous"))
        UserDefaults.standard.set(userId, forKey: "errorReporting.userId")
        UserDefaults.standard.set(email, forKey: "errorReporting.userEmail")
    }

    static func recentEvents() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: recentEventsKey),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    private static func persist(_ event: [String: Any]) {
        var events = recentEvents()
        events.append(event)
        if events.count > maxRecent {
            events.removeFirst(events.count - maxRecent)
        }
        if let data = try? JSONSerialization.data(withJSONObject: events) {
            UserDefaults.standard.set(data, forKey: recentEventsKey)
        }
    }
}
