import Foundation
import SocketIO

@MainActor
final class SignalementsRealtimeService: ObservableObject {
    @Published private(set) var latestSignalement: SignalementDTO?
    @Published private(set) var latestClusterEvent: ClusterEventPayload?
    @Published private(set) var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let decoder = JSONDecoder()

    func connect() {
        guard AppConfig.isBackendEnabled else { return }
        guard socket == nil, let url = URL(string: AppConfig.backendBaseURL) else { return }

        let manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(3)
            ]
        )

        let socket = manager.defaultSocket
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = true
            }
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        socket.on(clientEvent: .error) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        socket.on("nouveauSignalementGlobal") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleIncomingSignalement(data)
            }
        }
        socket.on("nouveauSignalement") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleIncomingSignalement(data)
            }
        }
        socket.on("clusterEvent") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleClusterEvent(data)
            }
        }
        socket.on("clusterEventArret") { [weak self] data, _ in
            Task { @MainActor in
                self?.handleClusterEvent(data)
            }
        }

        self.manager = manager
        self.socket = socket
        socket.connect()
    }

    func subscribeToStop(_ arretId: String) {
        socket?.emit("souscrireArret", arretId)
    }

    private func handleClusterEvent(_ data: [Any]) {
        guard let first = data.first,
              JSONSerialization.isValidJSONObject(first),
              let jsonData = try? JSONSerialization.data(withJSONObject: first) else {
            return
        }
        if let payload = try? decoder.decode(ClusterEventPayload.self, from: jsonData) {
            latestClusterEvent = payload
        }
    }

    func disconnect() {
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        manager = nil
        isConnected = false
    }

    private func handleIncomingSignalement(_ data: [Any]) {
        guard let first = data.first else { return }

        if let dto = decodeSignalement(from: first) {
            latestSignalement = dto
        }
    }

    private func decodeSignalement(from raw: Any) -> SignalementDTO? {
        guard JSONSerialization.isValidJSONObject(raw),
              let jsonData = try? JSONSerialization.data(withJSONObject: raw) else {
            return nil
        }

        return try? decoder.decode(SignalementDTO.self, from: jsonData)
    }
}

struct ClusterEventPayload: Decodable, Identifiable {
    let event: String
    let clusterIndex: Int
    let ligne: String
    let arretId: String?
    let typeProbleme: String
    let reportCount: Int
    let confidence: String
    let status: String
    let resolved: Bool
    let stillBlockedConfirmationCount: Int
    let resolveConfirmationCount: Int
    let expiresAt: Date?
    let latitude: Double?
    let longitude: Double?
    let emittedAt: Date

    var id: String { "\(clusterIndex)-\(emittedAt.timeIntervalSince1970)" }

    var isPublished: Bool { event == "published" }
    var isResolved: Bool { event == "resolved" }
    var isStillBlockedVote: Bool { event == "still_blocked" }
}
