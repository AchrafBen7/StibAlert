import SwiftUI

struct HomeEventImpactSheet: View {
    let event: TransportEventImpactDTO
    let onOpenLine: (String) -> Void
    let onOpenStop: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(DS.Color.ink.opacity(0.22))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                heroCard

                if !event.impactedLines.isEmpty {
                    sectionCard(title: "LIGNES TOUCHÉES") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                            ForEach(event.impactedLines, id: \.self) { line in
                                Button {
                                    onOpenLine(line)
                                } label: {
                                    HStack(spacing: 6) {
                                        LineBadge(line: line, size: .sm)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(DS.Color.inkMute)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .frame(height: 40)
                                    .background(DS.Color.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let impactedStops = event.impactedStopDetails, !impactedStops.isEmpty {
                    sectionCard(title: "ARRÊTS / ZONES") {
                        VStack(spacing: 0) {
                            ForEach(Array(impactedStops.enumerated()), id: \.element.id) { index, stop in
                                if index > 0 {
                                    Rectangle()
                                        .fill(DS.Color.ink.opacity(0.1))
                                        .frame(height: 1)
                                }

                                if let stopId = stop.id {
                                    Button {
                                        onOpenStop(stopId)
                                    } label: {
                                        stopRow(title: stop.name, subtitle: "Ouvrir l'arrêt")
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    stopRow(title: stop.name, subtitle: "Zone impactée", interactive: false)
                                }
                            }
                        }
                    }
                } else if !event.impactedStops.isEmpty {
                    sectionCard(title: "ARRÊTS / ZONES") {
                        VStack(spacing: 0) {
                            ForEach(Array(event.impactedStops.enumerated()), id: \.offset) { index, stop in
                                if index > 0 {
                                    Rectangle()
                                        .fill(DS.Color.ink.opacity(0.1))
                                        .frame(height: 1)
                                }
                                stopRow(title: stop, subtitle: "Zone impactée", interactive: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .presentationBackground(DS.Color.paper)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ÉVÉNEMENT BRUXELLES")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(DS.Color.inkMute)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)

                Text(event.venue ?? event.zoneLabel ?? "Bruxelles")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)

                if let eventDateLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                        Text(eventDateLabel)
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(1.1)
                    }
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 2)
                }
            }

            HStack(spacing: 8) {
                badge(event.phaseLabel ?? "À venir", tint: phaseTint)
                if let impact = event.impactLevel {
                    badge(impactLabel(impact), tint: impactTint(impact))
                }
            }

            if let notes = event.notesFr, !notes.isEmpty {
                Text(notes)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.horizontal, 4)

            content()
                .padding(12)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func stopRow(title: String, subtitle: String, interactive: Bool = true) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DS.Color.paper2)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: interactive ? "location.viewfinder" : "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(subtitle)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.inkMute)
                    .tracking(1.1)
            }

            Spacer()

            if interactive {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.vertical, 10)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(DS.Font.monoSmall.weight(.bold))
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tint)
            .overlay(
                Capsule()
                    .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var phaseTint: Color {
        switch event.phase {
        case "live":
            return Color(hex: "#FFD1B4")
        case "upcoming":
            return Color(hex: "#F3D58F")
        default:
            return DS.Color.paper2
        }
    }

    private func impactLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence probable"
        default:
            return "Affluence légère"
        }
    }

    private func impactTint(_ value: String) -> Color {
        switch value.lowercased() {
        case "high":
            return Color(hex: "#FFA17F")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
        }
    }

    private var eventDateLabel: String? {
        guard let startsAt = event.startsAt else { return nil }
        return Self.eventDateFormatter.string(from: startsAt)
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.timeZone = TimeZone(identifier: "Europe/Brussels")
        formatter.dateFormat = "EEE d MMM · HH:mm"
        return formatter
    }()
}

private struct HomeStopDetailSheet: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onReport: () -> Void

    private var effectiveStop: TransportStopSummaryDTO {
        stopDetail?.stop ?? stopSummary
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private var sheetDisplayedLines: [String] {
        var seen = Set<String>()
        let departureLines = stopDetail?.nextDepartures.map(\.line) ?? []
        let source = departureLines.isEmpty ? effectiveStop.lines : departureLines
        return source.compactMap { line in
            let normalized = Self.normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .sorted { l, r in
            if let li = Int(l), let ri = Int(r) { return li < ri }
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }

    private struct DepartureGroup: Identifiable {
        let id: String
        let line: String
        let destination: String?
        let primary: TransportDepartureDTO
        let secondary: TransportDepartureDTO?
    }

    private var sheetDepartureGroups: [DepartureGroup] {
        let all = (stopDetail?.nextDepartures ?? [])
            .sorted { $0.minutes < $1.minutes }
        var buckets: [String: [TransportDepartureDTO]] = [:]
        var order: [String] = []
        for dep in all {
            let key = "\(dep.line)|\(dep.destination ?? "")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(dep)
        }
        return order.compactMap { key in
            guard let arr = buckets[key], let first = arr.first else { return nil }
            return DepartureGroup(
                id: key,
                line: first.line,
                destination: first.destination,
                primary: first,
                secondary: arr.dropFirst().first
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(effectiveStop.name)
                            .font(.custom("DelaGothicOne-Regular", size: 20))
                            .foregroundStyle(.white)

                        Text(TransportViewAdapters.localizedSeverityLabel(
                            severity: stopDetail?.severity ?? "minor",
                            fallback: stopDetail?.label?.fr ?? "Arrêt surveillé"
                        ))
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(Color(hex: "#B5CFF8"))
                    }

                    Spacer()

                    Button(action: onReport) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Color(hex: "#F8E2B3"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Signaler à cet arrêt")
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Chargement des prochains passages…")
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }

                if !sheetDisplayedLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lignes")
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .foregroundStyle(Color.white.opacity(0.72))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sheetDisplayedLines, id: \.self) { line in
                                    Text(line)
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prochains passages")
                        .font(.custom("DelaGothicOne-Regular", size: 15))
                        .foregroundStyle(.white)

                    if !sheetDepartureGroups.isEmpty {
                        ForEach(sheetDepartureGroups) { group in
                            HStack(spacing: 10) {
                                Text(group.line)
                                    .font(.custom("Montserrat-SemiBold", size: 13))
                                    .foregroundStyle(.black)
                                    .frame(minWidth: 36, minHeight: 28)
                                    .background(Color(hex: "#B5CFF8"))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.destination ?? "Direction en cours")
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)

                                    let primaryText = "Dans \(group.primary.minutes) min"
                                    let secondaryText = group.secondary.map { " · puis \($0.minutes) min" } ?? ""
                                    if let delay = group.primary.delayMinutes, delay > 2 {
                                        Text("\(primaryText) · retard +\(delay) min\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(Color(hex: "#FF6B6B"))
                                    } else if group.primary.source == "scheduled" {
                                        Text("\(primaryText) · horaire théorique\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    } else {
                                        Text("\(primaryText)\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    } else if !isLoading {
                        Text("Aucun prochain passage fiable pour le moment.")
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if !nearbyVilloStations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Villo! à proximité")
                            .font(.custom("DelaGothicOne-Regular", size: 15))
                            .foregroundStyle(.white)

                        ForEach(Array(nearbyVilloStations.prefix(3)), id: \.station.id) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "bicycle")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 34, height: 34)
                                    .background(Color(hex: "#57E3B6"))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.station.displayName)
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text("\(item.station.availableBikes) vélos • \(item.station.availableBikeStands) places • \(item.distanceMeters)m")
                                        .font(.custom("Montserrat-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.72))
                                }

                                Spacer()

                                Text(item.station.statusLabel)
                                    .font(.custom("Montserrat-SemiBold", size: 11))
                                    .foregroundStyle(item.station.isOperational ? Color.black : .white)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(item.station.isOperational ? Color(hex: "#57E3B6") : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationBackground(Color(hex: "#111827"))
    }
}

private struct HomeStopDetailOverlay: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onReport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    Capsule()
                        .fill(DS.Color.border)
                        .frame(width: 42, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    HomeStopDetailSheet(
                        stopSummary: stopSummary,
                        stopDetail: stopDetail,
                        isLoading: isLoading,
                        nearbyVilloStations: nearbyVilloStations,
                        onReport: onReport
                    )
                    .frame(maxHeight: 520)
                }
                .background(DS.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(DS.Color.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 94)
        }
    }
}

