import SwiftUI

struct ReportView: View {
    @State private var selectedKind: ReportKind = .delay
    @State private var selectedLine: ReportLine = ReportMockData.lines[0]
    @State private var selectedStop: ReportStop = ReportMockData.stops[0]
    @State private var note = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionBetween) {
                ReportHeader()

                ReportKindSection(selectedKind: $selectedKind)

                ReportRouteSection(
                    selectedLine: $selectedLine,
                    selectedStop: $selectedStop
                )

                ReportMediaSection()

                ReportNoteSection(note: $note)

                ReportPreviewSection(
                    preview: .init(
                        line: selectedLine.code,
                        title: selectedKind.previewTitle,
                        subtitle: "\(selectedStop.name) • Mock preview before the backend comes back.",
                        status: "Draft",
                        statusColor: DesignSystem.Colors.accent,
                        tint: selectedLine.tint,
                        icon: selectedKind.icon,
                        time: "Ready to submit"
                    )
                )

                VStack(spacing: 12) {
                    Button("Publish later") {}
                        .buttonStyle(SecondaryButton())

                    Button("Create report") {}
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

private struct ReportHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report")
                .font(DesignSystem.Typography.pageTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text("A stripped-back reporting flow rebuilt on the NIOS base, with only instant mock interactions.")
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

private struct ReportKindSection: View {
    @Binding var selectedKind: ReportKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Issue type",
                subtitle: "Choose the kind of disruption you want to report."
            )

            VStack(spacing: 12) {
                ForEach(ReportKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(kind.tint.opacity(0.14))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: kind.icon)
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(kind.tint)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(DesignSystem.Typography.bodySemibold)
                                    .foregroundStyle(DesignSystem.Colors.primaryText)

                                Text(kind.subtitle)
                                    .font(DesignSystem.Typography.description)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                            }

                            Spacer()

                            Image(systemName: selectedKind == kind ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(
                                    selectedKind == kind
                                    ? DesignSystem.Colors.accent
                                    : DesignSystem.Colors.borderStrong
                                )
                        }
                        .padding(16)
                        .niosCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct ReportRouteSection: View {
    @Binding var selectedLine: ReportLine
    @Binding var selectedStop: ReportStop

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Line and stop",
                subtitle: "Keep the flow local for now, but preserve the right structure."
            )

            VStack(spacing: 12) {
                ReportSelectionCard(
                    title: "Line",
                    value: selectedLine.code,
                    subtitle: selectedLine.title,
                    tint: selectedLine.tint,
                    icon: "tram.fill"
                )

                ReportSelectionCard(
                    title: "Stop",
                    value: selectedStop.name,
                    subtitle: selectedStop.subtitle,
                    tint: DesignSystem.Colors.accentSand,
                    icon: "mappin.and.ellipse"
                )
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct ReportSelectionCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(DesignSystem.Typography.labelSemibold)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                Text(value)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text(subtitle)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(16)
        .niosCard()
    }
}

private struct ReportMediaSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Photo",
                subtitle: "Keep the media area simple until the real upload flow returns."
            )

            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.accentSoft,
                                Color.white
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent)

                            Text("No media selected")
                                .font(DesignSystem.Typography.bodySemibold)
                                .foregroundStyle(DesignSystem.Colors.primaryText)

                            Text("A lightweight placeholder for the photo pipeline.")
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                        }
                    )

                Button("Add a photo") {}
                    .buttonStyle(AppleHoverButton(fontSize: 15))
                    .frame(height: 52)
            }
            .padding(16)
            .niosCard()
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct ReportNoteSection: View {
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Notes",
                subtitle: "Short context, no heavy validation yet."
            )

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $note)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .frame(minHeight: 132)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("Describe what happened near the stop or onboard.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.secondaryText.opacity(0.8))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Text("Draft only")
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    Spacer()

                    Text("\(note.count)/180")
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }
            .padding(16)
            .niosCard()
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct ReportPreviewSection: View {
    let preview: MockReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Preview",
                subtitle: "This is how the draft card can feel in the rebuilt UI."
            )

            ReportCard(report: preview)
                .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private enum ReportKind: CaseIterable, Identifiable {
    case delay
    case crowding
    case blocked
    case incident

    var id: Self { self }

    var title: String {
        switch self {
        case .delay: return "Delay"
        case .crowding: return "Crowding"
        case .blocked: return "Blocked service"
        case .incident: return "Safety issue"
        }
    }

    var subtitle: String {
        switch self {
        case .delay: return "The line is running behind schedule."
        case .crowding: return "Vehicle or platform is unusually packed."
        case .blocked: return "Line interruption or stop not being served."
        case .incident: return "Something requires extra caution on site."
        }
    }

    var icon: String {
        switch self {
        case .delay: return "clock.badge.exclamationmark"
        case .crowding: return "person.3.sequence.fill"
        case .blocked: return "slash.circle.fill"
        case .incident: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .delay: return DesignSystem.Colors.accent
        case .crowding: return DesignSystem.Colors.accentSand
        case .blocked: return DesignSystem.Colors.warning
        case .incident: return DesignSystem.Colors.error
        }
    }

    var previewTitle: String {
        switch self {
        case .delay: return "Delay reported"
        case .crowding: return "Crowding reported"
        case .blocked: return "Service interruption reported"
        case .incident: return "Safety concern reported"
        }
    }
}

private struct ReportLine: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let title: String
    let tint: Color
}

private struct ReportStop: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
}

private enum ReportMockData {
    static let lines: [ReportLine] = [
        .init(code: "M6", title: "Roi Baudouin -> Elisabeth", tint: Color(hex: "#1AA35F")),
        .init(code: "T7", title: "Vanderkindere -> Heysel", tint: Color(hex: "#D7263D")),
        .init(code: "B95", title: "Grand-Place -> Wiener", tint: Color(hex: "#4557A1"))
    ]

    static let stops: [ReportStop] = [
        .init(name: "Simonis", subtitle: "Metro and tram interchange"),
        .init(name: "Rogier", subtitle: "Central retail and metro node"),
        .init(name: "Arts-Loi", subtitle: "Office district interchange")
    ]
}
