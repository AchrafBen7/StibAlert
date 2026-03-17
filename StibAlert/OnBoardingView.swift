//
//  OnBoardingView.swift
//  StibAlert
//

import SwiftUI

struct OnboardingView: View {
    @State private var index = 0
    var onFinish: () -> Void = {}

    private static let pages: [OnboardingPage] = [
        .init(imageName: "onboarding_bus", title: L10n.Onboarding.page1Title, subtitle: L10n.Onboarding.page1Subtitle),
        .init(imageName: "onboarding_map", title: L10n.Onboarding.page2Title, subtitle: L10n.Onboarding.page2Subtitle),
        .init(imageName: "onboarding_favoris", title: L10n.Onboarding.page3Title, subtitle: L10n.Onboarding.page3Subtitle)
    ]

    var body: some View {
        ZStack {
            AppTheme.Colors.onboardingBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.Common.appName)
                        .font(AppTheme.Fonts.display(32))
                        .foregroundColor(AppTheme.Colors.textInverse)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)

                Spacer(minLength: 0)

                TabView(selection: $index) {
                    ForEach(Self.pages.indices, id: \.self) { i in
                        OnboardingPageView(page: Self.pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                HStack {
                    PageIndicator(current: index, total: Self.pages.count)
                    Spacer()

                    Button {
                        if index < Self.pages.count - 1 {
                            withAnimation(.easeInOut) {
                                index += 1
                            }
                        } else {
                            onFinish()
                        }
                    } label: {
                        Text(index < Self.pages.count - 1 ? L10n.Common.continueAction : L10n.Common.finishAction)
                            .font(AppTheme.Fonts.display(14))
                            .foregroundColor(AppTheme.Colors.textInverse)
                    }
                    .padding(.trailing, AppTheme.Spacing.lg)
                    .accessibilityLabel(index < Self.pages.count - 1 ? L10n.Common.continueAction : L10n.Common.finishAction)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Image(page.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
                .padding(.horizontal, AppTheme.Spacing.lg)

            Text(page.title)
                .font(AppTheme.Fonts.display(24))
                .foregroundColor(AppTheme.Colors.textInverse)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .fixedSize(horizontal: false, vertical: true)

            Text(page.subtitle)
                .font(AppTheme.Fonts.body(14))
                .foregroundColor(AppTheme.Colors.onboardingTextSecondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xs)

            Spacer(minLength: 0)
        }
    }
}

struct PageIndicator: View {
    let current: Int
    let total: Int

    private let width: CGFloat = 27
    private let height: CGFloat = 8
    private let gap: CGFloat = 10

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == current ? AppTheme.Colors.textInverse : .clear)
                    .frame(width: width, height: height)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.Colors.textInverse, lineWidth: 2)
                            .opacity(i == current ? 0 : 1)
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, AppTheme.Spacing.lg)
    }
}

struct OnboardingPage {
    let imageName: String
    let title: String
    let subtitle: String
}
