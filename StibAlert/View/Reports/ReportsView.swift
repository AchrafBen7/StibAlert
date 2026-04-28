import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var stibi: StibiCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reports: [SignalementDTO] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadError: String? = nil
    @State private var query = ""
    @State private var selectedLineFilter = "Tout"
    @State private var selectedReport: SignalementDTO? = nil

    private var availableLineFilters: [String] {
        let lines = Set(reports.map(\.ligne)).sorted {
            $0.compare($1, options: .numeric) == .orderedAscending
        }
        return ["Tout"] + lines
    }

    private var filteredReports: [SignalementDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return reports.filter { report in
            let matchesLine = selectedLineFilter == "Tout" || report.ligne == selectedLineFilter
            guard matchesLine else { return false }
            guard !trimmed.isEmpty else { return true }

            let stopName = arretName(for: report) ?? ""
            return report.ligne.localizedCaseInsensitiveContains(trimmed)
                || report.typeProbleme.localizedCaseInsensitiveContains(trimmed)
                || report.description.localizedCaseInsensitiveContains(trimmed)
                || stopName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#12161F").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 12)

                lineFilters
                    .padding(.top, 20)

                if let loadError {
                    errorBanner(loadError)
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                }

                if isLoading && !hasLoaded {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if hasLoaded && reports.isEmpty {
                    emptyState(
                        icon: "tray.fill",
                        title: "Aucun signalement récent",
                        message: "Les derniers reports STIB apparaîtront ici dès qu'ils sont publiés."
                    )
                } else if hasLoaded && filteredReports.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "Aucun résultat",
                        message: "Essaie une autre ligne ou recherche un autre arrêt."
                    )
                } else {
                    Text("\(filteredReports.count) signalement\(filteredReports.count == 1 ? "" : "s")")
                        .font(.custom("DelaGothicOne-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 21)
                        .padding(.top, 18)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReports) { report in
                                Button {
                                    withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.32, dampingFraction: 0.86)) {
                                        selectedReport = report
                                    }
                                } label: {
                                    ReportFeedCard(
                                        report: report,
                                        stopName: arretName(for: report)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedReport) { report in
            SignalementDetailView(
                signalement: report,
                onDismiss: { selectedReport = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            stibi.setCurrentScreen("reports")
            await loadReports()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 19) {
                Button {
                    withAnimation(AppMotion.spring(reduceMotion: reduceMotion)) {
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

                    TextField(
                        "",
                        text: $query,
                        prompt: Text("Rechercher une ligne, un arrêt ou un problème")
                            .foregroundStyle(Color.black.opacity(0.55))
                    )
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Signalements")
                    .font(.custom("DelaGothicOne-Regular", size: 26))
                    .foregroundStyle(.white)

                Text("Les derniers reports communautaires, filtrables par ligne et recherchables par arrêt.")
                    .font(.custom("Montserrat-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var lineFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableLineFilters, id: \.self) { line in
                    Button {
                        withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) {
                            selectedLineFilter = line
                        }
                    } label: {
                        Text(line == "Tout" ? "Tout" : "Ligne \(line)")
                            .font(.custom("Montserrat-SemiBold", size: 13))
                            .foregroundStyle(selectedLineFilter == line ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(selectedLineFilter == line ? Color.white : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 21)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#FF7A7A"))
            Text(message)
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Button {
                Task { await loadReports(force: true) }
            } label: {
                Text("Réessayer")
                    .font(.custom("Montserrat-SemiBold", size: 12))
                    .foregroundStyle(Color(hex: "#89B7FF"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.42))
            Text(title)
                .font(.custom("DelaGothicOne-Regular", size: 20))
                .foregroundStyle(.white)
            Text(message)
                .font(.custom("Montserrat-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 38)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func loadReports(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else {
            hasLoaded = true
            return
        }
        guard !isLoading else { return }
        if hasLoaded && !force { return }

        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let response = try await SignalementService.liste(page: 1, limit: 100)
            reports = response.signalements.sorted {
                ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast)
            }
            if !availableLineFilters.contains(selectedLineFilter) {
                selectedLineFilter = "Tout"
            }
        } catch {
            loadError = error.localizedDescription
            print("ReportsView load failed: \(error.localizedDescription)")
        }
    }

    private func arretName(for report: SignalementDTO) -> String? {
        if case .populated(let arret) = report.arretId {
            return arret.nom
        }
        return nil
    }
}

private struct ReportFeedCard: View {
    let report: SignalementDTO
    let stopName: String?

    private var lineColor: Color {
        switch report.typeProbleme.lowercased() {
        case "accident":
            return Color(hex: "#EF4444")
        case "panne":
            return Color(hex: "#F97316")
        case "retard":
            return Color(hex: "#3B82F6")
        default:
            return Color(hex: "#8B5CF6")
        }
    }

    private var statusText: String {
        if report.status == "resolved" {
            return "Résolu"
        }
        return report.typeProbleme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(report.ligne)
                    .font(.custom("DelaGothicOne-Regular", size: 16))
                    .foregroundStyle(lineColor.isDark ? .white : .black)
                    .frame(width: 48, height: 48)
                    .background(lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(stopName ?? "Arrêt STIB")
                        .font(.custom("Montserrat-SemiBold", size: 15))
                        .foregroundStyle(.white)

                    Text(statusText)
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(lineColor)

                    Text(report.description)
                        .font(.custom("Montserrat-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(3)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Label(report.freshnessLabel, systemImage: "clock")
                    .labelStyle(.titleAndIcon)

                if let confidence = report.confirmationsSummaryLabel {
                    Label(confidence, systemImage: "checkmark.seal")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.custom("Montserrat-SemiBold", size: 11))
            .foregroundStyle(.white.opacity(0.58))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
