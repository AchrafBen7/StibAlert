import SwiftUI

/// Mise en forme des durées de trajet.
///
/// Au-delà d'une heure, « 74 min » demande un calcul mental alors qu'on parle
/// naturellement en heures. On bascule donc à 60 minutes : « 1 h 14 ».
enum RouteDurationFormat {
    static func compact(_ minutes: Int) -> String {
        guard minutes >= 60 else {
            return AppLocalizer.format("duration.minutes", defaultValue: "%lld min", minutes)
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return AppLocalizer.format("duration.hours", defaultValue: "%lld h", hours)
        }
        return AppLocalizer.format("duration.hours_minutes", defaultValue: "%1$lld h %2$02lld", hours, rest)
    }
}

/// Disposition en flux : les éléments passent à la ligne suivante quand ils ne
/// tiennent plus, au lieu d'être tronqués.
///
/// La bande des correspondances était un `HStack` en `lineLimit(1)` : sur un
/// trajet à trois correspondances, les derniers badges étaient coupés en plein
/// milieu (« R2 », « 8: ») et devenaient illisibles. C'est justement sur les
/// longs trajets qu'on a le plus besoin de les lire.
struct RouteFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        maxLineWidth = max(maxLineWidth, lineWidth)
        return CGSize(width: min(maxLineWidth, maxWidth), height: totalHeight + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y + (lineHeight - size.height) / 2 + size.height / 2),
                anchor: .leading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
