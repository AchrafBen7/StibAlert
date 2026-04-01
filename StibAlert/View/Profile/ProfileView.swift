import SwiftUI

struct ProfileView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionBetween) {
                ProfileHeader()

                ProfileIdentityCard()
                    .padding(.horizontal, DesignSystem.Spacing.md)

                ProfileStatsSection(items: ProfileMockData.stats)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Preferences",
                        subtitle: "Static settings blocks until the real account system returns."
                    )

                    VStack(spacing: 12) {
                        ForEach(ProfileMockData.preferences) { item in
                            ProfilePreferenceCard(item: item)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }

                VStack(spacing: 12) {
                    Button("Edit profile later") {}
                        .buttonStyle(SecondaryButton())

                    Button("Sign in later") {}
                        .buttonStyle(PrimaryButton())
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, 120)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ProfileHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(DesignSystem.Typography.pageTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text("A clean account shell, rebuilt without auth complexity for now.")
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

private struct ProfileIdentityCard: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accentSand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 74, height: 74)
                .overlay(
                    Text("AB")
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Achraf Benali")
                    .font(DesignSystem.Typography.sectionTitleSmall)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text("stibalert@mock.app")
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                StatusBadge(label: "Local mode", color: DesignSystem.Colors.accent)
            }

            Spacer()
        }
        .padding(18)
        .niosCard()
    }
}

private struct ProfileStatsSection: View {
    let items: [ProfileStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Overview",
                subtitle: "A few profile blocks rebuilt in the same NIOS rhythm."
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.tint.opacity(0.14))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: item.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(item.tint)
                            )

                        Text(item.title)
                            .font(DesignSystem.Typography.description)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)

                        Text(item.value)
                            .font(DesignSystem.Typography.cardTitle)
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .niosCard()
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct ProfilePreferenceCard: View {
    let item: ProfilePreference

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.tint.opacity(0.14))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text(item.subtitle)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Text(item.value)
                .font(DesignSystem.Typography.labelSemibold)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(16)
        .niosCard()
    }
}

private struct ProfileStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let tint: Color
}

private struct ProfilePreference: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let value: String
    let icon: String
    let tint: Color
}

private enum ProfileMockData {
    static let stats: [ProfileStat] = [
        .init(title: "Saved lines", value: "2", icon: "tram.fill", tint: DesignSystem.Colors.accent),
        .init(title: "Saved stops", value: "2", icon: "mappin.and.ellipse", tint: DesignSystem.Colors.accentSand),
        .init(title: "Draft reports", value: "1", icon: "square.and.pencil", tint: DesignSystem.Colors.warning),
        .init(title: "Backend mode", value: "Off", icon: "bolt.slash.fill", tint: DesignSystem.Colors.error)
    ]

    static let preferences: [ProfilePreference] = [
        .init(
            title: "Language",
            subtitle: "Current mock language state",
            value: "EN",
            icon: "globe",
            tint: DesignSystem.Colors.accent
        ),
        .init(
            title: "Notifications",
            subtitle: "Disabled while the backend is disconnected",
            value: "Off",
            icon: "bell.slash.fill",
            tint: DesignSystem.Colors.warning
        ),
        .init(
            title: "Storage",
            subtitle: "Local only, no remote sync",
            value: "Local",
            icon: "externaldrive.fill",
            tint: DesignSystem.Colors.accentSand
        )
    ]
}
