import SwiftUI

struct SignalementsView: View {
    @State private var selectedFilter: SignalFilter = .all

    private var filtered: [SignalMock] {
        selectedFilter == .all ? SignalMockData.all : SignalMockData.all.filter { $0.filter == selectedFilter }
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                filterChips
                    .padding(.top, 12)
                Divider().padding(.top, 10)
                signalList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Signalements")
                    .font(.custom("DelaGothicOne-Regular", size: 28))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("\(SignalMockData.all.count) signalements en cours")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            Spacer()
            Circle()
                .fill(DesignSystem.Colors.accent.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.accent)
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Filter chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SignalFilter.allCases) { f in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedFilter = f }
                    } label: {
                        Text(f.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedFilter == f ? .white : DesignSystem.Colors.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == f ? Color(hex: "#0B111E") : DesignSystem.Colors.cardBackground)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedFilter == f ? Color(hex: "#0B111E") : DesignSystem.Colors.border,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: List
    private var signalList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                ForEach(filtered) { signal in
                    SignalCard(signal: signal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Signal card

private struct SignalCard: View {
    let signal: SignalMock

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Line badge
            Text(signal.line)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(signal.lineColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(signal.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Spacer()
                    StatusPill(label: signal.status, color: signal.statusColor)
                }
                Text(signal.stop)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(signal.time)
                        .font(.system(size: 12))
                }
                .foregroundStyle(DesignSystem.Colors.secondaryText.opacity(0.7))
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Models & mock data

enum SignalFilter: CaseIterable, Identifiable {
    case all, metro, tram, bus

    var id: Self { self }
    var label: String {
        switch self {
        case .all: return "Tous"
        case .metro: return "Métro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        }
    }
}

struct SignalMock: Identifiable {
    let id = UUID()
    let line: String
    let lineColor: Color
    let title: String
    let stop: String
    let status: String
    let statusColor: Color
    let time: String
    let filter: SignalFilter
}

enum SignalMockData {
    static let all: [SignalMock] = [
        .init(line: "M1", lineColor: Color(hex: "#4557A1"), title: "Retard important",
              stop: "Arts-Loi → Stockel", status: "En cours", statusColor: .orange,
              time: "Il y a 2 min", filter: .metro),
        .init(line: "M2", lineColor: Color(hex: "#4557A1"), title: "Porte fermée défectueuse",
              stop: "Simonis", status: "Signalé", statusColor: Color(hex: "#4557A1"),
              time: "Il y a 5 min", filter: .metro),
        .init(line: "T7", lineColor: Color(hex: "#D7263D"), title: "Affluence élevée",
              stop: "Vanderkindere → Heysel", status: "Vérifié", statusColor: .green,
              time: "Il y a 8 min", filter: .tram),
        .init(line: "T3", lineColor: Color(hex: "#D7263D"), title: "Tram bloqué",
              stop: "Gare du Nord", status: "En cours", statusColor: .orange,
              time: "Il y a 11 min", filter: .tram),
        .init(line: "T25", lineColor: Color(hex: "#D7263D"), title: "Déviation temporaire",
              stop: "Ixelles – Flagey", status: "Résolu", statusColor: .green,
              time: "Il y a 18 min", filter: .tram),
        .init(line: "B95", lineColor: Color(hex: "#CBC1AD"), title: "Bus bondé",
              stop: "Louise → Centrale", status: "Signalé", statusColor: Color(hex: "#4557A1"),
              time: "Il y a 20 min", filter: .bus),
        .init(line: "B54", lineColor: Color(hex: "#CBC1AD"), title: "Arrêt sauté",
              stop: "Porte de Hal", status: "En cours", statusColor: .orange,
              time: "Il y a 25 min", filter: .bus),
        .init(line: "M6", lineColor: Color(hex: "#4557A1"), title: "Interruption de service",
              stop: "Roi Baudouin", status: "En cours", statusColor: .red,
              time: "Il y a 30 min", filter: .metro),
    ]
}
