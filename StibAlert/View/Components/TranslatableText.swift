import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Un texte d'opérateur, avec un bouton « Translate » quand l'app est en
/// anglais et que le texte, lui, ne l'est pas.
///
/// Point d'entrée sûr sur TOUTES les versions d'iOS : la partie qui dépend du
/// framework `Translation` (iOS 18+) vit dans une vue séparée, sinon le simple
/// fait de STOCKER une `TranslationSession.Configuration` empêcherait la
/// compilation pour la cible 17.6 de l'app.
struct TranslatableText<Style: View>: View {
    let text: String
    /// Faux sur les rangées COMPACTES (une ligne, tronquées) : un bouton y
    /// casserait la mise en page. Elles profitent quand même de la traduction,
    /// puisque le cache est partagé — dès que l'utilisateur a traduit une fois
    /// où que ce soit, tout l'affiche.
    var showsButton: Bool = true
    /// Le style est fourni par l'appelant : cette vue ne décide pas de
    /// l'apparence, seulement de la LANGUE affichée.
    @ViewBuilder var style: (String) -> Style

    var body: some View {
        if #available(iOS 18.0, *) {
            TranslatableTextCore(text: text, showsButton: showsButton, style: style)
        } else {
            style(text)
        }
    }
}

@available(iOS 18.0, *)
private struct TranslatableTextCore<Style: View>: View {
    let text: String
    let showsButton: Bool
    @ViewBuilder var style: (String) -> Style

    @ObservedObject private var translator = DisruptionTranslator.shared
    /// Poser une configuration DÉCLENCHE `translationTask`. La remettre à nil
    /// ne l'annule pas rétroactivement : c'est la présence d'une valeur NEUVE
    /// qui relance une session.
    @State private var configuration: TranslationSession.Configuration?
    @State private var didFail = false

    private var displayed: String {
        translator.translation(for: text) ?? text
    }

    private var isTranslated: Bool {
        translator.translation(for: text) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            style(displayed)

            if showsButton, translator.isOffered, !isTranslated, !text.isEmpty {
                translateButton
            }
        }
        .task(id: text) {
            // L'utilisateur a déjà accepté une fois : on ne lui redemande plus,
            // on traduit en arrivant. C'est le « avec mémorisation du choix ».
            guard translator.isOffered, translator.autoTranslate, !isTranslated else { return }
            start()
        }
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(text)
                translator.store(source: text, translated: response.targetText)
                translator.enableAuto()
                didFail = false
            } catch {
                // Pack de langue refusé, hors ligne, langue non gérée : on
                // laisse le texte d'origine et on propose de réessayer. Jamais
                // d'écran d'erreur pour une commodité.
                translator.failed(text)
                didFail = true
            }
            configuration = nil
        }
    }

    private var translateButton: some View {
        Button {
            start()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: didFail ? "arrow.clockwise" : "translate")
                    .font(.system(size: 10, weight: .semibold))
                Text(didFail
                     ? AppLocalizer.string("translate.retry", defaultValue: "Réessayer la traduction")
                     : AppLocalizer.string("translate.action", defaultValue: "Traduire"))
                    .font(DS.Font.caption)
            }
            .foregroundStyle(DS.Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(translator.isTranslating(text))
        .opacity(translator.isTranslating(text) ? 0.45 : 1)
    }

    private func start() {
        guard !translator.isTranslating(text) else { return }
        translator.markInFlight(text)
        // `source: nil` = détection automatique. Les communiqués arrivent tantôt
        // en français, tantôt en néerlandais selon ce que publie l'opérateur :
        // fixer la source ferait échouer la moitié des traductions.
        configuration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: translator.targetLanguage)
        )
    }
}
