//
//  DraggableSheetView.swift
//  StibAlert
//
//  Created by studentehb on 23/05/2025.
//

import SwiftUI

struct DraggableSheetView: View {
    let signalements: [ArretSignalementItem]
    let typeTransport: String?
    
    @GestureState private var dragOffset = CGSize.zero
    @State private var currentOffset: CGFloat = UIScreen.main.bounds.height * 0.5
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            signalements
                                .filter { isRecent($0.date) }
                                .sorted(by: { parseDate($0.date) ?? Date.distantPast > parseDate($1.date) ?? Date.distantPast })
                        ) { melding in
                            SignalementStyledCard(melding: melding, typeTransport: typeTransport)
                            Divider()
                        }
                        Spacer().frame(height: 40)
                    }
                }
                
                .padding(.top, 8)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background(Color(.systemBackground))
            .cornerRadius(24)
            .offset(y: currentOffset + dragOffset.height)
            .animation(.easeInOut, value: currentOffset)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let height = geo.size.height
                        let newOffset = currentOffset + value.translation.height
                        
                        if newOffset < height * 0.3 {
                            currentOffset = 0  // full open
                        } else if newOffset > height * 0.7 {
                            currentOffset = height * 0.8  // collapsed
                        } else {
                            currentOffset = height * 0.5 // mid
                        }
                    }
            )
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

func isRecent(_ dateString: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    guard let date = formatter.date(from: dateString) else { return false }
    return Date().timeIntervalSince(date) <= 24 * 60 * 60
}

func parseDate(_ isoString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: isoString)
}
