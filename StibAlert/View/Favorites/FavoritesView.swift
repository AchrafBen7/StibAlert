import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var nav: AppNavigation
    @State private var selectedFilter: FavoriteTransportFilter = .all
    @State private var query = ""
    @State private var selectedItem: FavoriteTransitItem?

    private var filteredItems: [FavoriteTransitItem] {
        let base = selectedFilter == .all
            ? FavoritesMockData.items
            : FavoritesMockData.items.filter { $0.filter == selectedFilter }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.code.localizedCaseInsensitiveContains(trimmed)
            || $0.problemLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#1B1B1B").ignoresSafeArea()

            if let selectedItem {
                FavoriteStopDetailView(
                    item: selectedItem,
                    onBack: { self.selectedItem = nil },
                    onClose: { self.selectedItem = nil }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.horizontal, 21)
                            .padding(.top, 12)

                        filtersRow
                            .padding(.horizontal, 21)
                            .padding(.top, 24)

                        LazyVStack(spacing: 18) {
                            ForEach(filteredItems) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    FavoriteTransitCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
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
            ForEach(FavoriteTransportFilter.allCases) { filter in
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

private struct FavoriteStopDetailView: View {
    let item: FavoriteTransitItem
    let onBack: () -> Void
    let onClose: () -> Void

    private let liveStatuses = FavoriteStopDetailMockData.liveStatuses
    private let incidents = FavoriteStopDetailMockData.incidents

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 18)

                servedLines
                    .padding(.top, 18)

                planBCard
                    .padding(.horizontal, 15)
                    .padding(.top, 36)

                sectionHeader("Etat en temps réel", trailing: nil)
                    .padding(.horizontal, 21)
                    .padding(.top, 26)

                VStack(spacing: 14) {
                    ForEach(liveStatuses) { status in
                        LiveStatusCard(status: status)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                sectionHeader("Situation actuelle", trailing: "Mise à jour : Il y a 6 min")
                    .padding(.horizontal, 21)
                    .padding(.top, 30)

                VStack(spacing: 14) {
                    ForEach(incidents) { incident in
                        IncidentCard(incident: incident)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Voir tout les signalements (5)")
                            .font(.custom("Montserrat-Regular", size: 12))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 15)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
        }
        .background(Color(hex: "#1B1B1B"))
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text(item.title)
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var servedLines: some View {
        HStack(spacing: 9) {
            ForEach(item.detailLines) { line in
                Text(line.code)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(line.textColor)
                    .frame(width: 32, height: 32)
                    .background(line.color)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var planBCard: some View {
        Button {} label: {
            HStack {
                Spacer()
                Text("Besoin d’un plan B ?")
                    .font(.custom("DelaGothicOne-Regular", size: 12))
                    .foregroundStyle(Color(hex: "#322944"))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.78))
            }
            .frame(height: 63)
            .padding(.horizontal, 18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 14))
                    .foregroundStyle(.white)

                if title == "Etat en temps réel" {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            if let trailing {
                HStack(spacing: 6) {
                    Text(trailing)
                        .font(.custom("Darumadrop One", size: 12))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct FavoriteTransitCard: View {
    let item: FavoriteTransitItem

    private var problemBackground: Color {
        switch item.severity {
        case .normal:
            return Color(hex: "#CFF8E7")
        case .warning:
            return Color(hex: "#FFD29D")
        case .blocked:
            return Color(hex: "#FFC1C1")
        }
    }

    private var problemStroke: Color {
        switch item.severity {
        case .normal:
            return Color(hex: "#5ED9AF")
        case .warning:
            return Color(hex: "#F59A3B")
        case .blocked:
            return Color(hex: "#FF8686")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.code)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(item.codeTextColor)
                    .frame(width: 32, height: 32)
                    .background(item.codeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.custom("Montserrat-SemiBold", size: 15))
                        .foregroundStyle(.black)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black)

                        Text("Mis a jour il y a 1 min")
                            .font(.custom("Darumadrop One", size: 12))
                            .foregroundStyle(.black)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    Image(systemName: "bell")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.black)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(hex: "#7CB2FF"))
                }
                .padding(.top, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(180))

                Text("Affluence: \(item.crowding)")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.82))
            }
            .padding(.top, 16)

            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    Text(item.problemLabel)
                        .font(item.severity == .normal ? .custom("Montserrat-Regular", size: 12) : .custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 35)
                        .background(problemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(problemStroke, lineWidth: 1)
                        )

                    HStack(spacing: 5) {
                        Circle()
                            .fill(.black)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Text("i")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        Text("\(item.reportCount)")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(.black)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Prochain passage")
                        .font(.custom("Darumadrop One", size: 12))
                        .foregroundStyle(.black.opacity(0.92))

                    Text(item.nextPassage)
                        .font(.custom("Montserrat-SemiBold", size: 16))
                        .foregroundStyle(.black)
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "#83B3FF"), lineWidth: 1)
        )
    }
}

private struct LiveStatusCard: View {
    let status: FavoriteLiveStatus

    private var scoreColor: Color {
        status.score >= 80 ? Color(hex: "#10B981") : Color(hex: "#FF922A")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(status.lineCode)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(status.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(status.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundStyle(.black)

                    Text(status.subtitle)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Prochain passage")
                        .font(.custom("Darumadrop One", size: 12))
                        .foregroundStyle(.black)

                    Text(status.nextPassage)
                        .font(.custom("Montserrat-SemiBold", size: 20))
                        .foregroundStyle(.black)
                }
            }

            HStack {
                Label("Fiabilité du Service", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Score")
                        .font(.custom("Darumadrop One", size: 12))
                        .foregroundStyle(.black)
                    Text("\(status.score)%")
                        .font(.custom("Montserrat-SemiBold", size: 14))
                        .foregroundStyle(scoreColor)
                }
            }
            .padding(.top, 26)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "#E6EAF0"))
                    .frame(height: 13)

                Capsule()
                    .fill(status.barColor)
                    .frame(width: max(16, CGFloat(status.score) * 3.05), height: 13)
            }
            .padding(.top, 8)

            HStack {
                Text("0%")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(.custom("Montserrat-Regular", size: 12))
            .foregroundStyle(Color(hex: "#969BA6"))
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 17)
        .padding(.bottom, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status.borderColor, lineWidth: 1)
        )
    }
}

