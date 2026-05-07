import SwiftUI

struct ProfileMainView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @State private var isLoggingOut = false
    @State private var remoteActivities: [ProfileActivityItem] = []
    @State private var detailSignalement: SignalementDTO? = nil
    @State private var hasLoadedProfile = false
    @State private var profileLoadError: String? = nil

    var body: some View {
        if session.isGuest {
            GuestTabPlaceholder(
                reason: .profile,
                onSignIn: {
                    nav.authInitialRoute = .signIn
                    nav.showAuthFlow = true
                },
                onSignUp: {
                    nav.authInitialRoute = .signUp
                    nav.showAuthFlow = true
                }
            )
        } else {
            ZStack {
                DS.Color.paper.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        profileHero
                            .padding(.horizontal, 20)
                            .padding(.top, 22)

                        statsRow
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        activityHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 26)

                        if let profileLoadError {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DS.Color.statusMajor)
                                Text(profileLoadError)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Spacer()
                                Button {
                                    self.profileLoadError = nil
                                    Task { await loadProfileData() }
                                } label: {
                                    Text("Réessayer")
                                        .font(DS.Font.monoSmall)
                                        .foregroundStyle(DS.Color.ink)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(DS.Color.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DS.Color.statusMajor.opacity(0.35), lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        }

                        if hasLoadedProfile && activities.isEmpty && profileLoadError == nil {
                            VStack(spacing: 10) {
                                Image(systemName: "tray")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(DS.Color.inkMute)
                                Text("Aucun signalement pour l'instant")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(activities) { activity in
                                    Button {
                                        guard let signalement = activity.signalement else { return }
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        detailSignalement = signalement
                                    } label: {
                                        ProfileActivityCard(activity: activity)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(activity.signalement == nil)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        }

                        if !activities.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    nav.currentPage = .reports
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Voir tous vos signalements")
                                        .font(.system(size: 12.5, weight: .bold))
                                }
                                .foregroundStyle(DS.Color.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(DS.Color.paper)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(DS.Color.ink.opacity(0.18), lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        }

                        logoutButton
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                            .padding(.bottom, 96)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $detailSignalement) { signalement in
                SignalementDetailView(
                    signalement: signalement,
                    onDismiss: { detailSignalement = nil }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task {
                await loadProfileData()
            }
        } // end else (guest check)
    }

    private var logoutButton: some View {
        Button(action: logout) {
            HStack(spacing: 10) {
                if isLoggingOut {
                    ProgressView().tint(DS.Color.paper)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                    Text("Se déconnecter")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(DS.Color.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(DS.Color.ink)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoggingOut)
    }

    private func logout() {
        isLoggingOut = true
        Task {
            await session.deconnexion()
            isLoggingOut = false
        }
    }

    private var displayName: String { session.currentUser?.nom ?? "Invité" }
    private var displayEmail: String { session.currentUser?.email ?? "" }
    private var activities: [ProfileActivityItem] { remoteActivities }
    private var reportCountText: String { "\(activities.count)" }
    private var reliabilityValue: String {
        guard !remoteActivities.isEmpty else { return "—" }
        let confirmed = remoteActivities.filter { $0.confirmations > 0 }.count
        let ratio = (Double(confirmed) / Double(remoteActivities.count)) * 100
        return "\(Int(ratio.rounded()))%"
    }
    private var reliabilityDefinition: String {
        guard !remoteActivities.isEmpty else {
            return "Ajoute des signalements pour voir leur part confirmée par la communauté."
        }
        return "Part de tes signalements récents confirmés au moins une fois par la communauté."
    }
    private var avatarInitial: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
    private var reliabilityRatio: Double? {
        guard !remoteActivities.isEmpty else { return nil }
        let confirmed = remoteActivities.filter { $0.confirmations > 0 }.count
        return Double(confirmed) / Double(remoteActivities.count)
    }
    private var earnedBadges: [ProfileBadgeItem] {
        var badges: [ProfileBadgeItem] = []
        let favoriteLines = session.currentUser?.favoriteLines ?? []

        if remoteActivities.count >= 10 {
            badges.append(
                .init(
                    title: "10 signalements validés",
                    subtitle: "Tu aides déjà la communauté à voir plus clair.",
                    accent: Color(hex: "#D6C7A8"),
                    icon: "checkmark.seal.fill"
                )
            )
        }

        if let topLine = favoriteLines.first ?? remoteActivities.mostFrequentLine {
            let lineCount = remoteActivities.filter { $0.line == topLine }.count
            if lineCount >= 3 || favoriteLines.contains(topLine) {
                badges.append(
                    .init(
                        title: "Guardian de la ligne \(topLine)",
                        subtitle: "Tu surveilles cette ligne en priorité.",
                        accent: Color(hex: "#7CB2FF"),
                        icon: "tram.fill"
                    )
                )
            }
        }

        if let reliabilityRatio, reliabilityRatio >= 0.7 {
            badges.append(
                .init(
                    title: "Bruxellois fiable",
                    subtitle: "La majorité de tes signalements sont confirmés ensuite.",
                    accent: Color(hex: "#73D39C"),
                    icon: "building.2.crop.circle.fill"
                )
            )
        }

        return Array(badges.prefix(3))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMPTE STIBALERT")
                .font(DS.Font.monoSmall)
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)
            Text("Profil")
                .font(DS.Font.displayH1)
                .foregroundStyle(DS.Color.ink)
        }
    }

    private var profileHero: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6CC5C6"), Color(hex: "#F4A06E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 66, height: 66)
                .overlay(
                    Text(avatarInitial)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color(hex: "#5B2F1C"))
                )

            Text(displayName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.Color.ink)

            if !displayEmail.isEmpty {
                Text(displayEmail)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.inkMute)
            }

            Text("MEMBRE STIBALERT")
                .font(DS.Font.monoSmall)
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            ProfileStatCard(title: "Signalements", value: reportCountText)
            ProfileReliabilityCard(value: reliabilityValue, definition: reliabilityDefinition)
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 10) {
            Text("Activité Récente")
                .font(DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)

            Spacer()
        }
    }

    private func loadProfileData() async {
        guard AppConfig.isBackendEnabled else { hasLoadedProfile = true; return }
        defer { hasLoadedProfile = true }
        do {
            let user = try await UtilisateurService.me()
            session.applyCurrentUserUpdate(user)
            var page = 1
            var totalPages = 1
            var collected: [SignalementDTO] = []

            repeat {
                let response = try await SignalementService.liste(page: page)
                collected.append(contentsOf: response.signalements.filter { $0.utilisateurId == user.id })
                totalPages = response.pagination?.totalPages ?? 1
                page += 1
            } while collected.count < 5 && page <= totalPages

            remoteActivities = Array(collected.prefix(5)).map(ProfileActivityItem.from(signalement:))
            profileLoadError = nil
        } catch {
            profileLoadError = "Impossible de charger vos signalements."
        }
    }

}

private struct ProfileStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Circle()
                    .fill(DS.Color.primary.opacity(0.75))
                    .frame(width: 10, height: 10)
            }

            Text(value)
                .font(DS.Font.displayH1)
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileReliabilityCard: View {
    let value: String
    let definition: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fiabilité")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Circle()
                    .fill(DS.Color.primary.opacity(0.75))
                    .frame(width: 10, height: 10)
            }

            Text(value)
                .font(DS.Font.displayH1)
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            Text(definition)
                .font(.system(size: 10.5))
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileActivityCard: View {
    let activity: ProfileActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                Text(activity.line)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(activity.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(activity.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(activity.title)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(DS.Color.ink)

                        Text(activity.when)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    Text(activity.description)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.ink)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(activity.location, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.top, 12)

                    Label("\(activity.confirmations) confirmations", systemImage: "person.2")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.top, 6)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileActivityItem: Identifiable {
    let id: String
    let line: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let when: String
    let description: String
    let location: String
    let confirmations: Int
    let signalement: SignalementDTO?

    static func from(signalement: SignalementDTO) -> ProfileActivityItem {
        .init(
            id: signalement.id,
            line: signalement.ligne,
            lineColor: lineColor(for: signalement.ligne),
            lineTextColor: lineTextColor(for: signalement.ligne),
            title: signalement.typeProbleme,
            when: relativeTimestamp(from: signalement.dateSignalement),
            description: signalement.description,
            location: {
                if case .populated(let arret) = signalement.arretId { return arret.nom }
                return signalement.arretId?.id ?? "Arrêt"
            }(),
            confirmations: signalement.community?.confirmations ?? 0,
            signalement: signalement
        )
    }

    private static func relativeTimestamp(from date: Date?) -> String {
        guard let date else { return "Il y a un instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
    private static func lineColor(for line: String) -> Color {
        TransitLinePalette.fill(for: line)
    }

    private static func lineTextColor(for line: String) -> Color {
        TransitLinePalette.foreground(for: line)
    }
}

private struct ProfileBadgeItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let accent: Color
    let icon: String
}

private struct ProfileBadgeCard: View {
    let badge: ProfileBadgeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(badge.accent.opacity(0.18))
                    .frame(width: 34, height: 34)

                Image(systemName: badge.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(badge.accent)
            }

            Text(badge.title)
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(badge.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DS.Color.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 188, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension Array where Element == ProfileActivityItem {
    var mostFrequentLine: String? {
        let counts = reduce(into: [String: Int]()) { partialResult, item in
            partialResult[item.line, default: 0] += 1
        }
        return counts.max(by: { lhs, rhs in lhs.value < rhs.value })?.key
    }
}
