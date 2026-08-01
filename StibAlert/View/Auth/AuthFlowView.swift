import SwiftUI

enum AuthRoute: Hashable {
    case signIn
    case signUp
    case activation
}

struct AuthFlowView: View {
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss
    let initialRoute: AuthRoute?
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootPage
                .navigationDestination(for: AuthRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private var rootPage: some View {
        switch initialRoute {
        case .signIn:
            destination(for: .signIn)
        case .signUp:
            destination(for: .signUp)
        case .activation:
            destination(for: .activation)
        case nil:
            WelcomePage(
                onSignIn: { path.append(.signIn) },
                onSignUp: { path.append(.signUp) },
                onSkip: { dismiss() }
            )
        }
    }

    /// Connexion et inscription sont désormais LA MÊME page : le sélecteur
    /// bascule un `@State` interne au lieu d'empiler un écran. Il n'y a donc
    /// plus de va-et-vient dans la pile, et plus besoin du `toggleMode` qui
    /// jonglait entre `append` et `removeAll` selon l'écran d'entrée. Seule
    /// l'activation reste une vraie étape suivante, donc un vrai push.
    @ViewBuilder
    private func destination(for route: AuthRoute) -> some View {
        switch route {
        case .signIn, .signUp:
            AuthPage(
                initialMode: route == .signUp ? .signup : .signin,
                onRequireActivation: { path.append(.activation) },
                onClose: { dismiss() }
            )
            .environmentObject(session)
        case .activation:
            ActivationView()
                .environmentObject(session)
        }
    }
}

private struct WelcomePage: View {
    let onSignIn: () -> Void
    let onSignUp: () -> Void
    let onSkip: () -> Void

    @State private var tickIndex = 0

    private let tickerLines = ["1", "2", "5", "7", "81", "29", "71", "95", "N04"]
    private let tickerHeadlines = [
        "Trafic interrompu · bus de remplacement",
        "Service normal · fréquence respectée",
        "Travaux Place Flagey · déviation",
        "Bondé · 22h Forest National",
        "Reprise progressive · contrôle terminé",
        "Métro régulier · 4 min entre rames",
        "Ralentissement Rogier",
        "Service spécial Atomium ce soir",
        "Noctis renforcé · weekend"
    ]

    private let timer = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    private struct Tile: Identifiable {
        let id = UUID()
        let n: String
        let icon: String
        let title: String
        let desc: String
        let accent: Color
    }

    private let tiles: [Tile] = [
        .init(n: "01", icon: "mappin.and.ellipse", title: "Carte vivante", desc: "Tous les arrêts STIB, lignes, Villo! et événements en un coup d'œil.", accent: DS.Color.primary),
        .init(n: "02", icon: "bell.fill", title: AppLocalizer.string("auth.targeted_alerts", defaultValue: "Alertes ciblées"), desc: AppLocalizer.string("auth.targeted_alerts_desc", defaultValue: "Notifié uniquement sur tes lignes, pas de bruit en plus."), accent: DS.Color.statusMajor),
        .init(n: "03", icon: "person.2.fill", title: AppLocalizer.string("source.community", defaultValue: "Communauté"), desc: AppLocalizer.string("auth.community_desc", defaultValue: "Signalements terrain confirmés en temps réel par les voyageurs."), accent: DS.Color.community),
        .init(n: "04", icon: "bicycle", title: "Multimodal", desc: "Combine STIB, Villo! et marche, le plus rapide selon le trafic réel.", accent: DS.Color.villo)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                hero
                tilesSection
                manifesto
                cta
            }
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(timer) { _ in
            tickIndex = (tickIndex + 1) % tickerLines.count
        }
    }

