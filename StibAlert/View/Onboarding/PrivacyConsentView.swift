import SwiftUI

struct PrivacyConsentView: View {
    let onAccept: (Bool) -> Void

    @State private var analyticsOptIn = false
    @State private var showFullPolicy = false
    @State private var isAccepting = false

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Text("Avant de continuer, voici comment StibAlert traite vos données.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.bottom, 8)

                    sectionView(
                        icon: "location.circle.fill",
                        title: "Localisation",
                        description: "Utilisée en temps réel pour afficher les arrêts proches et améliorer les signalements. Jamais stockée."
                    )

                    sectionView(
                        icon: "envelope.circle.fill",
                        title: "Compte e-mail",
                        description: "Vous pouvez utiliser StibAlert anonymement. Avec un compte, vous accédez aux favoris et au scoring de confiance plus élevé."
                    )

                    sectionView(
                        icon: "shield.lefthalf.filled",
                        title: "Anti-spam",
                        description: "Votre IP et identifiant d'appareil sont hashés (SHA256) pour éviter les abus. Jamais stockés en clair."
                    )

                    sectionView(
                        icon: "trash.circle.fill",
                        title: "Rétention",
                        description: "Les signalements sont supprimés après 30 jours. Votre compte est conservé tant que vous le souhaitez."
                    )

                    sectionView(
                        icon: "chart.bar.fill",
                        title: "Statistiques (optionnel)",
                        description: "Aidez-nous à améliorer l'app en partageant des données d'usage anonymes. Vous pouvez désactiver à tout moment."
                    )

                    Toggle(isOn: $analyticsOptIn) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Partager des statistiques d'usage anonymes")
                                .font(DS.Font.bodyBold)
                                .foregroundStyle(DS.Color.ink)
                            Text("Aucune donnée personnelle identifiable. Modifiable dans Profil → Confidentialité.")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DS.Color.primary))
                    .padding(14)
                    .background(DS.Color.paper2)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        showFullPolicy = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Lire la politique de confidentialité complète")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.ink)
                        .padding(14)
                        .background(DS.Color.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
            }
            .accessibilityLabel("Consentement RGPD StibAlert")

            VStack {
                Spacer()
                Button {
                    isAccepting = true
                    let now = Date()
                    UserDefaults.standard.set(true, forKey: AppStorageKeys.hasAcceptedPrivacyConsent)
                    UserDefaults.standard.set(now.timeIntervalSince1970, forKey: AppStorageKeys.privacyConsentAcceptedAt)
                    UserDefaults.standard.set(PrivacyConsent.currentVersion, forKey: AppStorageKeys.privacyConsentVersion)
                    UserDefaults.standard.set(analyticsOptIn, forKey: AppStorageKeys.analyticsOptIn)
                    onAccept(analyticsOptIn)
                } label: {
                    HStack {
                        if isAccepting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Accepter et continuer")
                                .font(DS.Font.bodyBold)
                            Image(systemName: "arrow.right")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Color.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isAccepting)
                .accessibilityHint("Confirme votre consentement et lance l'application")
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(
                    LinearGradient(
                        colors: [DS.Color.paper.opacity(0), DS.Color.paper, DS.Color.paper],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .sheet(isPresented: $showFullPolicy) {
            PrivacyPolicySheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONFIDENTIALITÉ")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.primary)
            Text("Vos données, vos règles")
                .font(DS.Font.displayH1)
                .foregroundStyle(DS.Color.ink)
        }
    }

    private func sectionView(icon: String, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.Color.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(description)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Politique de confidentialité — StibAlert")
                        .font(DS.Font.displayH2)
                        .foregroundStyle(DS.Color.ink)

                    Text("Dernière mise à jour : 12 mai 2026 · Version \(PrivacyConsent.currentVersion)")
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)

                    sectionText(title: "1. Données collectées", body: """
                    - Adresse e-mail, nom, mot de passe haché (bcrypt).
                    - Coordonnées GPS utilisées uniquement au moment du signalement.
                    - Description et photo des signalements.
                    - Hash SHA256 de l'IP et identifiant d'appareil (anti-spam, jamais stocké en clair).
                    - Token OneSignal pour push notifications.
                    """)

                    sectionText(title: "2. Utilisation", body: """
                    - Authentification et gestion de compte.
                    - Affichage des incidents temps réel.
                    - Anti-spam et modération.
                    - Push notifications de perturbations sur vos lignes favorites.
                    """)

                    sectionText(title: "3. Partage", body: """
                    Aucune donnée vendue ou partagée à des fins commerciales. Données stockées chez :
                    - MongoDB Atlas (UE)
                    - Redis Cloud (UE)
                    - OneSignal (UE/US)
                    - Cloudinary (UE)
                    """)

                    sectionText(title: "4. Vos droits (RGPD)", body: """
                    Vous pouvez à tout moment :
                    - Exporter vos données depuis Profil → Confidentialité
                    - Supprimer votre compte (anonymisation immédiate des signalements)
                    - Rectifier vos informations
                    - Désactiver les statistiques anonymes

                    Contact : privacy@stib-alert.be
                    """)

                    sectionText(title: "5. Rétention", body: """
                    - Signalements : 30 jours
                    - Compte : tant qu'il est actif
                    - Anti-spam hashes : 90 jours après dernière activité
                    """)
                }
                .padding(20)
            }
            .navigationTitle("Confidentialité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func sectionText(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text(body)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

extension PrivacyConsent {
    static var hasUserAccepted: Bool {
        let accepted = UserDefaults.standard.bool(forKey: AppStorageKeys.hasAcceptedPrivacyConsent)
        let storedVersion = UserDefaults.standard.string(forKey: AppStorageKeys.privacyConsentVersion)
        return accepted && storedVersion == currentVersion
    }

    static var analyticsEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.analyticsOptIn)
    }
}
