import SwiftUI
import UIKit

private enum PaywallPlanKind: String {
    case weekly
    case yearly
}

private struct PaywallPlan: Identifiable {
    let id: PaywallPlanKind
    let optionId: String
    let titleKey: String
    let subtitleKey: String
    let price: String
    let periodKey: String
    let weeklyEquivalent: String?
    let badge: String?
    let emphasized: Bool
    let hasIntroOffer: Bool
}

private struct PaywallPalette {
    let background: Color
    let onBackground: Color
    let surface: Color
    let onSurface: Color
    let surfaceVariant: Color
    let onSurfaceVariant: Color
    let outlineVariant: Color

    init(isDark: Bool) {
        background = isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight
        onBackground = isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight
        surface = isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight
        onSurface = isDark ? LingoRiseColors.onSurfaceDark : LingoRiseColors.onSurfaceLight
        surfaceVariant = isDark ? LingoRiseColors.surfaceVariantDark : LingoRiseColors.surfaceVariantLight
        onSurfaceVariant = isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight
        outlineVariant = isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight
    }
}

struct PaywallScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let source: PaywallSource

    @State private var selectedPlan: PaywallPlanKind = .yearly
    @State private var canDismiss = false
    @State private var weeklyOption = AppSubscriptionOption.fallbackWeekly
    @State private var yearlyOption = AppSubscriptionOption.fallbackYearly

    private let panelReservedHeight: CGFloat = 200

    var body: some View {
        let palette = PaywallPalette(isDark: appState.effectiveDarkTheme(systemColorScheme: colorScheme))
        let weeklyPlan = PaywallPlan(
            id: .weekly,
            optionId: weeklyOption.id,
            titleKey: "paywall_weekly_plan",
            subtitleKey: "paywall_billed_weekly",
            price: weeklyOption.price,
            periodKey: "paywall_price_per_week",
            weeklyEquivalent: nil,
            badge: weeklyOption.hasIntroOffer ? L10n.t("paywall_first_time_offer") : weeklyOption.savingsTag,
            emphasized: false,
            hasIntroOffer: weeklyOption.hasIntroOffer
        )
        let yearlyPlan = PaywallPlan(
            id: .yearly,
            optionId: yearlyOption.id,
            titleKey: "paywall_yearly_plan_short",
            subtitleKey: "paywall_billed_yearly",
            price: yearlyOption.price,
            periodKey: "paywall_price_per_year",
            weeklyEquivalent: yearlyOption.weeklyPrice.map { L10n.format("paywall_weekly_equivalent", $0) },
            badge: yearlyOption.savingsTag ?? (yearlyOption.hasIntroOffer ? L10n.t("paywall_first_time_offer") : nil),
            emphasized: true,
            hasIntroOffer: yearlyOption.hasIntroOffer
        )
        let visiblePlans = source == .profileYearlyUpgrade ? [yearlyPlan] : [weeklyPlan, yearlyPlan]
        let selectedPaywallPlan = visiblePlans.first { $0.id == selectedPlan } ?? yearlyPlan

        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [palette.background, palette.surfaceVariant, palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                PremiumBackground()
                    .ignoresSafeArea()

                if canDismiss {
                    Button {
                        appState.dismissPaywall(source: source)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.onSurface)
                            .frame(width: 40, height: 40)
                            .background(palette.surfaceVariant)
                            .overlay(
                                Circle()
                                    .stroke(palette.outlineVariant, lineWidth: 1)
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("paywall_close"))
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                    .zIndex(3)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            HeroTitle(source: source, palette: palette)
                            Spacer().frame(height: 8)
                            Text(subtitle)
                                .font(LexendFont.font(15, weight: .medium))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer().frame(height: 14)
                            TrustStrip(palette: palette)
                            Spacer().frame(height: 14)

                            VStack(spacing: 8) {
                                PaywallValueRow(
                                    symbol: "headphones",
                                    title: L10n.t("paywall_feature_listen_read"),
                                    subtitle: L10n.t("paywall_feature_listen_read_sub"),
                                    palette: palette
                                )
                                PaywallValueRow(
                                    symbol: "sparkles",
                                    title: L10n.t("paywall_feature_pronunciation"),
                                    subtitle: L10n.t("paywall_feature_pronunciation_sub"),
                                    palette: palette
                                )
                                PaywallValueRow(
                                    symbol: "book.fill",
                                    title: L10n.t("paywall_feature_unlimited"),
                                    subtitle: L10n.t("paywall_feature_unlimited_sub"),
                                    palette: palette
                                )
                                PaywallValueRow(
                                    symbol: "point.topleft.down.curvedto.point.bottomright.up",
                                    title: L10n.t("paywall_feature_path"),
                                    subtitle: L10n.t("paywall_feature_path_sub"),
                                    palette: palette
                                )
                            }

                            Spacer().frame(height: 20)
                        }
                        .frame(maxWidth: 440)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 52)
                    .padding(.bottom, panelReservedHeight)
                }

                StickyPurchasePanel(
                    plans: visiblePlans,
                    selectedPlan: $selectedPlan,
                    source: source,
                    palette: palette,
                    bottomInset: geometry.safeAreaInsets.bottom,
                    onPlanSelected: { plan in
                        AppAnalytics.logPaywallPlanSelect(
                            source: source,
                            optionLabel: plan.id.rawValue,
                            hasIntroOffer: plan.hasIntroOffer,
                            hasSavingsTag: plan.badge != nil && plan.hasIntroOffer == false
                        )
                    },
                    onPurchase: {
                        purchase(selectedPaywallPlan)
                    },
                    onPrivacy: { openRemoteUrl(AppRemoteConfig.shared.privacyPolicyUrl) },
                    onTerms: { openRemoteUrl(AppRemoteConfig.shared.termsOfUseUrl) },
                    onRestore: { restorePurchases() }
                )
            }
            .animation(.easeInOut(duration: 0.26), value: canDismiss)
            .onAppear {
                AppAnalytics.logPaywallView(source: source)
                canDismiss = false
                Task {
                    await loadOfferings()
                }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        canDismiss = true
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch source {
        case .personalizedOnboarding:
            return L10n.t("paywall_subtitle_personalized")
        case .profileYearlyUpgrade:
            return L10n.t("paywall_subtitle_yearly_upgrade")
        default:
            return L10n.t("paywall_subtitle_generic")
        }
    }

    private func loadOfferings() async {
        guard let result = await AppSubscriptionService.shared.fetchOfferings() else { return }
        await MainActor.run {
            if let weekly = result.weekly {
                weeklyOption = weekly
            }
            if let yearly = result.yearly {
                yearlyOption = yearly
            }
        }
    }

    private func purchase(_ plan: PaywallPlan) {
        AppAnalytics.logPurchaseStart(optionId: plan.optionId, optionLabel: plan.id.rawValue, source: source)
        Task {
            if AppSubscriptionService.shared.isConfigured() {
                let result = await AppSubscriptionService.shared.purchase(optionId: plan.optionId)
                await MainActor.run {
                    switch result {
                    case .success:
                        AppAnalytics.logPurchaseSuccess(optionId: plan.optionId, optionLabel: plan.id.rawValue, source: source)
                        appState.isPremium = true
                        appState.completePaywall(source: source)
                    case let .failure(error):
                        AppAnalytics.logPurchaseFail(optionId: plan.optionId, errorMessage: error.message, source: source)
                    }
                }
            } else {
                await MainActor.run {
                    appState.isPremium = true
                    appState.completePaywall(source: source)
                }
            }
        }
    }

    private func restorePurchases() {
        AppAnalytics.logRestoreStart(source: source)
        Task {
            let result = await AppSubscriptionService.shared.restorePurchases()
            await MainActor.run {
                switch result {
                case .success:
                    AppAnalytics.logRestoreSuccess(source: source)
                    appState.isPremium = true
                    appState.completePaywall(source: source)
                case let .failure(error):
                    AppAnalytics.logRestoreFail(errorMessage: error.message, source: source)
                }
            }
        }
    }

    private func openRemoteUrl(_ urlString: String) {
        guard let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PremiumBackground: View {
    var body: some View {
        ZStack {
            VStack {
                RadialGradient(
                    colors: [
                        Color(hex: 0x60A5FA, alpha: 0.38),
                        Color(hex: 0x8B5CF6, alpha: 0.22),
                        .clear
                    ],
                    center: UnitPoint(x: 0.82, y: -0.12),
                    startRadius: 0,
                    endRadius: 360
                )
                .frame(height: 340)
                Spacer()
            }

            HStack {
                RadialGradient(
                    colors: [
                        Color(hex: 0x1D4ED8, alpha: 0.18),
                        .clear
                    ],
                    center: UnitPoint(x: -0.18, y: 0.78),
                    startRadius: 0,
                    endRadius: 260
                )
                .frame(height: 360)
                Spacer()
            }
        }
    }
}

private struct HeroTitle: View {
    let source: PaywallSource
    let palette: PaywallPalette

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("paywall_hero_prefix").replacingOccurrences(of: "\\n", with: "").replacingOccurrences(of: "\n", with: ""))
                .font(LexendFont.font(26, weight: .bold))
                .foregroundStyle(palette.onBackground)
                .multilineTextAlignment(.center)
            Text(heroHighlight)
                .font(LexendFont.font(26, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0x93C5FD), Color(hex: 0x60A5FA), Color(hex: 0xA78BFA)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroHighlight: String {
        switch source {
        case .personalizedOnboarding:
            return L10n.t("paywall_hero_personalized")
        case .profileYearlyUpgrade:
            return L10n.t("paywall_hero_yearly_upgrade")
        default:
            return L10n.t("paywall_hero_generic")
        }
    }
}

private struct TrustStrip: View {
    let palette: PaywallPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0xFACC15))
                .frame(width: 20, height: 20)
            Text(L10n.t("paywall_trust_strip"))
                .font(LexendFont.font(12, weight: .semibold))
                .foregroundStyle(palette.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.outlineVariant, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PaywallValueRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let palette: PaywallPalette

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x93C5FD))
                .frame(width: 36, height: 36)
                .background(LingoRiseColors.primary.opacity(0.16))
                .clipShape(Circle())
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LexendFont.font(13, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(1)
                Text(subtitle)
                    .font(LexendFont.font(11, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.outlineVariant, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StickyPurchasePanel: View {
    let plans: [PaywallPlan]
    @Binding var selectedPlan: PaywallPlanKind
    let source: PaywallSource
    let palette: PaywallPalette
    let bottomInset: CGFloat
    let onPlanSelected: (PaywallPlan) -> Void
    let onPurchase: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlanSelectionRow(
                plans: plans,
                selectedPlan: $selectedPlan,
                palette: palette,
                onPlanSelected: onPlanSelected
            )
            .padding(.horizontal, 8)
            .frame(maxWidth: 440)

            Spacer().frame(height: 18)

            PremiumCtaButton(
                title: ctaText,
                enabled: true,
                action: onPurchase
            )
            .frame(maxWidth: 440)

            Spacer().frame(height: 1)

            HStack(spacing: 0) {
                FooterLink(title: L10n.t("profile_privacy_policy"), action: onPrivacy)
                FooterLink(title: L10n.t("profile_terms_of_use"), action: onTerms)
                FooterLink(title: L10n.t("paywall_restore"), action: onRestore)
            }
            .frame(maxWidth: 440)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, max(bottomInset - 16, 0))
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    .clear,
                    palette.background.opacity(0.96),
                    palette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var ctaText: String {
        switch selectedPlan {
        case .yearly:
            return L10n.t("paywall_cta_year_growth")
        case .weekly:
            return L10n.t("paywall_cta_week_rise")
        }
    }
}

private struct PlanSelectionRow: View {
    let plans: [PaywallPlan]
    @Binding var selectedPlan: PaywallPlanKind
    let palette: PaywallPalette
    let onPlanSelected: (PaywallPlan) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(plans) { plan in
                PremiumPlanCard(
                    plan: plan,
                    selected: selectedPlan == plan.id,
                    palette: palette
                ) {
                    selectedPlan = plan.id
                    onPlanSelected(plan)
                }
            }
        }
    }
}

