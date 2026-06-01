import SwiftUI

struct HomeBottomChromeOverlay: View {
    let currentPage: AppPage
    let shouldShowPulseBar: Bool
    let shouldShowTabBar: Bool
    let totalActiveSignalementsCount: Int
    let favoriteAffectedCount: Int
    let highlightedEventCount: Int
    let refreshedAt: Date?
    let onOpenReports: () -> Void
    let onOpenReportSheet: () -> Void
    let onOpenVoice: () -> Void
    let onOpenStibAI: () -> Void
    let onRecenter: () -> Void
    let onSelectTab: (AppTab) -> Void
    // I4 — Inline persistant pour les invités. Non dismissible (l'utilisateur
    // peut juste cliquer "Crée un compte"). Affiché juste au-dessus de la
    // tab bar pour ne pas couvrir la carte.
    var isGuest: Bool = false
    var onCreateAccount: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowPulseBar {
                // Layout: [Mic] far-left  ........  [AI]  [ Location / + ].
                // Le bouton "ma position" est désormais EMPILÉ juste au-dessus
                // du bouton "+" (même colonne, bord droit). Mic reste à gauche,
                // AI à gauche de la colonne +. alignment .bottom pour que Mic
                // et AI s'alignent sur le `+`.
                HStack(alignment: .bottom, spacing: 10) {
                    MapVoiceFloatingButton(action: onOpenVoice)
                    Spacer(minLength: 8)
                    STIBAIFloatingButton(action: onOpenStibAI)
                        .padding(.trailing, 6) // gap supplémentaire vers la colonne `+`
                    VStack(spacing: 10) {
                        LocationFloatingButton(action: onRecenter)
                        HomeReportFloatingButton(action: onOpenReportSheet)
                    }
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            if isGuest {
                guestBanner
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if shouldShowTabBar {
                AppTabBar(selection: Binding(
                    get: { AppTab.from(page: currentPage) },
                    set: onSelectTab
                ))
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Barre de navigation")
            }
        }
        .padding(.bottom, 6)
        .padding(.bottom, 8) // iOS 17.5+ safe area bottom adjustment
        .zLayer(.bottomChrome)
    }

    private var guestBanner: some View {
        Button(action: onCreateAccount) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mode invité")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                    Text("Crée un compte pour favoris + alertes push")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Créer")
                    .font(.system(size: 11.5, weight: .black))
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: DS.Color.ink.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .accessibilityLabel("Mode invité — créer un compte pour favoris et alertes")
    }
}

private struct HomePulseBar: View {
    let totalActive: Int
    let favoriteAffectedCount: Int
    let eventCount: Int
    let refreshedAt: Date?
    let onOpenReports: () -> Void

    private var titleText: String {
        if favoriteAffectedCount > 0 {
            return favoriteAffectedCount == 1
                ? "1 incident sur tes lignes"
                : "\(favoriteAffectedCount) incidents sur tes lignes"
        }
        return totalActive == 1 ? "1 signalement actif" : "\(totalActive) signalements actifs"
    }

    var body: some View {
        Button(action: onOpenReports) {
            HStack(spacing: 10) {
                Circle()
                    .fill(favoriteAffectedCount > 0 ? DS.Color.statusMajor : DS.Color.statusMinor)
                    .frame(width: 10, height: 10)

                Text(titleText)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.Color.paper.opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(DS.Shadow.overlay)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HomeReportFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(width: 48, height: 48)
                .background(DS.Color.primary)
                // Border noir retiré : il alourdissait le bouton « + » et
                // détonnait. L'ombre flottante suffit à le détacher du fond.
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Signaler")
    }
}

struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .rotationEffect(.degrees(18))
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.paper.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recentrer la carte")
        .accessibilityHint("Replace la carte sur votre position")
    }
}
