import SwiftUI

// MARK: - 3-level snap sheet heights

enum SheetLevel: Int, CaseIterable {
    case peek    // just handle visible
    case middle  // half open
    case full    // full screen

    func height(screen: CGFloat) -> CGFloat {
        switch self {
        case .peek:   return 110
        case .middle: return 340
        case .full:   return screen
        }
    }
}

// MARK: - Report sheet (overlaid on HomeView's map)

struct ReportSheetView: View {
    @Binding var isShowing: Bool

    @State private var level: SheetLevel = .full
    @GestureState private var liveOffset: CGFloat = 0
    @State private var selectedStop: UUID? = nil

    private let screen = UIScreen.main.bounds.height
    private let snapSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)

    // Leaves the status bar / dynamic island area uncovered
    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    private var fullHeight: CGFloat { screen - safeTop - 24 }

    @State private var baseHeight: CGFloat = 0

    private func heights() -> (peek: CGFloat, middle: CGFloat, full: CGFloat) {
        (110, 340, fullHeight)
    }

    private var displayHeight: CGFloat {
        let h = heights()
        return (baseHeight - liveOffset).clamped(to: h.peek...h.full)
    }

    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($liveOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let h = heights()
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let endH = (baseHeight - value.translation.height).clamped(to: h.peek...h.full)
                let snapped = snapToLevel(current: endH, velocity: velocity)
                withAnimation(snapSpring) { level = snapped }
                baseHeight = heightFor(snapped)

                if snapped == .peek && value.translation.height > 60 {
                    withAnimation(snapSpring) { isShowing = false }
                }
            }
    }

    private func heightFor(_ l: SheetLevel) -> CGFloat {
        switch l {
        case .peek:   return heights().peek
        case .middle: return heights().middle
        case .full:   return heights().full
        }
    }

    private func snapToLevel(current: CGFloat, velocity: CGFloat) -> SheetLevel {
        let levels = SheetLevel.allCases
        if velocity < -300 { return levels[min(level.rawValue + 1, levels.count - 1)] }
        if velocity > 300  { return levels[max(level.rawValue - 1, 0)] }
        return levels.min(by: { abs(heightFor($0) - current) < abs(heightFor($1) - current) }) ?? .middle
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle (white, always visible) ──────────────────
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 44, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    StepIndicatorRow(current: 1, total: 5)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    Text("Arrets a proximité")
                        .font(.custom("DelaGothicOne-Regular", size: 20))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)

                    Text("Signaler un arret")
                        .font(.custom("Montserrat-Regular", size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 20)

                    StopCardsGrid(selectedStop: $selectedStop)
                        .padding(.horizontal, 14)

                    // 36pt gap between last card and button
                    Button("Continuer") {}
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 14)
                        .padding(.top, 36)
                        .padding(.bottom, safeBottom + 6)
                }
            }
            .scrollDisabled(level != .full)
        }
        .frame(height: displayHeight)
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .bottom) {
                // Extends fully to screen bottom covering safe area
                Color(red: 0.11, green: 0.11, blue: 0.11)
                    .ignoresSafeArea(edges: .bottom)
                // Rounded top corners only
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.11, blue: 0.11))
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
        .gesture(sheetDrag)
        .onChange(of: level) { _, newLevel in
            baseHeight = heightFor(newLevel)
        }
        .onAppear {
            level = .full
            baseHeight = fullHeight
        }
    }
}

// MARK: - Step indicator row

private struct StepIndicatorRow: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...total, id: \.self) { step in
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(step <= current ? 1.0 : 0.3), lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(step == current ? Color.white.opacity(0.15) : .clear)
                        .frame(width: 32, height: 32)
                    Text("\(step)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(step <= current ? 1.0 : 0.35))
                }
                if step < total {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Stop cards

private struct StopCardsGrid: View {
    @Binding var selectedStop: UUID?
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(NearbyStopMockData.stops) { stop in
                NearbyStopCard(stop: stop, isSelected: selectedStop == stop.id)
                    .onTapGesture { selectedStop = stop.id }
            }
        }
    }
}

private struct NearbyStopCard: View {
    let stop: NearbyStop
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(stop.name)
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Circle()
                    .fill(Color(hex: "#B5CFF8"))
                    .frame(width: 10, height: 10)
                    .padding(.top, 3)
            }
            WrappingLineBadges(lines: stop.lines)
            Spacer(minLength: 0)
            Text("\(stop.distanceMeters)m de votre position")
                .font(.custom("Montserrat-Regular", size: 10))
                .foregroundStyle(.black)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(isSelected ? Color(hex: "#BDDDFF") : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct WrappingLineBadges: View {
    let lines: [StopLine]
    var body: some View {
        let chunks = lines.chunked(into: 4)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(chunks.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    ForEach(chunks[i]) { line in
                        Text(line.number)
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .foregroundStyle(.black)
                            .frame(width: 28, height: 24)
                            .background(line.color)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Models

struct StopLine: Identifiable {
    let id = UUID()
    let number: String
    let color: Color
}

struct NearbyStop: Identifiable {
    let id = UUID()
    let name: String
    let lines: [StopLine]
    let distanceMeters: Int
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - Mock data

enum NearbyStopMockData {
    private static func l(_ n: String, _ r: Double, _ g: Double, _ b: Double) -> StopLine {
        StopLine(number: n, color: Color(red: r, green: g, blue: b))
    }
    static let stops: [NearbyStop] = [
        .init(name: "Gare centrale",   lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12)], distanceMeters: 50),
        .init(name: "Bourse",          lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12)], distanceMeters: 95),
        .init(name: "Royale",          lines: [l("33",0.91,0.42,0.55),l("38",0.55,0.36,0.75),l("71",0.18,0.62,0.23),l("95",0.14,0.42,0.25)], distanceMeters: 120),
        .init(name: "Parc",            lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("92",0.82,0.27,0.12),l("93",0.88,0.44,0.10),l("29",0.90,0.50,0.14)], distanceMeters: 150),
        .init(name: "De Brouckère",    lines: [l("4",0.91,0.28,0.44),l("10",0.55,0.36,0.75),l("5",0.90,0.50,0.14),l("1",0.42,0.22,0.68)], distanceMeters: 175),
        .init(name: "Palais",          lines: [l("92",0.82,0.27,0.12)], distanceMeters: 200),
        .init(name: "Sainte-Catherine",lines: [l("1",0.42,0.22,0.68),l("5",0.90,0.50,0.14)], distanceMeters: 250),
        .init(name: "Ravenstein",      lines: [l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12),l("71",0.18,0.62,0.23)], distanceMeters: 300),
    ]
}
