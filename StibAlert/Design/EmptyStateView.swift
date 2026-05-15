import SwiftUI

struct EmptyStateView: View {
    let iconSystemName: String
    let title: String
    let message: String
    var iconTint: Color = DS.Color.inkMute
    var iconWeight: Font.Weight = .light
    var iconSize: CGFloat = 36
    var cta: CTA? = nil

    struct CTA {
        let label: String
        let action: () -> Void
    }

    init(
        iconSystemName: String,
        title: String,
        body: String,
        iconTint: Color = DS.Color.inkMute,
        iconWeight: Font.Weight = .light,
        iconSize: CGFloat = 36,
        cta: CTA? = nil
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.message = body
        self.iconTint = iconTint
        self.iconWeight = iconWeight
        self.iconSize = iconSize
        self.cta = cta
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconSystemName)
                .font(.system(size: iconSize, weight: iconWeight))
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)

            Text(title)
                .font(DS.Font.displayH3)
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            if let cta {
                Button(action: cta.action) {
                    Text(cta.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(DS.Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.ink, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
