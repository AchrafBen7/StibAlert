import SwiftUI

struct ReportCard: View {
    let report: MockReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(report.line)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(report.tint)
                            .clipShape(Capsule())

                        StatusBadge(label: report.status, color: report.statusColor)
                    }

                    Text(report.title)
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(report.subtitle)
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(report.tint.opacity(0.12))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Image(systemName: report.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(report.tint)
                    )
            }

            HStack {
                Label(report.time, systemImage: "clock")
                    .font(DesignSystem.Typography.footnote)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                Spacer()

                Button("Details") {}
                    .buttonStyle(AppleHoverButton(fontSize: 14))
                    .frame(width: 112)
            }
        }
        .padding(16)
        .niosCard()
    }
}

struct MockReport: Identifiable {
    let id = UUID()
    let line: String
    let title: String
    let subtitle: String
    let status: String
    let statusColor: Color
    let tint: Color
    let icon: String
    let time: String
}
