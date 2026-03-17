//
//  KeychainManager.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//
import Foundation
import Security

class KeychainManager {
    
    
    static func save(key: String, value: String) {
        let data = Data(value.utf8)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]

    
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    
    static func get(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status != errSecSuccess {
            print("[Keychain] ❌ Erreur lors de la récupération de \(key) - status: \(status)")
            return nil
        }

        if let data = result as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return nil
    }


    
    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