private struct IncidentCard: View {
    let incident: FavoriteIncident

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(incident.lineCode)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(incident.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(incident.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.title)
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundStyle(.black)

                    Text(incident.body)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(incident.dotColor)
                    .frame(width: 12, height: 12)
            }

            HStack {
                Text("Confirmez cette situation ?")
                    .font(.custom("Montserrat-Regular", size: 10))
                    .foregroundStyle(.black.opacity(0.9))

                Spacer()

                Button {} label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(incident.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private enum FavoriteTransportFilter: CaseIterable, Identifiable {
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

private enum FavoriteSeverity {
    case normal
    case warning
    case blocked
}

private struct FavoriteTransitItem: Identifiable {
    let id = UUID()
    let code: String
    let codeColor: Color
    let codeTextColor: Color
    let title: String
    let crowding: String
    let problemLabel: String
    let reportCount: Int
    let nextPassage: String
    let filter: FavoriteTransportFilter
    let severity: FavoriteSeverity
    let detailLines: [FavoriteLineChip]
}

private struct FavoriteLineChip: Identifiable {
    let id = UUID()
    let code: String
    let color: Color
    let textColor: Color
}

private struct FavoriteLiveStatus: Identifiable {
    let id = UUID()
    let lineCode: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let subtitle: String
    let nextPassage: String
    let score: Int
    let barColor: Color
    let borderColor: Color
}

private struct FavoriteIncident: Identifiable {
    let id = UUID()
    let lineCode: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let body: String
    let background: Color
    let dotColor: Color
}

private enum FavoritesMockData {
    static let items: [FavoriteTransitItem] = [
        .init(code: "46", codeColor: Color(hex: "#E43C2E"), codeTextColor: .white, title: "De Wand", crowding: "Haute", problemLabel: "Perturbé", reportCount: 12, nextPassage: "15 min", filter: .bus, severity: .warning, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(code: "62", codeColor: Color(hex: "#F29DC3"), codeTextColor: .black, title: "Leopold III", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", filter: .tram, severity: .normal, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(code: "38", codeColor: Color(hex: "#A67CB0"), codeTextColor: .white, title: "Suzan Daniel", crowding: "Moyenne", problemLabel: "Bloqué", reportCount: 16, nextPassage: "/", filter: .tram, severity: .blocked, detailLines: [.init(code: "38", color: Color(hex: "#A67CB0"), textColor: .white), .init(code: "51", color: Color(hex: "#91BEE5"), textColor: .black)]),
        .init(code: "48", codeColor: Color(hex: "#ED7807"), codeTextColor: .white, title: "Heembeek", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", filter: .bus, severity: .normal, detailLines: [.init(code: "48", color: Color(hex: "#ED7807"), textColor: .white), .init(code: "56", color: Color(hex: "#0066A3"), textColor: .white)]),
        .init(code: "1", codeColor: Color(hex: "#8F4199"), codeTextColor: .white, title: "Gare de l’ouest", crowding: "Moyenne", problemLabel: "Perturbé", reportCount: 3, nextPassage: "2 min", filter: .metro, severity: .warning, detailLines: [.init(code: "1", color: Color(hex: "#8F4199"), textColor: .white), .init(code: "5", color: Color(hex: "#F9A611"), textColor: .white)]),
        .init(code: "7", codeColor: Color(hex: "#EFE048"), codeTextColor: .black, title: "Vanderkindere", crowding: "Haute", problemLabel: "Bloqué", reportCount: 9, nextPassage: "8 min", filter: .tram, severity: .blocked, detailLines: [.init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "92", color: Color(hex: "#4C8B33"), textColor: .white)])
    ]
}

private enum FavoriteStopDetailMockData {
    static let liveStatuses: [FavoriteLiveStatus] = [
        .init(lineCode: "46", lineColor: Color(hex: "#F29DC3"), lineTextColor: .black, title: "Traffic Normal", subtitle: "Tout fonctionne\nparfaitement", nextPassage: "3 min", score: 94, barColor: Color(hex: "#10C994"), borderColor: Color(hex: "#B7F2DE")),
        .init(lineCode: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, title: "Traffic Perturbé", subtitle: "Perturbations\nmineures", nextPassage: "12min", score: 64, barColor: Color(hex: "#FF922A"), borderColor: Color(hex: "#FFC98D"))
    ]

    static let incidents: [FavoriteIncident] = [
        .init(lineCode: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, title: "Traffic Normal", body: "Aucun problème détecté\nrécemment sur cette ligne.\nLe service semble\nfonctionner normalement.", background: Color(hex: "#CFF8E7"), dotColor: Color(hex: "#49D7A5")),
        .init(lineCode: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, title: "Retard", body: "Un incident a été signalé à l'arrêt\nDelacroix : une personne présente\nsur la voie a provoqué un arrêt\ntemporaire de la circulation. Les\nautorités sont intervenues. Des\nretards de 10 à 15 minutes sont à\nprévoir sur la ligne 46.", background: Color(hex: "#FFD29D"), dotColor: Color(hex: "#FF922A")),
        .init(lineCode: "46", lineColor: Color(hex: "#F29DC3"), lineTextColor: .black, title: "Accident", body: "Un incident a été signalé à l'arrêt\nDelacroix : une personne présente\nsur la voie a provoqué un arrêt\ntemporaire de la circulation. Les\nautorités sont intervenues. Des\nretards de 10 à 15 minutes sont à\nprévoir sur la ligne 46.", background: Color(hex: "#FFB3B7"), dotColor: Color(hex: "#FF7178"))
    ]
}
