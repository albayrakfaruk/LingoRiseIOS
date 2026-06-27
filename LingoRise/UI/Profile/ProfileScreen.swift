import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Binding var showLanguageSheet: Bool
    @State private var isRestoring = false
    @State private var alert: ProfileAlert?

    private var palette: HomePalette {
        HomePalette(isDark: appState.effectiveDarkTheme(systemColorScheme: colorScheme))
    }

    private var canUpgradeToYearly: Bool {
        appState.isPremium && AppSubscriptionService.shared.activeSubscriptionPeriod == .weekly
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                if !appState.isPremium || canUpgradeToYearly {
                    PremiumUpgradeCard(isYearlyUpgrade: canUpgradeToYearly) {
                        appState.route = .paywall(source: canUpgradeToYearly ? .profileYearlyUpgrade : .profile)
                    }
                    .frame(minHeight: 210)
                } else {
                    PremiumStatusCard()
                        .frame(minHeight: 120)
                }

                Spacer().frame(height: 28)

                Text(L10n.t("profile_general_settings"))
                    .font(LexendFont.font(13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.leading, 4)
                    .padding(.bottom, 8)

                settingsCard

                Text(L10n.format("profile_version_format", L10n.t("profile_version"), appVersion))
                    .font(LexendFont.font(12))
                    .foregroundStyle(Color(hex: 0x6B7280))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 112)
            }
            .padding(.horizontal, 20)
        }
        .background(palette.background.ignoresSafeArea())
        .alert(item: $alert) { item in
            Alert(title: Text(item.message))
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("profile_title"))
                    .font(LexendFont.font(34, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                Text(L10n.t("profile_manage_account"))
                    .font(LexendFont.font(13))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            Spacer()
            PremiumBadge(isPremium: appState.isPremium) {
                appState.route = .paywall(source: .profile)
            }
            .frame(height: 40)
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            SettingsRow(
                symbol: "moon.fill",
                title: L10n.t("profile_dark_theme"),
                subtitle: appState.effectiveDarkTheme(systemColorScheme: colorScheme) ? L10n.t("profile_dark_theme_enabled") : L10n.t("profile_dark_theme_disabled"),
                tint: LingoRiseColors.primary,
                palette: palette
            ) {
                appState.setDarkTheme(!appState.effectiveDarkTheme(systemColorScheme: colorScheme))
            } trailing: {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { appState.effectiveDarkTheme(systemColorScheme: colorScheme) },
                        set: { appState.setDarkTheme($0) }
                    )
                )
                .labelsHidden()
            }
            Divider().padding(.leading, 76)
            SettingsRow(symbol: "globe", title: L10n.t("profile_app_language"), subtitle: languageLabel(appState.appLanguage), tint: Color(hex: 0x14B8A6), palette: palette) {
                showLanguageSheet = true
            }
            Divider().padding(.leading, 76)
            SettingsRow(symbol: "arrow.clockwise", title: L10n.t("profile_restore_purchase"), subtitle: isRestoring ? L10n.t("profile_restoring") : nil, tint: Color(hex: 0x22C55E), palette: palette, enabled: !isRestoring) {
                restorePurchases()
            }
            Divider().padding(.leading, 76)
            SettingsRow(symbol: "hand.raised.fill", title: L10n.t("profile_privacy_policy"), subtitle: nil, tint: Color(hex: 0x60A5FA), palette: palette) {
                openRemoteUrl(AppRemoteConfig.shared.privacyPolicyUrl)
            }
            Divider().padding(.leading, 76)
            SettingsRow(symbol: "doc.text.fill", title: L10n.t("profile_terms_of_use"), subtitle: nil, tint: Color(hex: 0xA78BFA), palette: palette) {
                openRemoteUrl(AppRemoteConfig.shared.termsOfUseUrl)
            }
            Divider().padding(.leading, 76)
            SettingsRow(symbol: "bubble.left.and.bubble.right.fill", title: L10n.t("profile_feedback"), subtitle: nil, tint: Color(hex: 0x38BDF8), palette: palette) {
                openFeedbackEmail()
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(palette.isDark ? 0.20 : 0.05), radius: 4, x: 0, y: 3)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        if !AppSubscriptionService.shared.isConfigured() {
            alert = ProfileAlert(message: L10n.t("error_revenuecat_not_configured"))
            return
        }
        isRestoring = true
        AppAnalytics.logRestoreStart(source: .profile)
        Task {
            let result = await AppSubscriptionService.shared.restorePurchases()
            isRestoring = false
            switch result {
            case .success:
                AppAnalytics.logRestoreSuccess(source: .profile)
                appState.isPremium = AppSubscriptionService.shared.isPremium
                alert = ProfileAlert(message: L10n.t("profile_restore_success"))
            case .failure(let error):
                AppAnalytics.logRestoreFail(errorMessage: error.message, source: .profile)
                alert = ProfileAlert(message: L10n.t("profile_restore_failed"))
            }
        }
    }

    private func openRemoteUrl(_ value: String) {
        guard let url = URL(string: value), !value.isEmpty else {
            alert = ProfileAlert(message: L10n.t("profile_link_unavailable"))
            return
        }
        openURL(url)
    }

    private func openFeedbackEmail() {
        let address = AppRemoteConfig.shared.companyEmail
        guard !address.isEmpty,
              let encodedSubject = "LingoRise Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(address)?subject=\(encodedSubject)")
        else {
            alert = ProfileAlert(message: L10n.t("profile_email_unavailable"))
            return
        }
        openURL(url) { accepted in
            if !accepted {
                alert = ProfileAlert(message: L10n.t("profile_email_unavailable"))
            }
        }
    }

    private func languageLabel(_ tag: String) -> String {
        LanguageSheet.displayOption(for: tag, systemLanguageTag: Locale.preferredLanguages.first ?? "en-US").title
    }
}

