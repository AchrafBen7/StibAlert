import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case network(Error)
    case decoding(Error)
    case server(status: Int, message: String?)
    case unauthorized
    case backendDisabled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return AppLocalizer.string("error.invalid_url", defaultValue: "URL invalide.")
        case .network(let e): return Self.networkMessage(for: e)
        case .decoding:
            return AppLocalizer.string("error.decoding",
                                       defaultValue: "La réponse du serveur est temporairement incompatible. Réessaie dans quelques secondes.")
        // `msg` vient du backend : il arrive déjà dans une langue, on ne le traduit pas.
        case .server(let status, let msg): return msg ?? Self.serverMessage(for: status)
        case .unauthorized:
            return AppLocalizer.string("error.unauthorized", defaultValue: "Session expirée, reconnecte-toi.")
        case .backendDisabled:
            return AppLocalizer.string("error.backend_disabled", defaultValue: "Fonctionnalités en ligne désactivées.")
        }
    }

    private static func networkMessage(for error: Error) -> String {
        let unstable = AppLocalizer.string("error.network.unstable",
                                           defaultValue: "Connexion instable. Vérifie ton réseau puis réessaie.")
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return unstable }

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return AppLocalizer.string("error.network.offline",
                                       defaultValue: "Aucune connexion internet. Les données affichées peuvent être anciennes.")
        case NSURLErrorTimedOut:
            return AppLocalizer.string("error.network.timeout",
                                       defaultValue: "Le serveur met trop de temps à répondre. Réessaie dans quelques secondes.")
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return AppLocalizer.string("error.service_unavailable",
                                       defaultValue: "Service momentanément indisponible. Réessaie un peu plus tard.")
        default:
            return unstable
        }
    }

    private static func serverMessage(for status: Int) -> String {
        switch status {
        case 400..<500:
            return AppLocalizer.string("error.bad_request",
                                       defaultValue: "La demande n’a pas pu être traitée. Réessaie ou modifie ta recherche.")
        case 500..<600:
            return AppLocalizer.string("error.service_unavailable",
                                       defaultValue: "Service momentanément indisponible. Réessaie un peu plus tard.")
        default:
            return AppLocalizer.string("error.server_temporary", defaultValue: "Erreur serveur temporaire.")
        }
    }
}

extension Notification.Name {
    static let sessionExpired = Notification.Name("com.stibalert.sessionExpired")
}

struct ServerError: Decodable {
    let message: String?
}

