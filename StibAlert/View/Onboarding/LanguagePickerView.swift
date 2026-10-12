import SwiftUI

/// Tout premier écran de l'app, AVANT le consentement RGPD.
///
/// L'app suivait déjà la langue du téléphone : sur un appareil néerlandophone
/// elle s'ouvre bien en néerlandais. Le problème était ailleurs.
///
/// 1. À Bruxelles, la langue du téléphone n'est pas la langue qu'on veut lire.
///    Beaucoup d'appareils sont en anglais par habitude, chez des gens qui
///    lisent le français ou le néerlandais.
/// 2. Une langue que l'app ne parle pas (allemand, espagnol, arabe…) retombe
///    sur le français via `AppLocale.normalize`, en silence. Rien n'indiquait
///    alors que deux autres langues existaient.
/// 3. Le réglage vivait dans Profil → Langues, c'est-à-dire derrière
///    l'onboarding ET derrière la création d'un compte.
///
/// Cet écran coûte un geste et règle les trois.
///
/// ⚠️ Rien ici ne passe par le catalogue de traductions. L'écran s'affiche
/// avant que la langue soit connue : chaque libellé est donc écrit en dur dans
/// sa propre langue, seule façon d'être lisible par les trois publics à la
/// fois. C'est aussi pourquoi il n'y a pas de drapeaux — le néerlandais n'est
/// pas les Pays-Bas et l'anglais n'est pas le Royaume-Uni.
struct LanguagePickerView: View {
    /// Reçoit le code retenu ("fr", "nl" ou "en").
    let onContinue: (String) -> Void

    /// Pré-sélection : la langue que l'app affiche déjà. L'écran devient alors
    /// une confirmation d'un geste pour qui est bien servi par défaut, et une
    /// porte de sortie pour les autres.
    @State private var selected: String = AppLocale.languageCode

    private struct Option {
        let code: String
        /// Le nom de la langue DANS cette langue : « Nederlands », pas
        /// « Néerlandais ». Un néerlandophone doit pouvoir trouver sa ligne
        /// sans lire un mot de français.
        let name: String
        let cta: String
    }

    private let options = [
        Option(code: "fr", name: "Français", cta: "Continuer"),
        Option(code: "nl", name: "Nederlands", cta: "Doorgaan"),
        Option(code: "en", name: "English", cta: "Continue"),
    ]

    private var current: Option {
        options.first { $0.code == selected } ?? options[0]
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            // L'en-tête reste EN HAUT et les trois choix au centre. Les
            // laisser flotter ensemble, comme le faisait la version à titre,
            // creusait un vide démesuré au-dessus dès que le titre a sauté.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("BLAYSE")
                        .font(DS.Font.label)
                        .tracking(2.4)
                        .foregroundStyle(DS.Color.inkMute)
                    Spacer()
                    Text("BRUXELLES · BRUSSEL")
                        .font(DS.Font.labelSmall)
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                }

                // Pas de titre. Une première version écrivait la consigne
                // dans les trois langues, les deux non retenues en gris : ça
                // se lisait comme un bégaiement, et le texte éteint ressemblait
                // à une erreur d'affichage. Les trois lignes ci-dessous disent
                // déjà « Français / Nederlands / English » — rien à ajouter.
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    ForEach(options, id: \.code) { option in
                        row(for: option)
                    }
                }

                Spacer(minLength: 24)

                continueButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func row(for option: Option) -> some View {
        let isSelected = option.code == selected
        return Button {
            guard !isSelected else { return }
            selected = option.code
            AppHaptics.soft()
        } label: {
            HStack(spacing: 14) {
                Text(option.name)
                    .font(DesignSystem.Typography.title3)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.ink.opacity(0.18))
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? DS.Color.primary : DS.Color.border,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var continueButton: some View {
        Button {
            AppHaptics.success()
            onContinue(selected)
        } label: {
            HStack(spacing: 10) {
                // Le bouton parle déjà la langue choisie : « Doorgaan » après
                // un tap sur Nederlands. C'est la preuve immédiate que la
                // bascule a pris, avant même l'écran suivant.
                Text(current.cta)
                Image(systemName: "arrow.right")
            }
            .font(DesignSystem.Typography.bodyStrong)
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(DS.Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.95), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}
