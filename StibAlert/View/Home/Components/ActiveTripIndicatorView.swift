import SwiftUI

/// Badge persistant en haut de la carte quand un trip est en cours. Avant ce
/// composant, l'utilisateur lançait un itinéraire, entendait Mobi parler,
/// mais ne voyait AUCUNE indication visuelle de "trip en cours" — la carte
/// ressemblait à un état de repos.
///
/// 2 modes :
/// - **compact** : pulse vert + ligne + destination + durée
/// - **expanded** : ajoute la dernière annonce + barre de progress + bouton
///   "Annuler le trajet"
struct ActiveTripIndicatorView: View {
    @ObservedObject var tracker: ActiveTripTracker
    let onCancel: () -> Void

    @State private var isExpanded = false
    @State private var pulse = false

    var body: some View {
        if tracker.isActive, let summary = tracker.summary {
            content(summary: summary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { pulse = true }
                .onChange(of: tracker.isActive) { _, active in
                    if !active { withAnimation { isExpanded = false } }
                }
        }
    }

    @ViewBuilder
    private func content(summary: ActiveTripTracker.ActiveTripSummary) -> some View {
        VStack(spacing: 0) {
            // Bandeau compact (toujours visible)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // Pulse vert "trip actif"
                    ZStack {
                        Circle()
                            .fill(DS.Color.statusOK.opacity(0.25))
                            .frame(width: 22, height: 22)
                            .scaleEffect(pulse ? 1.4 : 0.95)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                        Circle()
                            .fill(DS.Color.statusOK)
                            .frame(width: 10, height: 10)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("En route vers \(summary.destinationName)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let firstLine = summary.firstLineCode {
                                Text("Via ligne \(firstLine)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Color.inkMute)
                                Text("·")
                                    .foregroundStyle(DS.Color.inkMute.opacity(0.5))
                            }
                            Text("\(summary.totalMinutes) min")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Section étendue (cachée par défaut)
            if isExpanded {
                VStack(spacing: 12) {
                    Divider().background(DS.Color.ink.opacity(0.10))

                    if let announcement = tracker.lastAnnouncement {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.Color.primary)
                                .padding(.top, 2)
                            Text(announcement)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }

                    if tracker.progress > 0 {
                        ProgressView(value: tracker.progress)
                            .tint(DS.Color.statusOK)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation { isExpanded = false }
                        onCancel()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Annuler le trajet")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(DS.Color.statusMajor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DS.Color.statusMajor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Color.statusOK.opacity(0.35), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: DS.Color.statusOK.opacity(0.15), radius: 8, y: 2)
    }
}