enum HTTPMethod: String {
    case GET, POST, PATCH, DELETE
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            // Try String first (ISO8601, RFC3339, etc.)
            if let s = try? container.decode(String.self) {
                // Try standard ISO8601 with fractional seconds
                let iso8601Full = ISO8601DateFormatter()
                iso8601Full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso8601Full.date(from: s) { return date }

                // Try ISO8601 without fractional seconds
                let iso8601 = ISO8601DateFormatter()
                iso8601.formatOptions = [.withInternetDateTime]
                if let date = iso8601.date(from: s) { return date }

                // Heure locale SANS fuseau ("2024-09-02T00:00:00"), telle que
                // De Lijn date ses déviations. Ce n'est pas de l'ISO complet,
                // donc les deux formateurs ci-dessus la refusent — et comme
                // JSONDecoder abandonne tout le document à la première erreur,
                // une seule de ces dates faisait échouer /transport/overview
                // en entier (bandeau réseau de l'accueil + résumé signalements).
                // On l'interprète à Bruxelles, ce qu'elle veut dire.
                if let date = APIClient.naiveDateFormatter.date(from: s) { return date }
                if let date = APIClient.naiveDayFormatter.date(from: s) { return date }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unable to decode date string: \(s)"
                )
            }

            // Try Number (Unix timestamp in seconds or milliseconds)
            // Google Directions: departure_time.value is in seconds
            // JavaScript Date.getTime(): milliseconds since 1970
            // Heuristic: > 10^12 means milliseconds, < 10^12 means seconds
            if let n = try? container.decode(Double.self) {
                // Reject obviously invalid timestamps (before 1970 or after year 2100)
                let isMilliseconds = n > 1_000_000_000_000
                let interval = isMilliseconds ? n / 1000 : n

                // Sanity check: reject timestamps outside reasonable range
                let minValid: TimeInterval = -62_167_219_200 // Year 0
                let maxValid: TimeInterval = 4_102_444_800   // Year 2100

                guard (minValid...maxValid).contains(interval) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Timestamp out of valid range: \(n)"
                    )
                }

                return Date(timeIntervalSince1970: interval)
            }

            // Try Integer (some APIs return Unix seconds as Int)
            if let n = try? container.decode(Int.self) {
                return Date(timeIntervalSince1970: TimeInterval(n))
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Date value is not a string, double, or integer"
            )
        }
        return d
    }()
    private let encoder = JSONEncoder()

    /// Heure locale bruxelloise sans fuseau, telle que De Lijn publie ses
    /// périodes de déviation. `DateFormatter` est thread-safe en lecture seule,
    /// et on ne fait que `date(from:)`.
    fileprivate static let naiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Brussels")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Même chose pour une date seule ("2024-09-02"), calée à minuit.
    fileprivate static let naiveDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Brussels")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// - Parameter timeout: dépassement propre à CETTE requête. Le défaut de la
    ///   session (8 s) convient aux appels simples, mais pas au calcul
    ///   d'itinéraire : côté serveur il agrège Transitous + ORS + les API STIB,
    ///   et l'instance peut sortir de veille. Au-delà de 8 s l'appel echouait,
    ///   l'app retombait sur Apple Plans (qui ne sait ni le vélo ni le transit
    ///   bruxellois) et annonçait « aucun itinéraire en transport en commun » —
    ///   un mensonge, pour une app de transport en commun.
    func request<Response: Decodable>(
        _ path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = false,
        timeout: TimeInterval? = nil,
        as: Response.Type = Response.self
    ) async throws -> Response {
        guard AppConfig.isBackendEnabled else { throw APIError.backendDisabled }
        guard let url = URL(string: AppConfig.backendBaseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(KeychainHelper.anonymousDeviceId(), forHTTPHeaderField: "x-stib-device-id")

        let accessToken = requiresAuth ? KeychainHelper.readToken() : nil
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: nil)
        }

        if http.statusCode == 401 {
            if requiresAuth, accessToken != nil, let newToken = await attemptTokenRefresh() {
                var retryReq = req
                retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                guard let (retryData, retryResponse) = try? await session.data(for: retryReq),
                      let retryHttp = retryResponse as? HTTPURLResponse else {
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    throw APIError.unauthorized
                }
                if retryHttp.statusCode == 401 {
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    throw APIError.unauthorized
                }
                guard (200..<300).contains(retryHttp.statusCode) else {
                    let msg = (try? decoder.decode(ServerError.self, from: retryData))?.message
                    throw APIError.server(status: retryHttp.statusCode, message: msg)
                }
                if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
                do { return try decoder.decode(Response.self, from: retryData) } catch { throw APIError.decoding(error) }
            }
            if requiresAuth, accessToken != nil {
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            }
            let msg = (try? decoder.decode(ServerError.self, from: data))?.message
            throw APIError.server(status: http.statusCode, message: msg)
        }

        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(ServerError.self, from: data))?.message
            throw APIError.server(status: http.statusCode, message: msg)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<binary>"
            print("⚠️ Decode failure for \(Response.self): \(error)\nJSON preview: \(preview)")
            #endif
            ErrorReporting.capture(error, tag: "api.decode", context: ["type": String(describing: Response.self)])
            throw APIError.decoding(error)
        }
    }

    // Direct call — bypasses retry logic to avoid recursion
    private func attemptTokenRefresh() async -> String? {
        guard let rawRefresh = KeychainHelper.readRefreshToken() else { return nil }
        guard let url = URL(string: AppConfig.backendBaseURL + "/api/utilisateurs/refresh") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? encoder.encode(AnyEncodable(RefreshTokenRequest(refreshToken: rawRefresh)))
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let refreshed = try? decoder.decode(RefreshTokenResponse.self, from: data) else {
            KeychainHelper.deleteRefreshToken()
            return nil
        }
        KeychainHelper.saveToken(refreshed.token)
        KeychainHelper.saveRefreshToken(refreshed.refreshToken)
        return refreshed.token
    }

    func upload<Response: Decodable>(
        _ path: String,
        fields: [String: String],
        imageData: Data?,
        imageField: String = "photo",
        requiresAuth: Bool = true
    ) async throws -> Response {
        guard AppConfig.isBackendEnabled else { throw APIError.backendDisabled }
        guard let url = URL(string: AppConfig.backendBaseURL + path) else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(KeychainHelper.anonymousDeviceId(), forHTTPHeaderField: "x-stib-device-id")
        let accessToken = requiresAuth ? KeychainHelper.readToken() : nil
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        if let imageData {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(imageField)\"; filename=\"photo.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: nil)
        }
        if http.statusCode == 401 {
            if requiresAuth, accessToken != nil, let newToken = await attemptTokenRefresh() {
                var retryReq = req
                retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                guard let (retryData, retryResponse) = try? await session.data(for: retryReq),
                      let retryHttp = retryResponse as? HTTPURLResponse,
                      (200..<300).contains(retryHttp.statusCode) else {
                    NotificationCenter.default.post(name: .sessionExpired, object: nil)
                    throw APIError.unauthorized
                }
                return try decoder.decode(Response.self, from: retryData)
            }
            if requiresAuth, accessToken != nil {
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            }
            let msg = (try? decoder.decode(ServerError.self, from: data))?.message
            throw APIError.server(status: http.statusCode, message: msg)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode(ServerError.self, from: data))?.message
            throw APIError.server(status: http.statusCode, message: msg)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

private extension Data {
    mutating func append(_ s: String) { if let d = s.data(using: .utf8) { append(d) } }
}
