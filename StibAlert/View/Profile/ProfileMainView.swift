import SwiftUI

struct ProfileMainView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var stibi: StibiCenter
    @State private var isLoggingOut = false
    @State private var remoteActivities: [ProfileActivityItem] = []
    @State private var detailSignalement: SignalementDTO? = nil
    @State private var hasLoadedProfile = false
    @State private var profileLoadError: String? = nil

    var body: some View {
        if session.isGuest {
            GuestTabPlaceholder(
                reason: .profile,
                onSignIn: { nav.showAuthFlow = true },
                onSignUp: { nav.showAuthFlow = true }
            )
        } else {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 12)

                avatarSection
                    .padding(.top, 20)

                statsRow
                    .padding(.horizontal, 37)
                    .padding(.top, 24)

                if !earnedBadges.isEmpty {
                    badgesSection
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                }

                activityHeader
                    .padding(.horizontal, 21)
                    .padding(.top, 34)

                if let profileLoadError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#FF7A7A"))
                        Text(profileLoadError)
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Button {
                            self.profileLoadError = nil
                            Task { await loadProfileData() }
                        } label: {
                            Text("Réessayer")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .foregroundStyle(Color(hex: "#7CB2FF"))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 21)
                    .padding(.top, 14)
                }

                if hasLoadedProfile && activities.isEmpty && profileLoadError == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("Aucun signalement pour l'instant")
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 16) {
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
                    .padding(.horizontal, 21)
                    .padding(.top, 14)
                }

                if !activities.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            nav.currentPage = .signalements
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .medium))
                            Text("Voir tous vos signalements (\(remoteActivities.count))")
                                .font(.custom("Montserrat-Regular", size: 12))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 21)
                    .padding(.top, 13)
                }

                logoutButton
                    .padding(.horizontal, 21)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
            }
        }
        .background(AppTheme.Palette.screen)
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
            stibi.setCurrentScreen("profile_main")
            await loadProfileData()
            await loadStibiContext()
        }
        } // end else (guest check)
    }

    private var logoutButton: some View {
        Button(action: logout) {
            HStack(spacing: 8) {
                if isLoggingOut {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                    Text("Se déconnecter")
                        .font(.custom("Montserrat-SemiBold", size: 14))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .background(Color(hex: "#2A2A2A"))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color(hex: "#FF7A7A").opacity(0.5), lineWidth: 1)
            )
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
                        subtitle: "Stibi surveille cette ligne avec toi en priorité.",
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
        ZStack {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        nav.currentPage = .home
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        nav.currentPage = .home
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Profil")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6CC5C6"), Color(hex: "#F4A06E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 49, height: 49)
                .overlay(
                    Text(avatarInitial)
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(Color(hex: "#5B2F1C"))
                )

            Text(displayName)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(.white)

            Text(displayEmail)
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ProfileStatCard(title: "Signalements", value: reportCountText)
            ProfileReliabilityCard(value: reliabilityValue, definition: reliabilityDefinition)
        }
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Badges")
                    .font(.custom("DelaGothicOne-Regular", size: 20))
                    .foregroundStyle(.white)

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#D6C7A8"))

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(earnedBadges) { badge in
                        ProfileBadgeCard(badge: badge)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 10) {
            Text("Activité Récente")
                .font(.custom("DelaGothicOne-Regular", size: 20))
                .foregroundStyle(.white)

            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)

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

    private func loadStibiContext() async {
        guard AppConfig.isBackendEnabled else { return }
        do {
            let context = try await AssistantService.context()
            stibi.pushContextInsight(for: "profile_main", context: context)
        } catch {
            print("ProfileMain Stibi context failed: \(error.localizedDescription)")
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
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)
                Spacer()
                Circle()
                    .fill(Color(hex: "#7CB2FF"))
                    .frame(width: 12, height: 12)
            }

            Text(value)
                .font(.custom("DelaGothicOne-Regular", size: 32))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, minHeight: 101, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color(hex: "#7AB4FF"), lineWidth: 1)
        )
    }
}

private struct ProfileReliabilityCard: View {
    let value: String
    let definition: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fiabilité")
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)
                Spacer()
                Circle()
                    .fill(Color(hex: "#7CB2FF"))
                    .frame(width: 12, height: 12)
            }

            Text(value)
                .font(.custom("DelaGothicOne-Regular", size: 32))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            Text(definition)
                .font(.custom("Montserrat-Regular", size: 10))
                .foregroundStyle(.black.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, minHeight: 101, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color(hex: "#7AB4FF"), lineWidth: 1)
        )
    }
}

private struct ProfileActivityCard: View {
    let activity: ProfileActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                Text(activity.line)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(activity.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(activity.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(activity.title)
                            .font(.custom("DelaGothicOne-Regular", size: 20))
                            .foregroundStyle(.black)

                        Text(activity.when)
                            .font(.custom("DelaGothicOne-Regular", size: 11))
                            .foregroundStyle(.black)
                    }

                    Text(activity.description)
                        .font(.custom("Montserrat-Regular", size: 13))
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(activity.location, systemImage: "clock.arrow.circlepath")
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .padding(.top, 12)

                    Label("\(activity.confirmations) confirmations", systemImage: "person.2")
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .padding(.top, 6)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(activity.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    let background: Color
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
            background: background(for: signalement.typeProbleme),
            signalement: signalement
        )
    }

    private static func relativeTimestamp(from date: Date?) -> String {
        guard let date else { return "Il y a un instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private static func background(for type: String) -> Color {
        switch type {
        case "Accident": return Color(hex: "#FFB3B7")
        case "Retard": return Color(hex: "#FFC98D")
        case "Panne": return Color(hex: "#BBDCFF")
        case "Propreté": return Color(hex: "#CFF8E7")
        default: return Color(hex: "#FFC98D")
        }
    }

    private static func lineColor(for line: String) -> Color {
        switch line {
        case "1", "5", "10": return Color(hex: "#8F4199")
        case "7": return Color(hex: "#FFDC01")
        case "46": return Color(hex: "#F29DC3")
        default: return Color(hex: "#8F4199")
        }
    }

    private static func lineTextColor(for line: String) -> Color {
        line == "7" ? .black : .white
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
                .font(.custom("DelaGothicOne-Regular", size: 14))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(badge.subtitle)
                .font(.custom("Montserrat-Regular", size: 11))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 188, alignment: .leading)
        .background(Color(hex: "#252525"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(badge.accent.opacity(0.42), lineWidth: 1)
        )
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

