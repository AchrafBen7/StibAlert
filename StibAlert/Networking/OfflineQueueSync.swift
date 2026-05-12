import Foundation
import Combine

/// Watches `NetworkConnectivityMonitor` and flushes queued offline reports
/// whenever connectivity returns. Lives at the app root level so it runs
/// regardless of which screen is on top.
@MainActor
final class OfflineQueueSync: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastSyncedAt: Date? = nil
    @Published private(set) var isSyncing: Bool = false

    private var observers = Set<AnyCancellable>()
    private weak var monitor: NetworkConnectivityMonitor?

    init() {
        refreshPendingCount()
    }

    func bind(to monitor: NetworkConnectivityMonitor) {
        guard self.monitor !== monitor else { return }
        self.monitor = monitor

        monitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                if connected {
                    Task { @MainActor [weak self] in
                        await self?.sync()
                    }
                }
            }
            .store(in: &observers)
    }

    func refreshPendingCount() {
        pendingCount = OfflineCache.loadQueuedReports().count
    }

    func sync() async {
        guard !isSyncing else { return }
        let queued = OfflineCache.loadQueuedReports()
        guard !queued.isEmpty else {
            pendingCount = 0
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            refreshPendingCount()
            lastSyncedAt = Date()
        }

        for report in queued {
            do {
                _ = try await SignalementService.ajouter(
                    nomArret: report.nomArret,
                    ligne: report.ligne,
                    typeProbleme: report.typeProbleme,
                    description: report.description,
                    latitude: report.latitude,
                    longitude: report.longitude,
                    photo: nil
                )
                OfflineCache.removeQueuedReport(id: report.id)
            } catch {
                // Stop the loop on first error — likely still offline / server down.
                // The remaining items will be retried on next reconnect.
                break
            }
        }
    }
}
