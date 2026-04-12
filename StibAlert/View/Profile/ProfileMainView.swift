import SwiftUI

struct ProfileMainView: View {
    @EnvironmentObject private var nav: AppNavigation

    var body: some View {
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
                ForEach(ProfileMainMockData.activities) { activity in
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

            Spacer()
        }
        .background(Color(hex: "#1B1B1B"))
        .toolbar(.hidden, for: .navigationBar)
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
                    Text("A")
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(Color(hex: "#5B2F1C"))
                )

            Text("Achraf Benali")
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(.white)

            Text("Achrafb768@gmail.com")
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ProfileStatCard(title: "Signalements", value: "12")
            ProfileReliabilityCard(value: "4.8")
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
                            .font(.custom("Darumadrop One", size: 11))
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
}

private enum ProfileMainMockData {
    static let activities: [ProfileActivityItem] = [
        .init(line: "7", lineColor: Color(hex: "#FFDC01"), lineTextColor: .black, title: "Retard", when: "Il y a 2 jours", description: "Panne technique sur la ligne, service\ntemporairement interrompu", location: "Heysel", confirmations: 48, background: Color(hex: "#FFC98D")),
        .init(line: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, title: "Accident", when: "Il y a 3 jours", description: "Panne technique sur la ligne, service\ntemporairement interrompu", location: "Heembeek", confirmations: 48, background: Color(hex: "#FFB3B7"))
    ]
}
