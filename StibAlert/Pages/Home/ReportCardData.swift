//
//  ReportCardData.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import Foundation
import SwiftUI


import SwiftUI

struct ReportMock: Identifiable {
    let id = UUID()
    let lineNumber: String
    let stopName: String
    let fromText: String
    let toText: String
    let lineColor: Color
    let isDone: Bool // true = report terminé => opacité réduite
}



