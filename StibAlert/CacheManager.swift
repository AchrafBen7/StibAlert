//
//  CacheManager.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.
//


import Foundation

struct CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let cacheLifetime: TimeInterval = 24 * 60 * 60 // 24 heures en secondes
    
    private init() {}
    
    // Enregistrer un fichier cache
    func save(data: Data, filename: String) {
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        do {
            try data.write(to: url)
            UserDefaults.standard.set(Date(), forKey: "cache_\(filename)_date")
            print("[CACHE] ✅ Fichier '\(filename)' sauvegardé.")
        } catch {
            print("[CACHE] ❌ Erreur sauvegarde '\(filename)': \(error)")
        }
    }
    
    // Charger un fichier cache
    func load(filename: String) -> Data? {
        let url = getDocumentsDirectory().appendingPathComponent(filename)
        
        guard fileManager.fileExists(atPath: url.path) else {
            print("[CACHE] 🚫 Pas de fichier '\(filename)' trouvé.")
            return nil
        }
        
        // Vérifier si le cache est expiré
        if let savedDate = UserDefaults.standard.object(forKey: "cache_\(filename)_date") as? Date {
            let age = Date().timeIntervalSince(savedDate)
            if age > cacheLifetime {
                print("[CACHE] ⏰ Cache '\(filename)' expiré. Suppression...")
                try? fileManager.removeItem(at: url)
                UserDefaults.standard.removeObject(forKey: "cache_\(filename)_date")
                return nil
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            print("[CACHE] 📂 Chargement du cache '\(filename)' réussi.")
            return data
        } catch {
            print("[CACHE] ❌ Erreur chargement '\(filename)': \(error)")
            return nil
        }
    }
    
    // Fonction pour tout nettoyer si besoin (optionnel)
    func clearAllCache() {
        let documentsURL = getDocumentsDirectory()
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            for url in fileURLs {
                try fileManager.removeItem(at: url)
            }
            print("[CACHE] 🧹 Tous les fichiers cache supprimés.")
        } catch {
            print("[CACHE] ❌ Erreur nettoyage cache : \(error)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
