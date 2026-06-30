import Foundation
#if canImport(Sentry)
import Sentry
#endif

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

    /// DSN Sentry (projet Apple). À remplacer par le vôtre :
    /// sentry.io > votre projet > Settings > Client Keys (DSN). Public par
    /// nature (embarqué dans l'app cliente, comme l'App ID analytics).
    private static let sentryDSN = "https://cc668d37461b5fbe77a3b62b150a6906@o4511654427361280.ingest.de.sentry.io/4511656442069072"

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

        // Sentry démarre APRÈS notre handler : son intégration crash sauvegarde
        // et chaîne le handler précédent (le nôtre), donc les deux fonctionnent
        // — Sentry envoie au cloud, le nôtre persiste en local pour le support.
        #if canImport(Sentry)
        if !sentryDSN.hasPrefix("REMPLACER") {
            SentrySDK.start { options in
                options.dsn = sentryDSN
                options.tracesSampleRate = 0.1
                #if DEBUG
                options.environment = "debug"
                #else
                options.environment = "production"
                #endif
            }
        }
        #endif
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

        #if canImport(Sentry)
        // Les crashes fatals sont déjà capturés par le handler natif de Sentry —
        // on n'envoie ici que les erreurs non-fatales capturées manuellement,
        // pour éviter le doublon.
        if !isFatal {
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: tag, key: "kind")
            }
        }
        #endif
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
        #if canImport(Sentry)
        SentrySDK.configureScope { scope in
            if let userId {
                let sentryUser = Sentry.User(userId: userId)
                sentryUser.email = email
                scope.setUser(sentryUser)
            } else {
                scope.setUser(nil)
            }
        }
        #endif
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
