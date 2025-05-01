//
//  data.swift
//  StibAlert
//
//  Created by studentehb on 01/05/2025.
//
import SwiftUI

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
