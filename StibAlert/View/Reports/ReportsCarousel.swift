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

            Text("\(items.count) ouvert\(items.count > 1 ? "s" : "")")
                .font(DS.Font.monoSmall.weight(.semibold))
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
        .frame(height: 278)
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

struct NetworkIssueCarouselCard: View {
    let item: NetworkIssueCarouselItem
    let itemCount: Int
    let activeIndex: Int

    private var severityLabel: String {
        let value = item.keyword.lowercased()
        switch value {
        case _ where value.contains("interrompu") || value.contains("accident"):
            return "Impact fort"
        case _ where value.contains("travaux") || value.contains("dévi"):
            return "À anticiper"
        default:
            return "À surveiller"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("reports-metro-stib")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.64),
                    .black.opacity(0.22),
                    .black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    item.tint.opacity(0.58),
                    .black.opacity(0.22),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 9) {
                    Circle()
                        .fill(item.tint)
                        .frame(width: 10, height: 10)
                        .shadow(color: item.tint.opacity(0.7), radius: 9)

                    Text("AUTOUR DE TOI")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.88))

                    Spacer()

                    Text("STIB-MIVB")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ReportsGlassBadge(title: item.sourceLabel, icon: "checkmark.seal.fill")
                        ReportsGlassBadge(title: severityLabel, icon: "exclamationmark.triangle.fill")
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(item.keyword)
                            .font(DS.Font.displayH1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text("\(activeIndex + 1)/\(max(itemCount, 1))")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Text(item.detail)
                        .font(DS.Font.bodySmall.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 8) {
                    if !item.lines.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(item.lines.prefix(4)), id: \.self) { line in
                                LineBadge(line: line, size: .lg)
                            }
                            if item.lines.count > 4 {
                                Text("+\(item.lines.count - 4)")
                                    .font(DS.Font.monoSmall.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }
                    }

                    if let location = item.location, !location.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10, weight: .bold))
                            Text(location)
                                .lineLimit(1)
                        }
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.16))
                        .clipShape(Circle())
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 212, maxHeight: 212)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(.white.opacity(0.46), lineWidth: 1)
                .padding(1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(color: item.tint.opacity(0.22), radius: 20, x: 0, y: 12)
        .accessibilityLabel("\(item.keyword). \(item.detail)")
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
                .font(DS.Font.monoSmall.weight(.bold))
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
