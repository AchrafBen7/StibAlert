import SwiftUI

// MARK: - Editorial line visualizer (stops-aware schematic)

struct EditorialLineVisualizer: View {
    let line: String
    let color: Color
    var stops: [String] = []
    var disruptedIndices: Set<Int> = []
    var disruptedStopName: String? = nil

    private var hasRealStops: Bool { !stops.isEmpty }

    private struct Waypoint: Identifiable {
        let id: Int
        let originalIndex: Int
        let total: Int
        let name: String
        let isDisrupted: Bool
        let isTerminus: Bool
        let isLabeled: Bool
    }

    private var waypoints: [Waypoint] {
        guard hasRealStops else { return [] }
        let total = stops.count
        let maxWaypoints = 30

        var keepSet = Set<Int>()
        keepSet.insert(0)
        keepSet.insert(total - 1)
        for di in disruptedIndices {
            keepSet.insert(di)
            if di > 0 { keepSet.insert(di - 1) }
            if di < total - 1 { keepSet.insert(di + 1) }
        }

        var allKept = Array(0..<total)
        if total > maxWaypoints {
            var picked = keepSet
            let denom = max(1, maxWaypoints - 1)
            for step in 0..<maxWaypoints {
                let candidate = Int(round(Double(step) * Double(total - 1) / Double(denom)))
                picked.insert(min(max(candidate, 0), total - 1))
            }
            allKept = picked.sorted()
        }

        return allKept.map { idx in
            let isDisrupted = disruptedIndices.contains(idx)
            let isTerminus = idx == 0 || idx == total - 1
            let isAdjacent = disruptedIndices.contains { di in abs(di - idx) == 1 }
            let labeled = isTerminus || isDisrupted || isAdjacent
            return Waypoint(
                id: idx,
                originalIndex: idx,
                total: total,
                name: stops[idx],
                isDisrupted: isDisrupted,
                isTerminus: isTerminus,
                isLabeled: labeled
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DS.Color.paper2.opacity(0.4)

                if hasRealStops {
                    realPathLayer(in: geo.size)
                } else {
                    stylizedFallback(in: geo.size)
                }

                cornerHUD(in: geo.size)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func position(for originalIndex: Int, total: Int, in size: CGSize, rng: inout EditorialPRNG) -> CGPoint {
        let padX: CGFloat = 18, padTop: CGFloat = 30, padBot: CGFloat = 34
        let usableW = size.width - padX * 2
        let usableH = size.height - padTop - padBot
        let t = total <= 1 ? 0 : CGFloat(originalIndex) / CGFloat(total - 1)
        let x = padX + t * usableW
        // Straight horizontal axis — labels still alternate above/below to
        // avoid overlap, so we don't need to zigzag the stop positions.
        let y = padTop + usableH * 0.5
        _ = rng.next()  // keep RNG advancing so seeded outputs stay stable elsewhere
        return CGPoint(x: x, y: y)
    }

    private func seededRNG(for total: Int) -> EditorialPRNG {
        var seed: UInt32 = 2166136261
        for c in line.unicodeScalars { seed ^= c.value; seed = seed &* 16777619 }
        seed ^= UInt32(truncatingIfNeeded: total) &* 0x9E3779B9
        return EditorialPRNG(seed: seed)
    }

    @ViewBuilder
    private func realPathLayer(in size: CGSize) -> some View {
        let pts: [(Waypoint, CGPoint)] = {
            var rng = seededRNG(for: stops.count)
            return waypoints.map { wp in
                (wp, position(for: wp.originalIndex, total: stops.count, in: size, rng: &rng))
            }
        }()

        Path { p in
            guard let first = pts.first?.1 else { return }
            p.move(to: first)
            for (_, pt) in pts.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .shadow(color: color.opacity(0.55), radius: 6)

        ForEach(pts, id: \.0.id) { wp, pt in
            let baseSize: CGFloat = wp.isTerminus ? 11 : (wp.isDisrupted ? 11 : 7)
            Rectangle()
                .fill(wp.isDisrupted ? DS.Color.statusMajor : (wp.isTerminus ? DS.Color.ink : DS.Color.paper))
                .frame(width: baseSize, height: baseSize)
                .rotationEffect(.degrees(45))
                .overlay(
                    Rectangle()
                        .stroke(DS.Color.ink, lineWidth: 1)
                        .rotationEffect(.degrees(45))
                        .frame(width: baseSize, height: baseSize)
                )
                .position(pt)

            if wp.isLabeled {
                Text(wp.name.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(wp.isDisrupted ? DS.Color.statusMajor : DS.Color.inkMute)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 80)
                    .position(x: pt.x, y: pt.y + ((wp.originalIndex % 2 == 0) ? -16 : 16))
            }
        }

        if let firstDisrupted = pts.first(where: { $0.0.isDisrupted }) {
            EditorialPulsingHalo(color: DS.Color.statusMajor)
                .position(firstDisrupted.1)
        }
    }

    @ViewBuilder
    private func stylizedFallback(in size: CGSize) -> some View {
        var rng = seededRNG(for: 7)
        let count = 7
        let pts: [CGPoint] = (0..<count).map { i in
            position(for: i, total: count, in: size, rng: &rng)
        }
        let stylizedDisrupted = max(1, count / 2)

        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .shadow(color: color.opacity(0.55), radius: 6)

        ForEach(Array(pts.enumerated()), id: \.offset) { i, pt in
            let isDisrupted = i == stylizedDisrupted
            let isTerminus = i == 0 || i == count - 1
            let size: CGFloat = isTerminus ? 11 : 9
            Rectangle()
                .fill(isDisrupted ? DS.Color.statusMajor : (isTerminus ? DS.Color.ink : DS.Color.paper))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(45))
                .overlay(
                    Rectangle()
                        .stroke(DS.Color.ink, lineWidth: 1)
                        .rotationEffect(.degrees(45))
                        .frame(width: size, height: size)
                )
                .position(pt)
        }

        if stylizedDisrupted < pts.count {
            EditorialPulsingHalo(color: DS.Color.statusMajor)
                .position(pts[stylizedDisrupted])
        }
    }

    @ViewBuilder
    private func cornerHUD(in size: CGSize) -> some View {
        VStack {
            HStack {
                Text("◤ LIVE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("L\(line) ◥")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(color)
            }
            Spacer()
            HStack {
                Text("◣ \(hasRealStops ? stops.count : 7) ARRÊTS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                if let disruptedStopName, !disruptedStopName.isEmpty {
                    Text("\(disruptedStopName.uppercased()) ◢")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(DS.Color.statusMajor)
                        .lineLimit(1)
                } else {
                    Text("ZONE PERTURBÉE ◢")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
            }
        }
        .padding(6)
    }
}

struct EditorialPulsingHalo: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: 24, height: 24)
                .scaleEffect(animate ? 2.4 : 0.5)
                .opacity(animate ? 0 : 1)
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: 16, height: 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

struct EditorialPRNG {
    var state: UInt32
    init(seed: UInt32) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B79F5
        var r = (state ^ (state >> 15)) &* (1 | state)
        r = (r &+ ((r ^ (r >> 7)) &* (61 | r))) ^ r
        return CGFloat((r ^ (r >> 14)) >> 0) / CGFloat(UInt32.max)
    }
}

enum ReportsStopMatching {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ReportsLineExtraction {
    /// Extracts STIB line ids from a free-text description ("bus 47 dévié",
    /// "tram 81", "ligne T7"). Used to populate NetworkIssueCarouselItem.lines
    /// when the upstream incident does not carry a structured line code.
    static func extract(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let pattern = #"(?:\b(?:bus|tram|ligne|metro|métro|line)\b)\s*([TtBb]?\d{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var ordered: [String] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let captureRange = match.range(at: 1)
            guard captureRange.location != NSNotFound else { return }
            let raw = nsText.substring(with: captureRange).uppercased()
            let digits = raw.filter(\.isNumber)
            guard let value = Int(digits), (1...999).contains(value) else { return }
            if !seen.contains(raw) {
                ordered.append(raw)
                seen.insert(raw)
            }
        }
        return ordered
    }
}
