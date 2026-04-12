import SwiftUI

struct SignalementsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @State private var selectedFilter: LineFilter = .all
    @State private var query = ""
    @State private var selectedLine: LineStatusItem?

    private var filteredLines: [LineStatusItem] {
        let base = selectedFilter == .all
            ? LineStatusMockData.all
            : LineStatusMockData.all.filter { $0.filter == selectedFilter }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.line.localizedCaseInsensitiveContains(trimmed)
            || $0.direction.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#1B1B1B").ignoresSafeArea()

            if let selectedLine {
                LineOverviewView(
                    line: selectedLine,
                    onBack: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            self.selectedLine = nil
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                        .padding(.horizontal, 21)
                        .padding(.top, 12)

                    filtersRow
                        .padding(.horizontal, 21)
                        .padding(.top, 24)

                    Text("\(LineStatusMockData.availableCount) lignes disponible")
                        .font(.custom("Darumadrop One", size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 21)
                        .padding(.top, 18)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredLines) { line in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        selectedLine = line
                                    }
                                } label: {
                                    LineStatusCard(line: line)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 19) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    nav.showSideMenu = true
                }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 42, height: 40)
                    .overlay(
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)

                TextField("", text: $query, prompt: Text("Zoek hier naar een topic").foregroundStyle(Color.black.opacity(0.55)))
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundStyle(.black)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 1)
            )
        }
    }

    private var filtersRow: some View {
        HStack(spacing: 16) {
            ForEach(LineFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.label)
                        .font(.custom("Montserrat-Regular", size: 15))
                        .foregroundStyle(selectedFilter == filter ? .black : .white)
                        .frame(width: filter == .metro ? 78 : 76, height: 35)
                        .background(selectedFilter == filter ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LineOverviewView: View {
    let line: LineStatusItem
    let onBack: () -> Void

    private var stops: [LineOverviewStop] {
        LineOverviewMockData.stops(for: line)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            routeSummary
                .padding(.horizontal, 21)
                .padding(.top, 22)

            Divider()
                .overlay(Color.white.opacity(0.84))
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        LineOverviewStopRow(
                            stop: stop,
                            isFirst: index == 0,
                            isLast: index == stops.count - 1
                        )
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 28)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))

                    Text("Lignes")
                        .font(.custom("Montserrat-SemiBold", size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(Color(hex: "#2A3043"))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 18) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)

                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar

            HStack(spacing: 16) {
                Text(line.line)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(line.lineTextColor)
                    .frame(width: 40, height: 44)
                    .background(line.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 0) {
                    routePill(text: line.origin, isLeading: true)

                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 14, height: 1)

                    routePill(text: line.destination, isLeading: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func routePill(text: String, isLeading: Bool) -> some View {
        Text(text)
            .font(.custom("Montserrat-Regular", size: 14))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(isLeading ? .leading : .center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: isLeading ? .leading : .center)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white, lineWidth: 1)
            )
    }

    private var routeSummary: some View {
        HStack(spacing: 22) {
            Label("45min", systemImage: "clock.arrow.circlepath")
                .labelStyle(LineOverviewMetricLabelStyle())

            Label("\(stops.count) arrets", systemImage: "mappin.and.ellipse")
                .labelStyle(LineOverviewMetricLabelStyle())
        }
    }
}

private struct LineStatusCard: View {
    let line: LineStatusItem

    private var statusColor: Color {
        switch line.status {
        case .fluid: return Color(hex: "#6CE8C8")
        case .disrupted: return Color(hex: "#FF9B3F")
        case .critical: return Color(hex: "#FF7A7A")
        }
    }

    private var borderColor: Color {
        switch line.status {
        case .fluid: return Color(hex: "#7EF1D1")
        case .disrupted: return Color(hex: "#FF9B3F")
        case .critical: return Color(hex: "#FF8A8A")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(line.line)
                .font(.custom("Montserrat-SemiBold", size: 16))
                .foregroundStyle(line.lineTextColor)
                .frame(width: 32, height: 32)
                .background(line.lineColor)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(line.direction)
                    .font(.custom("Montserrat-Regular", size: 16))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)

                    Text("\(line.status.label) – \(line.reportsCount) signalements")
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.78))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .padding(.horizontal, 15)
        .frame(height: 64)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }
}

private struct LineOverviewStopRow: View {
    let stop: LineOverviewStop
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.78))
                        .frame(width: 2)
                        .opacity(isFirst ? 0 : 1)

                    Rectangle()
                        .fill(Color.white.opacity(0.78))
                        .frame(width: 2)
                        .opacity(isLast ? 0 : 1)
                }

                Circle()
                    .fill(isFirst ? Color.white : Color(hex: "#1B1B1B"))
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .frame(width: 18, height: 18)
            }
            .frame(width: 18)

            LineOverviewStopCard(stop: stop)
        }
    }
}