private struct PremiumPlanCard: View {
    let plan: PaywallPlan
    let selected: Bool
    let palette: PaywallPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(plan.titleKey))
                        .font(LexendFont.font(14, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(1)
                    Text(L10n.t(plan.subtitleKey))
                        .font(LexendFont.font(11, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                }
                .frame(height: 40, alignment: .topLeading)
                .padding(.trailing, 28)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 0) {
                    Text(plan.price)
                        .font(LexendFont.font(20, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(1)
                    Text(L10n.t(plan.periodKey))
                        .font(LexendFont.font(11))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                    Text(plan.weeklyEquivalent ?? "")
                        .font(LexendFont.font(11, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                }
                .frame(height: 56, alignment: .bottomLeading)

                Spacer().frame(height: 0)

                HStack {
                    if let badge = plan.badge {
                        Text(badge)
                            .font(LexendFont.font(9, weight: .bold))
                            .foregroundStyle(plan.emphasized ? Color(hex: 0x111621) : .white)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(plan.emphasized ? Color(hex: 0xFACC15) : LingoRiseColors.primaryLight)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 22, alignment: .bottomLeading)
            }
            .padding(.leading, 17)
            .padding(.trailing, 34)
            .padding(.top, 15)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .leading)
            .frame(height: 126)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                selectionIndicator
                    .padding(.top, 10)
                    .padding(.trailing, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: selected ? Color(hex: 0x3B82F6, alpha: 0.30) : .clear, radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(selected ? Color.white : palette.surfaceVariant)
                .overlay(Circle().stroke(palette.outlineVariant, lineWidth: 1))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LingoRiseColors.primary)
            }
        }
        .frame(width: 20, height: 20)
    }

    private var background: LinearGradient {
        if selected {
            return LinearGradient(
                colors: [
                    Color(hex: 0x1D4ED8, alpha: plan.emphasized ? 0.34 : 0.22),
                    Color(hex: 0x7C3AED, alpha: plan.emphasized ? 0.24 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [palette.surface, palette.surfaceVariant],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var border: LinearGradient {
        if selected {
            return LinearGradient(
                colors: [Color(hex: 0x93C5FD), Color(hex: 0xA78BFA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [palette.outlineVariant, palette.outlineVariant],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PremiumCtaButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    @State private var glow = false
    @State private var shimmer = false

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x60A5FA), Color(hex: 0x2563EB), Color(hex: 0x8B5CF6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.06), location: 0.34),
                            .init(color: .white.opacity(0.20), location: 0.50),
                            .init(color: .white.opacity(0.06), location: 0.66),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 220, height: proxy.size.height * 2.8)
                    .blur(radius: 10)
                    .rotationEffect(.degrees(18))
                    .offset(x: shimmer ? proxy.size.width + 150 : -260, y: -proxy.size.height * 0.9)
                }
                .allowsHitTesting(false)

                HStack(spacing: 8) {
                    Text(title)
                        .font(LexendFont.font(15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }

                if !enabled {
                    Color(hex: 0x111621, alpha: 0.42)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x3B82F6, alpha: glow ? 0.44 : 0.30), radius: glow ? 22 : 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glow = true
            }
            withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }
}

private struct FooterLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LexendFont.font(10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
@MainActor
private func paywallPreviewAppState(darkTheme: Bool) -> AppState {
    let state = AppState()
    state.isDarkTheme = darkTheme
    state.isDarkThemeConfigured = true
    return state
}

#Preview("Paywall - Personalized Dark") {
    let appState = paywallPreviewAppState(darkTheme: true)
    PaywallScreen(source: .personalizedOnboarding)
        .environmentObject(appState)
        .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage)))
        .preferredColorScheme(.dark)
}

#Preview("Paywall - Personalized Light") {
    let appState = paywallPreviewAppState(darkTheme: false)
    PaywallScreen(source: .personalizedOnboarding)
        .environmentObject(appState)
        .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage)))
        .preferredColorScheme(.light)
}

#Preview("Paywall - Profile Upgrade") {
    let appState = paywallPreviewAppState(darkTheme: true)
    PaywallScreen(source: .profileYearlyUpgrade)
        .environmentObject(appState)
        .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage)))
        .preferredColorScheme(.dark)
}
#endif
