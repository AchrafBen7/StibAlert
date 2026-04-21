import SwiftUI

struct ProfileMainView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @State private var isLoggingOut = false
    @State private var remoteActivities: [ProfileActivityItem] = []

    var body: some View {
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

                activityHeader
                    .padding(.horizontal, 21)
                    .padding(.top, 34)

                VStack(spacing: 16) {
                    ForEach(activities) { activity in
                        ProfileActivityCard(activity: activity)
                    }
                }
                .padding(.horizontal, 21)
                .padding(.top, 14)

                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Voir tout vos signalements (5)")
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

                logoutButton
                    .padding(.horizontal, 21)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(hex: "#1B1B1B"))
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadProfileData() }
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
    private var activities: [ProfileActivityItem] {
        remoteActivities.isEmpty ? ProfileMainMockData.activities : remoteActivities
    }
    private var reportCountText: String { "\(activities.count)" }
    private var reliabilityValue: String {
        guard !remoteActivities.isEmpty else { return "4.8" }
        return String(format: "%.1f", min(5.0, 3.8 + Double(remoteActivities.count) * 0.15))
    }
    private var avatarInitial: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
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
            ProfileReliabilityCard(value: reliabilityValue)
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
        guard AppConfig.isBackendEnabled else { return }
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
        } catch {
            print("Profile data load failed: \(error.localizedDescription)")
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

            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: index < 4 ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(index < 4 ? Color(hex: "#FFD400") : Color(hex: "#B8BBC3"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
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
    let id = UUID()
    let line: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let when: String
    let description: String
    let location: String
    let confirmations: Int
    let background: Color

    static func from(signalement: SignalementDTO) -> ProfileActivityItem {
        .init(
            line: signalement.ligne,
            lineColor: lineColor(for: signalement.ligne),
            lineTextColor: lineTextColor(for: signalement.ligne),
            title: signalement.typeProbleme,
            when: relativeTimestamp(from: signalement.dateSignalement),
            description: signalement.description,
            location: signalement.arretId?.id ?? "Arrêt",
            confirmations: signalement.votesPositifs ?? 0,
            background: background(for: signalement.typeProbleme)
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

private enum ProfileMainMockData {
    static let activities: [ProfileActivityItem] = [
        .init(line: "7", lineColor: Color(hex: "#FFDC01"), lineTextColor: .black, title: "Retard", when: "Il y a 2 jours", description: "Panne technique sur la ligne, service\ntemporairement interrompu", location: "Heysel", confirmations: 48, background: Color(hex: "#FFC98D")),
        .init(line: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, title: "Accident", when: "Il y a 3 jours", description: "Panne technique sur la ligne, service\ntemporairement interrompu", location: "Heembeek", confirmations: 48, background: Color(hex: "#FFB3B7"))
    ]
}
