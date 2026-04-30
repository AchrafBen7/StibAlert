import SwiftUI

struct GuestTabPlaceholder: View {
    let reason: GuestAuthReason
    let onSignIn: () -> Void
    let onSignUp: () -> Void

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    VStack(spacing: 24) {
                        heroCard
                        featureStrip
                        actions
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 96)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        PageHeader(
            title: reason.tabTitle,
            eyebrow: reason.tabEyebrow,
            large: true
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var heroCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(DS.Color.paper2)
                    .frame(width: 84, height: 84)
                Image(systemName: reason.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(reason.accent)
            }
            .padding(.top, 20)

            Text(reason.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text(reason.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 20)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            HStack(spacing: 0) {
                placeholderStat(label: reason.statOneLabel, value: reason.statOneValue)
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1, height: 52)
                placeholderStat(label: reason.statTwoLabel, value: reason.statTwoValue)
            }
            .padding(.vertical, 14)
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func placeholderStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.Color.ink)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
    }

    private var featureStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CE QUE TU DÉBLOQUES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(reason.benefits.enumerated()), id: \.offset) { index, benefit in
                    HStack(spacing: 12) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(reason.accent)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DS.Color.ink)
                            Text(benefit.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Color.inkMute)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < reason.benefits.count - 1 {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(height: 1)
                    }
                }
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onSignUp) {
                Text("Créer un compte")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(DS.Color.primaryForeground)
                    .background(DS.Color.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.Color.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(DS.Shadow.floating)
            }
            .buttonStyle(PressableScaleStyle())

            Button(action: onSignIn) {
                Text("Se connecter")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(DS.Color.ink)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PressableScaleStyle())
        }
    }
}

private extension GuestAuthReason {
    struct Benefit {
        let icon: String
        let title: String
        let subtitle: String
    }

    var tabTitle: String {
        switch self {
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        case .report: return "Reports"
        case .confirm: return "Communauté"
        }
    }

    var tabEyebrow: String {
        switch self {
        case .favorites: return "Ton réseau personnel"
        case .profile: return "Compte StibAlert"
        case .report: return "Participation"
        case .confirm: return "Validation terrain"
        }
    }

    var accent: Color {
        switch self {
        case .favorites: return DS.Color.primary
        case .profile: return DS.Color.community
        case .report: return DS.Color.statusMajor
        case .confirm: return DS.Color.statusMinor
        }
    }

    var statOneLabel: String {
        switch self {
        case .favorites: return "Lignes"
        case .profile: return "Historique"
        case .report: return "Signalements"
        case .confirm: return "Votes"
        }
    }

    var statOneValue: String {
        switch self {
        case .favorites: return "∞"
        case .profile: return "24/7"
        case .report: return "Live"
        case .confirm: return "Temps réel"
        }
    }

    var statTwoLabel: String {
        switch self {
        case .favorites: return "Alertes"
        case .profile: return "Contributions"
        case .report: return "Communauté"
        case .confirm: return "Impact"
        }
    }

    var statTwoValue: String {
        switch self {
        case .favorites: return "Ciblées"
        case .profile: return "Centralisées"
        case .report: return "Active"
        case .confirm: return "Direct"
        }
    }

    var benefits: [Benefit] {
        switch self {
        case .favorites:
            return [
                .init(icon: "tram.fill", title: "Lignes suivies", subtitle: "Retrouve tes lignes STIB en un coup d’œil"),
                .init(icon: "bell.fill", title: "Alertes ciblées", subtitle: "Reçois uniquement ce qui touche ton trajet"),
                .init(icon: "arrow.left.arrow.right", title: "Routine quotidienne", subtitle: "Prépare domicile-travail avec le vrai contexte réseau")
            ]
        case .profile:
            return [
                .init(icon: "person.crop.circle", title: "Ton compte", subtitle: "Historique, préférences et identité centralisés"),
                .init(icon: "creditcard", title: "Carte STIB", subtitle: "Associe et consulte ta carte dans le même espace"),
                .init(icon: "rosette", title: "Karma", subtitle: "Retrouve tes reports et confirmations communautaires")
            ]
        case .report:
            return [
                .init(icon: "exclamationmark.bubble.fill", title: "Signaler", subtitle: "Partage un incident terrain avec la communauté"),
                .init(icon: "camera.viewfinder", title: "Contexte précis", subtitle: "Associe arrêt, ligne et description utile"),
                .init(icon: "person.2.fill", title: "Confirmation collective", subtitle: "Aide à fiabiliser le flux temps réel")
            ]
        case .confirm:
            return [
                .init(icon: "hand.thumbsup.fill", title: "Confirmer", subtitle: "Valide les incidents visibles sur le terrain"),
                .init(icon: "checkmark.seal.fill", title: "Résoudre", subtitle: "Aide à fermer les signalements devenus obsolètes"),
                .init(icon: "waveform.path.ecg", title: "Impact direct", subtitle: "Améliore la qualité du réseau partagé par tous")
            ]
        }
    }
}
