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
        let sentence: String
        let cta: String
    }

    private let options = [
        Option(code: "fr", name: "Français",   sentence: "Choisis ta langue.",      cta: "Continuer"),
        Option(code: "nl", name: "Nederlands", sentence: "Kies je taal.",           cta: "Doorgaan"),
        Option(code: "en", name: "English",    sentence: "Choose your language.",   cta: "Continue"),
    ]

    private var current: Option {
        options.first { $0.code == selected } ?? options[0]
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

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

                // La consigne est écrite trois fois, et la ligne de la langue
                // retenue est la seule en pleine encre. C'est ce qui dit, sans
                // texte supplémentaire, que le choix a été pris en compte.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options, id: \.code) { option in
                        Text(option.sentence)
                            // `display` (32 pt) faisait passer « Choose your
                            // language. » sur deux lignes : le bloc tombait à
                            // quatre lignes pour trois phrases, et on ne lisait
                            // plus une liste. 24 pt tient sur une ligne partout.
                            .font(DesignSystem.Typography.title1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(option.code == selected ? DS.Color.ink : DS.Color.inkMute.opacity(0.45))
                    }
                }
                .padding(.top, 20)
                .animation(.easeOut(duration: 0.18), value: selected)

                VStack(spacing: 10) {
                    ForEach(options, id: \.code) { option in
                        row(for: option)
                    }
                }
                .padding(.top, 32)

                Spacer(minLength: 24)

                continueButton
            }
            .padding(.horizontal, 24)
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