private struct LineOverviewStopCard: View {
    let stop: LineOverviewStop

    private var statusColor: Color {
        switch stop.status {
        case .fluid: return Color(hex: "#6CE8C8")
        case .disrupted: return Color(hex: "#FF9B3F")
        case .critical: return Color(hex: "#FF7A7A")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(stop.name)
                    .font(.custom("DelaGothicOne-Regular", size: 16))
                    .foregroundStyle(.black)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Prochain passage")
                        .font(.custom("Darumadrop One", size: 10))
                        .foregroundStyle(.black.opacity(0.92))

                    Text(stop.nextPassages)
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(.black)
                }
            }

            FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(stop.connections) { connection in
                    Text(connection.label)
                        .font(.custom("Montserrat-SemiBold", size: connection.fontSize))
                        .foregroundStyle(connection.textColor)
                        .frame(width: 20, height: 20)
                        .background(connection.color)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)

                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                Text("\(stop.status.label) – \(stop.reportsCount) signalements")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LineOverviewMetricLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            configuration.title
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum LineFilter: CaseIterable, Identifiable {
    case all
    case tram
    case bus
    case metro

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "Tous"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .metro: return "Metro"
        }
    }
}

enum LineHealthStatus {
    case fluid
    case disrupted
    case critical

    var label: String {
        switch self {
        case .fluid: return "Fluide"
        case .disrupted: return "Perturbé"
        case .critical: return "Critique"
        }
    }
}

struct LineStatusItem: Identifiable {
    let id = UUID()
    let line: String
    let lineColor: Color
    let lineTextColor: Color
    let origin: String
    let destination: String
    let direction: String
    let status: LineHealthStatus
    let reportsCount: Int
    let filter: LineFilter
}

struct LineOverviewStop: Identifiable {
    let id = UUID()
    let name: String
    let connections: [LineConnectionBadge]
    let nextPassages: String
    let status: LineHealthStatus
    let reportsCount: Int
}

struct LineConnectionBadge: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
    let textColor: Color
    let fontSize: CGFloat
}

enum LineStatusMockData {
    static let availableCount = 82

