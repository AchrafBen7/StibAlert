//
//  OnBoardingView.swift
//  StibAlert
//

import SwiftUI

struct OnboardingView: View {
    @State private var index = 0
    @State private var animateLights = false
    var onFinish: () -> Void = {}

    private static let pages: [OnboardingPage] = [
        .init(
            imageName: "onboarding_bus",
            title: L10n.Onboarding.page1Title,
            subtitle: L10n.Onboarding.page1Subtitle,
            style: .editorial,
            accentAlignment: .trailing
        ),
        .init(
            imageName: "onboarding_map",
            title: L10n.Onboarding.page2Title,
            subtitle: L10n.Onboarding.page2Subtitle,
            style: .editorial,
            accentAlignment: .center
        ),
        .init(
            imageName: "onboarding_favoris",
            title: L10n.Onboarding.page3Title,
            subtitle: L10n.Onboarding.page3Subtitle,
            style: .editorial,
            accentAlignment: .leading
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                onboardingBackground(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer(minLength: proxy.size.height * 0.52)

                    TabView(selection: $index) {
                        ForEach(Self.pages.indices, id: \.self) { pageIndex in
                            OnboardingPageView(
                                page: Self.pages[pageIndex],
                                isFirstPage: pageIndex == 0,
                                pageIndex: pageIndex
                            )
                                .tag(pageIndex)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    footer
                        .padding(.horizontal, 34)
                        .padding(.bottom, 34)
                        .padding(.top, 12)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    animateLights = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            PageIndicator(current: index, total: Self.pages.count)
            Spacer()

            Button {
                if index < Self.pages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        index += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(actionTitle)
                        .font(AppTheme.Fonts.clash(14))
                        .lineLimit(1)

                    Image(systemName: index == Self.pages.count - 1 ? "arrow.right" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(actionForeground)
                .frame(width: 118, height: 40)
                .background(
                    Capsule(style: .continuous)
                        .fill(actionBackground)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(actionBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionTitle)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionTitle: String {
        index < Self.pages.count - 1 ? L10n.Common.continueAction : L10n.Common.finishAction
    }

    private var actionForeground: Color {
        index < Self.pages.count - 1 ? AppTheme.Colors.textInverse : AppTheme.Colors.onboardingTitleSand
    }

    private var actionBackground: Color {
        index < Self.pages.count - 1
            ? AppTheme.Colors.onboardingIndicatorBlue.opacity(0.12)
            : AppTheme.Colors.onboardingTitleSand.opacity(0.18)
    }

    private var actionBorder: Color {
        index < Self.pages.count - 1 ? AppTheme.Colors.onboardingIndicatorBlue : AppTheme.Colors.onboardingTitleSand
    }

    private func onboardingBackground(size: CGSize) -> some View {
        ZStack {
            AppTheme.Colors.onboardingBackground
                .ignoresSafeArea()

            Ellipse()
                .fill(AppTheme.Colors.onboardingGlowWhite)
                .frame(width: 665, height: 289)
                .blur(radius: 79.5)
                .offset(
                    x: (-91 + 665 / 2) - size.width / 2,
                    y: (-144 + 289 / 2) - size.height / 2
                )
                .scaleEffect(animateLights ? 1.03 : 0.98)

            Ellipse()
                .fill(AppTheme.Colors.onboardingGlowBlue)
                .frame(width: 587.54, height: 507)
                .blur(radius: 132.3)
                .offset(
                    x: (-97 + 587.54 / 2) - size.width / 2,
                    y: (-211 + 507 / 2) - size.height / 2
                )
                .opacity(animateLights ? 0.95 : 0.82)
                .scaleEffect(animateLights ? 1.05 : 0.98)

            Circle()
                .fill(AppTheme.Colors.onboardingIndicatorBlue.opacity(0.42))
                .frame(width: 72, height: 72)
                .blur(radius: 40)
                .offset(x: size.width * 0.42, y: size.height * 0.06)
                .opacity(animateLights ? 0.8 : 0.55)
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isFirstPage: Bool
    let pageIndex: Int

    var body: some View {
        editorialPage
    }

    private var editorialPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorialAccent
                .padding(.bottom, pageIndex == 0 ? 48 : 34)

            title
                .font(AppTheme.Fonts.clash(32))
                .frame(width: 363, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            Text(page.subtitle)
                .font(AppTheme.Fonts.clash(16))
                .foregroundStyle(AppTheme.Colors.textInverse)
                .frame(width: 329, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 41)
        .padding(.trailing, 28)
    }

    private var editorialAccent: some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accentFill)
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(accentStroke, lineWidth: 1)
            )
            .frame(width: accentWidth, height: 8)
            .frame(maxWidth: .infinity, alignment: page.accentAlignment)
            .opacity(0.94)
    }

    private var accentFill: Color {
        switch pageIndex {
        case 0:
            return AppTheme.Colors.onboardingTitleSand
        case 1:
            return AppTheme.Colors.onboardingIndicatorBlue.opacity(0.32)
        default:
            return AppTheme.Colors.onboardingTitleBlue.opacity(0.22)
        }
    }

    private var accentStroke: Color {
        switch pageIndex {
        case 0:
            return AppTheme.Colors.onboardingTitleSand
        case 1:
            return AppTheme.Colors.onboardingIndicatorBlue
        default:
            return AppTheme.Colors.onboardingTitleBlue.opacity(0.78)
        }
    }

    private var accentWidth: CGFloat {
        switch pageIndex {
        case 0:
            return 38
        case 1:
            return 58
        default:
            return 48
        }
    }

    @ViewBuilder
    private var title: some View {
        if isFirstPage {
            Text("Des ")
                .foregroundStyle(AppTheme.Colors.onboardingTitleBlue)
            + Text("soucis")
                .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
            + Text(" sur votre\ntrajet ?")
                .foregroundStyle(AppTheme.Colors.onboardingTitleBlue)
        } else {
            Text(page.title)
                .foregroundStyle(AppTheme.Colors.onboardingTitleBlue)
        }
    }
}

struct PageIndicator: View {
    let current: Int
    let total: Int

    private let width: CGFloat = 28.077
    private let height: CGFloat = 8
    private let gap: CGFloat = 6

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(i == current ? AppTheme.Colors.onboardingTitleSand : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                i == current
                                    ? AppTheme.Colors.onboardingTitleSand
                                    : AppTheme.Colors.onboardingIndicatorBlue,
                                lineWidth: 1
                            )
                    )
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct OnboardingPage {
    enum Style {
        case editorial
        case card
    }

    let imageName: String
    let title: String
    let subtitle: String
    let style: Style
    let accentAlignment: Alignment
}
