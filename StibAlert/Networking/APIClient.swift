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
        case .invalidURL: return "URL invalide."
        case .network(let e): return e.localizedDescription
        case .decoding: return "Réponse serveur illisible."
        case .server(_, let msg): return msg ?? "Erreur serveur."
        case .unauthorized: return "Session expirée, reconnectez-vous."
        case .backendDisabled: return "Fonctionnalités en ligne désactivées."
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

    private let session: URLSession = .shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let date = formatter.date(from: s) { return date }
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(s)")
        }
        return d
    }()
    private let encoder = JSONEncoder()

    func request<Response: Decodable>(
        _ path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = false,
        as: Response.Type = Response.self
    ) async throws -> Response {
        guard AppConfig.isBackendEnabled else { throw APIError.backendDisabled }
        guard let url = URL(string: AppConfig.backendBaseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

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

        let (data, response) = try await session.data(for: req)
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