    static let all: [LineStatusItem] = [
        .init(line: "1", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Gare de l'ouest", destination: "Stokkel", direction: "Gare de l’ouest → Stokkel", status: .fluid, reportsCount: 2, filter: .metro),
        .init(line: "2", lineColor: Color(hex: "#ED7807"), lineTextColor: .white, origin: "Simonis", destination: "Elisabeth", direction: "Simonis → Elisabeth", status: .disrupted, reportsCount: 9, filter: .metro),
        .init(line: "4", lineColor: Color(hex: "#EA4F80"), lineTextColor: .white, origin: "Gare du Nord", destination: "Stalle", direction: "Gare du Nord → Stalle", status: .fluid, reportsCount: 2, filter: .tram),
        .init(line: "5", lineColor: Color(hex: "#F9A611"), lineTextColor: .white, origin: "Erasme", destination: "Herrmann-Debroux", direction: "Erasme → Herrmann-Debroux", status: .disrupted, reportsCount: 17, filter: .metro),
        .init(line: "6", lineColor: Color(hex: "#0066A3"), lineTextColor: .white, origin: "Roi Baudouin", destination: "Elisabeth", direction: "Roi Baudouin → Elisabeth", status: .disrupted, reportsCount: 9, filter: .metro),
        .init(line: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, origin: "Vanderkindere", destination: "Heysel", direction: "Vanderkindere → Heysel", status: .critical, reportsCount: 53, filter: .tram),
        .init(line: "8", lineColor: Color(hex: "#378BFF"), lineTextColor: .white, origin: "Louise", destination: "Roodebeek", direction: "Louise → Roodebeek", status: .critical, reportsCount: 22, filter: .bus),
        .init(line: "9", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Montgomery", destination: "Simonis", direction: "Montgomery → Simonis", status: .fluid, reportsCount: 4, filter: .tram),
        .init(line: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Rogier", destination: "Churchill", direction: "Rogier → Churchill", status: .fluid, reportsCount: 1, filter: .tram)
    ]
}

enum LineOverviewMockData {
    static func stops(for line: LineStatusItem) -> [LineOverviewStop] {
        let baseNames = [
            line.origin,
            "Beekkant",
            "Etangs Noirs",
            "Comte de Flandre",
            "Sainte-Catherine",
            "De Brouckere",
            "Gare Centrale",
            "Parc",
            "Arts-Loi",
            "Maelbeek",
            "Schuman",
            "Mérode",
            "Montgomery",
            "Joséphine-Charlotte",
            "Gribaumont",
            "Tomberg",
            "Roodebeek",
            line.destination
        ]

        let connections: [[LineConnectionBadge]] = [
            [badges("63", "#91BEE5", .black, 10), badges("66", "#0065A6", .white, 10), badges("65", "#F3C300", .black, 10), badges("89", "#B4BD10", .black, 10), badges("38", "#A67CB0", .white, 10), badges("52", "#FFDC01", .black, 10)],
            [badges("1", "#8F4199", .white, 10), badges("2", "#ED7807", .white, 10), badges("5", "#F9A611", .white, 10), badges("6", "#0066A3", .white, 10), badges("87", "#4C8B33", .white, 10)],
            [badges("1", "#8F4199", .white, 10), badges("5", "#F9A611", .white, 10), badges("13", "#91BEE5", .black, 10), badges("20", "#F3C300", .black, 10), badges("86", "#0066A3", .white, 10)],
            [badges("1", "#8F4199", .white, 10), badges("5", "#F9A611", .white, 10), badges("13", "#91BEE5", .black, 10), badges("20", "#F3C300", .black, 10), badges("86", "#0066A3", .white, 10)],
            [badges("1", "#8F4199", .white, 10), badges("5", "#F9A611", .white, 10), badges("13", "#91BEE5", .black, 10), badges("20", "#F3C300", .black, 10), badges("86", "#0066A3", .white, 10)],
            [badges("1", "#8F4199", .white, 10), badges("5", "#F9A611", .white, 10), badges("13", "#91BEE5", .black, 10), badges("20", "#F3C300", .black, 10), badges("86", "#0066A3", .white, 10)],
            [badges("3", "#8F4199", .white, 10), badges("4", "#EA4F80", .white, 10), badges("29", "#F3C300", .black, 9)],
            [badges("12", "#4C8B33", .white, 9), badges("21", "#ED7807", .white, 9), badges("34", "#91BEE5", .black, 9)],
            [badges("1", "#8F4199", .white, 10), badges("2", "#ED7807", .white, 10), badges("6", "#0066A3", .white, 10)],
            [badges("36", "#91BEE5", .black, 9), badges("56", "#A67CB0", .white, 9), badges("79", "#F3C300", .black, 9)],
            [badges("12", "#4C8B33", .white, 9), badges("21", "#ED7807", .white, 9), badges("36", "#91BEE5", .black, 9)],
            [badges("81", "#91BEE5", .black, 9), badges("27", "#ED7807", .white, 9)],
            [badges("7", "#EFE048", .black, 10), badges("25", "#F9A611", .white, 9)],
            [badges("39", "#A67CB0", .white, 9), badges("44", "#91BEE5", .black, 9)],
            [badges("28", "#4C8B33", .white, 9), badges("80", "#F3C300", .black, 9)],
            [badges("42", "#EA4F80", .white, 9), badges("79", "#F3C300", .black, 9)],
            [badges("45", "#91BEE5", .black, 9), badges("66", "#0065A6", .white, 9)],
            [badges("39", "#A67CB0", .white, 9), badges("44", "#91BEE5", .black, 9), badges("76", "#ED7807", .white, 9)]
        ]

        let statuses: [LineHealthStatus] = [
            .fluid, .critical, .disrupted, .disrupted, .fluid, .fluid, .fluid, .disrupted, .fluid,
            .disrupted, .fluid, .fluid, .critical, .fluid, .disrupted, .fluid, .fluid, line.status
        ]

        let reports = [2, 19, 8, 5, 1, 1, 0, 3, 2, 4, 1, 0, 7, 1, 3, 0, 1, line.reportsCount]
        let nextPassages = ["2, 5, 15 min", "1, 7, 11 min", "3, 9, 17 min", "4, 10, 18 min"]

        return baseNames.enumerated().map { index, name in
            LineOverviewStop(
                name: name,
                connections: connections[index],
                nextPassages: nextPassages[index % nextPassages.count],
                status: statuses[index],
                reportsCount: reports[index]
            )
        }
    }

    private static func badges(_ label: String, _ color: String, _ textColor: Color, _ fontSize: CGFloat) -> LineConnectionBadge {
        LineConnectionBadge(label: label, color: Color(hex: color), textColor: textColor, fontSize: fontSize)
    }
}