    private var masthead: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BRUXELLES · STIB-MIVB · 2026")
                    .font(DS.Font.labelSmall.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1)
                Spacer()
                Text("ED. \(formattedDate())")
                    .font(DS.Font.labelSmall.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1.5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Disclaimer App Store : voir SplashView.
            Text(AppLocalizer.string("Application indépendante — non affiliée à STIB-MIVB, SNCB, De Lijn ou TEC.", defaultValue: "Application indépendante — non affiliée à STIB-MIVB, SNCB, De Lijn ou TEC."))
                .font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundColor(DS.Color.inkMute)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            DS.Rule(thick: true)
                .padding(.horizontal, 20)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("№ 001 · ÉDITION MATIN")
                .font(DS.Font.label.weight(.bold))
                .foregroundColor(DS.Color.primary)
                .tracking(2)
                .padding(.bottom, 12)

            (
                Text(AppLocalizer.string("welcome.hero.network_line"))
                    .foregroundColor(DS.Color.ink)
                + Text("en clair.")
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .italic()
                    .foregroundColor(DS.Color.primary)
            )
            .font(.system(size: 44, weight: .bold))
            .tracking(-1.5)
            .lineSpacing(-2)

            Text(AppLocalizer.string("Temps réel, perturbations vérifiées par la communauté et trajets réellement praticables, pour Bruxelles.", defaultValue: "Temps réel, perturbations vérifiées par la communauté et trajets réellement praticables, pour Bruxelles."))
                .font(.system(size: 15))
                .foregroundColor(DS.Color.inkSoft)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.top, 16)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    PulsingDot(color: DS.Color.statusMajor)
                    Text("LIVE · MAINTENANT SUR LE RÉSEAU")
                        .font(DS.Font.label.weight(.bold))
                        .foregroundColor(DS.Color.ink)
                        .tracking(1.5)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DS.Color.paper)
                .overlay(
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.1))
                        .frame(height: 1),
                    alignment: .bottom
                )

                HStack(spacing: 10) {
                    LineBadge(line: tickerLines[tickIndex], size: .sm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tickerHeadlines[tickIndex % tickerHeadlines.count])
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(DS.Color.ink)
                            .lineLimit(1)
                        Text(AppLocalizer.format("auth.demo.confirmed_by", defaultValue: "il y a %lld min · confirmé par %lld voyageurs", 2 + tickIndex, 12 + tickIndex * 3))
                            .font(DS.Font.label)
                            .foregroundColor(DS.Color.inkMute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .animation(.easeInOut(duration: 0.3), value: tickIndex)
            }
            .background(DS.Color.paper2.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var tilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CE QUE VOUS OBTENEZ")
                    .font(DS.Font.labelSmall.weight(.bold))
                    .foregroundColor(DS.Color.ink)
                    .tracking(1)
                Spacer()
                Text("04 · PAGES")
                    .font(DS.Font.label.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1)
            }
            .padding(.bottom, 12)

            DS.Rule()
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(tiles) { tile in
                    tileRow(tile)
                }
            }

            HStack {
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Color.inkMute.opacity(0.6))
                Spacer()
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 24)
    }

    private func tileRow(_ tile: Tile) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(tile.accent)
                .frame(width: 4)

            HStack(alignment: .top, spacing: 14) {
                Text(tile.n)
                    .font(DS.Font.label.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .padding(.top, 4)

                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.paper2.opacity(0.5))
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1)
                    Image(systemName: tile.icon)
                        .font(.system(size: 16))
                        .foregroundColor(DS.Color.ink)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(DS.Color.ink)
                    Text(tile.desc)
                        .font(.system(size: 12.5))
                        .foregroundColor(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)

                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .shadow(DS.Shadow.raised)
    }

    private var manifesto: some View {
        VStack(alignment: .leading, spacing: 12) {
            DS.Rule(thick: true)
            Text(AppLocalizer.string("« Pas de pub, pas de tracking. Juste le réseau bruxellois, lisible, pour les gens qui le prennent vraiment. »", defaultValue: "« Pas de pub, pas de tracking. Juste le réseau bruxellois, lisible, pour les gens qui le prennent vraiment. »"))
                .font(.system(size: 16, design: .serif))
                .italic()
                .foregroundColor(DS.Color.ink)
                .lineSpacing(2)
            Text("— MANIFESTE STIBALERT")
                .font(DS.Font.label.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var cta: some View {
        VStack(spacing: 10) {
            DS.Rule()
                .padding(.bottom, 12)

            Button(action: onSignUp) {
                HStack(spacing: 8) {
                    Text(AppLocalizer.string("Créer un compte gratuit", defaultValue: "Créer un compte gratuit"))
                        .font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundColor(DS.Color.primaryForeground)
                .background(DS.Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.primary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(color: DS.Color.ink.opacity(0.15), radius: 8, y: 4)
            }
            .buttonStyle(PressableScaleStyle())

            Button(action: onSignIn) {
                Text(AppLocalizer.string("J'ai déjà un compte", defaultValue: "J'ai déjà un compte"))
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundColor(DS.Color.ink)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(PressableScaleStyle())

            Button(action: onSkip) {
                Text("CONTINUER SANS COMPTE →")
                    .font(DS.Font.label.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1.5)
                    .padding(.top, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: Date()).uppercased().replacingOccurrences(of: ".", with: "")
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 8, height: 8)
                .scaleEffect(animate ? 2.2 : 1)
                .opacity(animate ? 0 : 0.75)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animate)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear { animate = true }
    }
}
