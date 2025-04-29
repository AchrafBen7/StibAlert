//
//  NetworkMonitor.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.
//

import Network
import Foundation

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected: Bool = true

    private init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
func saveToCache(data: Data, filename: String) {
    let url = getDocumentsDirectory().appendingPathComponent(filename)
    do {
        try data.write(to: url)
        print("[DEBUG] ✅ Données sauvegardées dans : \(url)")
    } catch {
        print("[DEBUG] ❌ Erreur de sauvegarde du cache : \(error)")
    }
}

func loadFromCache(filename: String) -> Data? {
    let url = getDocumentsDirectory().appendingPathComponent(filename)
    return try? Data(contentsOf: url)
}

private func getDocumentsDirectory() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
}
