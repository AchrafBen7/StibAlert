//
//  OnBoardingView.swift
//  StibAlert
//

import SwiftUI

// MARK: - Design tokens (couleurs + polices)
enum AppColors {
    static let background = Color(hexRGB: "#2F2E2E")
    static let white      = Color(hexRGB: "#FFFFFF")
    static let white70    = Color.white.opacity(0.7)
}

enum AppFonts {
    // Assure-toi que les polices sont ajoutées dans le projet + Info.plist (Fonts provided by application)
    static func delaGothic(_ size: CGFloat) -> Font {
        .custom("DelaGothicOne-Regular", size: size)
    }
    static func montserrat(_ size: CGFloat) -> Font {
        .custom("Montserrat-Regular", size: size)
    }
}

// MARK: - Helper hex -> Color (signature unique pour éviter les conflits)
extension Color {
    /// Convertit "#RRGGBB", "RRGGBB", "#RGB" ou "RGB" en Color (sRGB).
    /// Exemple: Color(hexRGB: "#2F2E2E")
    init(hexRGB: String, alpha: Double = 1.0) {
        let clean = hexRGB.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)

        let r, g, b: UInt64
        switch clean.count {
        case 3: // RGB 12-bit
            r = (int >> 8) * 17
            g = (int >> 4 & 0xF) * 17
            b = (int & 0xF) * 17
        default: // RRGGBB 24-bit (fallback)
            r = (int >> 16) & 0xFF
            g = (int >> 8)  & 0xFF
            b = int & 0xFF
        }

        self.init(.sRGB,
                  red:   Double(r) / 255.0,
                  green: Double(g) / 255.0,
                  blue:  Double(b) / 255.0,
                  opacity: alpha)
    }
}

// MARK: - Onboarding container (3 pages)
struct OnboardingView: View {
    @State private var index = 0
    var onFinish: () -> Void = {}   // callback pour fermer l’onboarding

    private static let pages: [OnboardingPage] = [
        .init(imageName: "onboarding_bus",
              title: "Des soucis sur votre trajet ?",
              subtitle: "Soyez alerté en temps réel des problèmes sur vos lignes ou arrêts préférés."),
        .init(imageName: "onboarding_map",
              title: "Cartographie claire",
              subtitle: "Visualisez en un coup d’œil les perturbations et alternatives."),
        .init(imageName: "onboarding_favoris",
              title: "Vos favoris d’abord",
              subtitle: "Suivez vos lignes et arrêts préférés sans rien rater.")
    ]

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Stibalert")
                        .font(AppFonts.delaGothic(32)) // 32 px
                        .foregroundColor(AppColors.white)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer(minLength: 0)

                // Pager
                TabView(selection: $index) {
                    ForEach(Self.pages.indices, id: \.self) { i in
                        OnboardingPageView(page: Self.pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Footer: page indicator + Continue
                HStack {
                    PageIndicator(current: index, total: Self.pages.count)
                    Spacer()
                    Button {
                        if index < Self.pages.count - 1 {
                            withAnimation(.easeInOut) { index += 1 }
                        } else {
                            onFinish() // quitte l’onboarding
                        }
                    } label: {
                        Text("Continuer")
                            .font(AppFonts.delaGothic(14)) // 14 px
                            .foregroundColor(AppColors.white)
                    }
                    .padding(.trailing, 24)
                    .accessibilityLabel(index < Self.pages.count - 1 ? "Continuer" : "Terminer")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - One page UI
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(page.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                .padding(.horizontal, 24)

            Text(page.title)
                .font(AppFonts.delaGothic(24)) // 24 px
                .foregroundColor(AppColors.white)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(AppFonts.montserrat(14)) // 14 px
                .foregroundColor(AppColors.white70)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page indicator
struct PageIndicator: View {
    let current: Int
    let total: Int

    private let w: CGFloat = 27
    private let h: CGFloat = 8
    private let gap: CGFloat = 10

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == current ? AppColors.white : Color.clear)
                    .frame(width: w, height: h)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppColors.white, lineWidth: 2)
                            .opacity(i == current ? 0 : 1)
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 24)
    }
}


// MARK: - Model
struct OnboardingPage {
    let imageName: String
    let title: String
    let subtitle: String
}


