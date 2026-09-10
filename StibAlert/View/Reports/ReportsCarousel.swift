import SwiftUI

struct ReportsCarousel: View {
    let items: [NetworkIssueCarouselItem]
    @Binding var activeIndex: Int
    let reduceMotion: Bool
    let stopContext: (NetworkIssueCarouselItem) -> (stops: [String], disruptedIndices: Set<Int>, disruptedName: String?)
    let onEnsureLineDetail: (String) -> Void
    let onOpenSummary: () -> Void

    private let timer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dossierPager
            pageIndicators
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ReportsPulsingDot(color: DS.Color.statusMajor)
                Text("DOSSIER EN COURS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            Text(AppLocalizer.format("plural.dispatches", defaultValue: "%lld dépêches", items.count))
                .font(DS.Font.labelSmall.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)
        }
    }

    private var dossierPager: some View {
        TabView(selection: $activeIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let context = stopContext(item)
                Button(action: onOpenSummary) {
                    EditorialDossierCard(
                        item: item,
                        index: index + 1,
                        total: items.count,
                        stops: context.stops,
                        disruptedIndices: context.disruptedIndices,
                        disruptedStopName: context.disruptedName
                    )
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Shrunk from 278 → 196: user wanted the dossier carousel kept but
        // smaller so it doesn't dominate the screen; the new line-status
        // grid below now takes the visual lead.
        .frame(height: 196)
        .onAppear(perform: ensureVisibleLineDetails)
        .onChange(of: items.flatMap(\.lines).joined(separator: "|")) { _, _ in
            ensureVisibleLineDetails()
        }
        .onReceive(timer) { _ in
            guard !reduceMotion, items.count > 1 else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                activeIndex = (activeIndex + 1) % items.count
            }
        }
        .onChange(of: items.count) { _, count in
            if activeIndex >= count {
                activeIndex = 0
            }
        }
    }

    @ViewBuilder
    private var pageIndicators: some View {
        if items.count > 1 {
            HStack(spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                            activeIndex = index
                        }
                    } label: {
                        Rectangle()
                            .fill(index == activeIndex ? DS.Color.ink : DS.Color.ink.opacity(0.25))
                            .frame(width: index == activeIndex ? 28 : 8, height: 3)
                            .animation(.easeInOut(duration: 0.2), value: activeIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func ensureVisibleLineDetails() {
        for line in items.flatMap(\.lines).prefix(8) {
            onEnsureLineDetail(line)
        }
    }
}


private struct ReportsGlassBadge: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(DS.Font.labelSmall.weight(.bold))
                .tracking(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.white.opacity(0.16))
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}
