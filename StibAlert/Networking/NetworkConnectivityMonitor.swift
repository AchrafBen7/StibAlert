import Foundation
import Network
import Combine

class NetworkConnectivityMonitor: NSObject, ObservableObject {
    @Published var isConnected = true
    @Published var isExpensive = false
    @Published var isConstrained = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.stibalert.networkmonitor")

    override init() {
        super.init()
        setupMonitoring()
    }

    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }

    var statusMessage: String {
        guard !isConnected else {
            if isConstrained {
                return "Connexion limitée"
            }
            return nil
        }
        return "Hors ligne"
    }

    deinit {
        monitor.cancel()
    }
}