private struct ProfileAlert: Identifiable {
    let id = UUID()
    let message: String
}

struct PremiumUpgradeCard: View {
    var isYearlyUpgrade = false
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: 0x1C2333), Color(hex: 0x151B29), Color(hex: 0x0D121C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(LingoRiseColors.primary.opacity(0.28))
                .blur(radius: 44)
                .frame(width: 170, height: 170)
                .offset(x: 120, y: -70)
            Circle()
                .fill(Color(hex: 0x8B5CF6, alpha: 0.22))
                .blur(radius: 42)
                .frame(width: 150, height: 150)
                .offset(x: -70, y: 92)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(L10n.t(isYearlyUpgrade ? "profile_yearly_best_value" : "profile_premium_access"))
                        .font(LexendFont.font(11, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0xFFE9B0))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(colors: [Color(hex: 0xFACC15, alpha: 0.20), LingoRiseColors.primary.opacity(0.20)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())

                Spacer().frame(height: 16)

                Text(L10n.t(isYearlyUpgrade ? "profile_yearly_upgrade_heading" : "profile_master_english"))
                    .font(LexendFont.font(30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer().frame(height: 12)

                Text(L10n.t(isYearlyUpgrade ? "profile_yearly_upgrade_desc" : "profile_unlimited_speaking_desc"))
                    .font(LexendFont.font(13, weight: .medium))
                    .foregroundStyle(Color(hex: 0xADB3C8))
                    .lineLimit(3)

                Spacer().frame(height: 20)

                ProfileUpgradeCtaButton(
                    title: L10n.t(isYearlyUpgrade ? "profile_upgrade_to_yearly" : "profile_upgrade_now"),
                    action: action
                )
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: LingoRiseColors.primary.opacity(0.25), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: action)
    }
}

private struct ProfileUpgradeCtaButton: View {
    let title: String
    let action: () -> Void

    @State private var glow = false
    @State private var shimmer = false

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xFACC15), Color(hex: 0xF59E0B), Color(hex: 0x8B5CF6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.34),
                            .init(color: .white.opacity(0.28), location: 0.50),
                            .init(color: .white.opacity(0.08), location: 0.66),
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
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x111621))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0xF59E0B, alpha: glow ? 0.32 : 0.18), radius: glow ? 18 : 11, x: 0, y: 7)
        }
        .buttonStyle(.plain)
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

struct PremiumStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("profile_premium_plan"))
                .font(LexendFont.font(22, weight: .bold))
            Text(L10n.t("profile_all_unlocked"))
                .font(LexendFont.font(15, weight: .medium))
                .foregroundStyle(.secondary)
            HStack {
                PremiumBenefitChip(text: L10n.t("profile_premium_benefit_stories"))
                PremiumBenefitChip(text: L10n.t("profile_premium_benefit_practice"))
                PremiumBenefitChip(text: L10n.t("profile_premium_benefit_audio"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PremiumBenefitChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LexendFont.font(12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x22C55E))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: 0x22C55E, alpha: 0.14))
            .clipShape(Capsule())
    }
}

struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let tint: Color
    let palette: HomePalette
    var enabled = true
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(symbol: String, title: String, subtitle: String?, tint: Color, palette: HomePalette, enabled: Bool = true, action: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.palette = palette
        self.enabled = enabled
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(LexendFont.font(16, weight: .medium))
                        .foregroundStyle(palette.onSurface)
                    if let subtitle {
                        Text(subtitle)
                            .font(LexendFont.font(12))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                Spacer()
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.55)
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct LanguageSheet: View {
    struct Option: Identifiable {
        let id = UUID()
        let tag: String
        let titleKey: String
        let flag: String

        var title: String {
            L10n.t(titleKey)
        }
    }

    static let options: [Option] = [
        .init(tag: AppLocalization.systemTag, titleKey: "profile_language_system", flag: "🌐"),
        .init(tag: "en-US", titleKey: "language_english_us", flag: "🇺🇸"),
        .init(tag: "fr-FR", titleKey: "language_french_france", flag: "🇫🇷"),
        .init(tag: "it-IT", titleKey: "language_italian", flag: "🇮🇹"),
        .init(tag: "pt-PT", titleKey: "language_portuguese_portugal", flag: "🇵🇹"),
        .init(tag: "es-419", titleKey: "language_spanish_latin_america", flag: "🇲🇽"),
        .init(tag: "vi", titleKey: "language_vietnamese", flag: "🇻🇳"),
        .init(tag: "ru-RU", titleKey: "language_russian", flag: "🇷🇺"),
        .init(tag: "ar", titleKey: "language_arabic", flag: "🇸🇦"),
        .init(tag: "ja-JP", titleKey: "language_japanese", flag: "🇯🇵"),
        .init(tag: "id", titleKey: "language_indonesian", flag: "🇮🇩"),
        .init(tag: "ko-KR", titleKey: "language_korean", flag: "🇰🇷"),
        .init(tag: "es-ES", titleKey: "language_spanish_spain", flag: "🇪🇸"),
        .init(tag: "pt-BR", titleKey: "language_portuguese_brazil", flag: "🇧🇷"),
        .init(tag: "de-DE", titleKey: "language_german", flag: "🇩🇪"),
        .init(tag: "tr-TR", titleKey: "language_turkish", flag: "🇹🇷")
    ]

    @Environment(\.dismiss) private var dismiss
    @Binding var language: String
    let systemLanguageTag: String
    @State private var pendingLanguage: String

    init(language: Binding<String>, systemLanguageTag: String) {
        _language = language
        self.systemLanguageTag = systemLanguageTag
        _pendingLanguage = State(initialValue: language.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("profile_language_dialog_title"))
                .font(LexendFont.font(22, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.options) { option in
                        LanguageChoiceCard(
                            option: option,
                            selected: normalizedTag(pendingLanguage) == normalizedTag(option.tag)
                        ) {
                            pendingLanguage = option.tag
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(minHeight: 112)

            Button {
                if pendingLanguage != language {
                    AppAnalytics.logAppLanguageChange(previousLanguage: language, newLanguage: pendingLanguage)
                }
                language = pendingLanguage
                dismiss()
            } label: {
                Text(L10n.t("profile_language_apply"))
                    .font(LexendFont.font(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .foregroundStyle(.white)
            .background(LingoRiseColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    static func displayOption(for tag: String, systemLanguageTag: String) -> Option {
        let requested = normalizedTag(tag) == AppLocalization.systemTag ? systemLanguageTag : tag
        return options.first(where: { normalizedTag($0.tag) == normalizedTag(requested) })
            ?? options.first(where: { normalizedTag($0.tag).split(separator: "-").first == normalizedTag(requested).split(separator: "-").first })
            ?? options[0]
    }
}

private struct LanguageChoiceCard: View {
    let option: LanguageSheet.Option
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(option.flag)
                    .font(.system(size: 26))
                Text(option.title)
                    .font(LexendFont.font(12, weight: .semibold))
                    .foregroundStyle(selected ? Color(hex: 0x93C5FD) : Color(.secondaryLabel))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 132, height: 104)
            .background(selected ? LingoRiseColors.primary.opacity(0.22) : Color(.secondarySystemBackground).opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? LingoRiseColors.primary : Color(.separator).opacity(0.35), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private func normalizedTag(_ tag: String) -> String {
    tag.isEmpty || tag == AppLocalization.systemTag ? AppLocalization.systemTag : tag.lowercased()
}
