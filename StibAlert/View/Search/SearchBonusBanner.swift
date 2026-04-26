import SwiftUI

struct SearchBonusBanner: View {
    @AppStorage("searchBonusBannerDismissed") private var isDismissed: Bool = false
    @EnvironmentObject private var nav: AppNavigation

    var body: some View {
        if !isDismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.brand)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.Palette.brand.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Itinéraire — bonus expérimental")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                    Text("StibAlert est d'abord une carte live de signalements communautaires. Cet itinéraire est un extra.")
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                nav.currentPage = .home
                            }
                        } label: {
                            Text("Voir la carte live")
                                .font(AppTheme.Fonts.captionStrong)
                                .foregroundStyle(AppTheme.Palette.brand)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDismissed = true
                            }
                        } label: {
                            Text("Ne plus afficher")
                                .font(AppTheme.Fonts.caption)
                                .foregroundStyle(AppTheme.Palette.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Palette.screenElevated.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(AppTheme.Palette.border, lineWidth: 1)
            )
        }
    }
}
