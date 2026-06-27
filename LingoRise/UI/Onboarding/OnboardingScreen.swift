import SwiftUI
import UIKit

private struct OnboardingPalette {
    let isDark: Bool

    var background: Color { isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight }
    var onBackground: Color { isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight }
    var surface: Color { isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight }
    var onSurface: Color { isDark ? LingoRiseColors.onSurfaceDark : LingoRiseColors.onSurfaceLight }
    var surfaceVariant: Color { isDark ? LingoRiseColors.surfaceVariantDark : LingoRiseColors.surfaceVariantLight }
    var onSurfaceVariant: Color { isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight }
    var outline: Color { isDark ? LingoRiseColors.outlineDark : LingoRiseColors.outlineLight }
    var outlineVariant: Color { isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight }
}

struct OnboardingScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("onboarding_current_step") private var currentStep = 0
    @State private var lastNextAt = Date.distantPast
    private let totalSteps = 5

    var body: some View {
        GeometryReader { geometry in
            let isCompactHeight = geometry.size.height < 600
            let isDarkMode = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
            let palette = OnboardingPalette(isDark: isDarkMode)
            let background = palette.background
            let bottomControlsPadding = geometry.safeAreaInsets.bottom + (isCompactHeight ? 20 : 36) + (currentStep == 3 ? 24 : 0)
            ZStack {
                background.ignoresSafeArea()

                Circle()
                    .fill(LingoRiseColors.primary.opacity(0.20))
                    .frame(width: 280, height: 280)
                    .offset(x: 80, y: -80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                Circle()
                    .fill(LingoRiseColors.primary.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .offset(x: -60, y: 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                VStack {
                    ZStack {
                        switch currentStep {
                        case 0:
                            SpeakStoriesStep(isDark: isDarkMode)
                        case 1:
                            DiscoverStoriesStep(isDark: isDarkMode)
                        case 2:
                            FollowStoriesStep(isDark: isDarkMode)
                        case 3:
                            ListeningPuzzleOnboardingStep(
                                isDark: isDarkMode,
                                onPreviousStep: previousStep,
                                currentStep: 3,
                                totalSteps: totalSteps
                            )
                        default:
                            StartJourneyStep(isDark: isDarkMode)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.22), value: currentStep)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, isCompactHeight ? 12 : 24)
                .padding(.bottom, isCompactHeight ? 190 : 248)

                VStack(spacing: 0) {
                    OnboardingHeadline(currentStep: currentStep, isDark: isDarkMode)
                    Spacer().frame(height: isCompactHeight ? 4 : 8)
                    OnboardingSubtitle(currentStep: currentStep, isDark: isDarkMode)
                    Spacer().frame(height: isCompactHeight ? 10 : 20)

                    HStack(spacing: 10) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Capsule()
                                .fill(index == currentStep ? LingoRiseColors.primary : palette.outline)
                                .frame(width: index == currentStep ? 32 : 8, height: 8)
                        }
                    }

                    Spacer().frame(height: isCompactHeight ? 10 : 20)

                    Button(action: nextStep) {
                        HStack(spacing: 8) {
                            Text(currentStep == 4 ? L10n.t("onboarding_start_cta") : L10n.t("onboarding_continue"))
                                .font(LexendFont.font(22, weight: .bold))
                            Image(systemName: "arrow.forward")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(LingoRiseColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !isCompactHeight && (currentStep == 0 || currentStep == 4) {
                        Spacer().frame(height: 16)
                        Text(L10n.t("onboarding_trusted_by"))
                            .font(LexendFont.font(11, weight: .medium))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isCompactHeight ? 12 : 24)
                .padding(.bottom, bottomControlsPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(
                    LinearGradient(
                        colors: [.clear, background.opacity(0.7), background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: isCompactHeight ? 194 : 252)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                )
            }
        }
        .onAppear {
            currentStep = min(max(currentStep, 0), totalSteps - 1)
            AppAnalytics.logOnboardingStep(currentStep, stepName: stepName(currentStep))
        }
    }

    private func nextStep() {
        let now = Date()
        guard now.timeIntervalSince(lastNextAt) >= 0.35 else { return }
        lastNextAt = now
        if currentStep < 4 {
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep += 1
            }
            AppAnalytics.logOnboardingStep(currentStep, stepName: stepName(currentStep))
        } else {
            appState.finishOnboarding()
        }
    }

    private func previousStep() {
        guard currentStep > 0 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            currentStep -= 1
        }
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 0: return "stories_with_audio"
        case 1: return "discover_stories"
        case 2: return "follow_stories"
        case 3: return "listening_sentence_puzzle"
        case 4: return "start_journey"
        default: return "unknown"
        }
    }
}

struct OnboardingHeadline: View {
    let currentStep: Int
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        Group {
            switch currentStep {
            case 0:
                highlighted(first: L10n.t("onboarding_speak_headline_1"), second: L10n.t("onboarding_speak_headline_2"))
            case 1:
                highlighted(first: L10n.t("onboarding_discover_headline_1"), second: L10n.t("onboarding_discover_headline_2"))
            case 2:
                Text(L10n.t("onboarding_follow_title"))
            case 3:
                highlighted(first: L10n.t("onboarding_practice_headline_1"), second: L10n.t("onboarding_practice_headline_2"))
            default:
                highlighted(first: L10n.t("onboarding_start_headline_1"), second: L10n.t("onboarding_start_headline_2"))
            }
        }
        .font(LexendFont.font(28, weight: .bold))
        .lineSpacing(0)
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.onBackground)
        .frame(maxWidth: .infinity)
    }

    private func highlighted(first: String, second: String) -> Text {
        Text(first.trimmingCharacters(in: .whitespacesAndNewlines) + "\n") + Text(second.trimmingCharacters(in: .whitespacesAndNewlines)).foregroundColor(LingoRiseColors.primary).fontWeight(.bold)
    }
}

struct OnboardingSubtitle: View {
    let currentStep: Int
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        Text(text)
            .font(LexendFont.font(18))
            .lineSpacing(0)
            .foregroundStyle(palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var text: String {
        switch currentStep {
        case 0:
            return L10n.t("onboarding_speak_subtitle")
        case 1:
            return L10n.t("onboarding_discover_subtitle")
        case 2:
            return L10n.t("onboarding_follow_subtitle")
        case 3:
            return L10n.t("onboarding_practice_subtitle")
        default:
            return L10n.t("onboarding_start_subtitle")
        }
    }
}

struct SpeakStoriesStep: View {
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            let cardHeight = min(cardWidth * 1.25, max(geometry.size.height - 176, 0))
            VStack {
                Spacer(minLength: 0)
                ZStack {
                    Color(hex: 0x1E2433)
                    FilledOnboardingImage(name: "onboarding_speak_stories_hero")
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 176)
        }
    }
}

struct DiscoverStoriesStep: View {
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = max((geometry.size.height - 176) * 0.88, 0)
            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.t("onboarding_status_time"))
                            .font(LexendFont.font(11, weight: .bold))
                            .foregroundStyle(palette.onSurfaceVariant)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(palette.onSurfaceVariant).frame(width: 4, height: 4)
                            Circle().fill(palette.onSurfaceVariant).frame(width: 4, height: 4)
                            RoundedRectangle(cornerRadius: 2).fill(palette.onSurfaceVariant).frame(width: 12, height: 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    Rectangle()
                        .fill(palette.outlineVariant)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n.t("onboarding_discover_heading"))
                            .font(LexendFont.font(22, weight: .bold))
                            .foregroundStyle(palette.onSurface)
                        Text(L10n.t("onboarding_discover_trending"))
                            .font(LexendFont.font(11, weight: .medium))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .padding(.top, 4)
                        Spacer().frame(height: 20)
                        DiscoverStoryCard(isDark: isDark, image: "onboarding_story_lost_city_z", title: L10n.t("onboarding_story_lost_city_z"), level: L10n.t("onboarding_level_intermediate"), levelColor: LingoRiseColors.levelYellow, duration: L10n.format("onboarding_min", 4))
                        Spacer().frame(height: 10)
                        DiscoverStoryCard(isDark: isDark, image: "onboarding_story_coffee_culture", title: L10n.t("onboarding_story_coffee"), level: L10n.t("onboarding_level_beginner"), levelColor: LingoRiseColors.levelGreen, duration: L10n.format("onboarding_min", 3))
                        Spacer().frame(height: 10)
                        DiscoverStoryCard(isDark: isDark, image: "onboarding_story_tech_trends", title: L10n.t("onboarding_story_tech"), level: L10n.t("onboarding_level_advanced"), levelColor: LingoRiseColors.levelRed, duration: L10n.format("onboarding_min", 6))
                        Spacer().frame(height: 10)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(palette.surfaceVariant)
                                .frame(width: 80, height: 80)
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(palette.surfaceVariant)
                                    .frame(height: 12)
                                    .frame(maxWidth: .infinity)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(palette.surfaceVariant)
                                    .frame(width: 120, height: 8)
                            }
                        }
                        .padding(12)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight, alignment: .top)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 176)
        }
    }
}

struct DiscoverStoryCard: View {
    let isDark: Bool
    let image: String
    let title: String
    let level: String
    let levelColor: Color
    let duration: String
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                onboardingImage(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                Color.black.opacity(0.2)
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(LexendFont.font(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(level)
                        .font(LexendFont.font(11, weight: .medium))
                        .foregroundStyle(levelColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(levelColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(duration)
                        .font(LexendFont.font(11, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(palette.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.outlineVariant, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct FollowStoriesStep: View {
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            let cardHeight = min(cardWidth * 1.25, max(geometry.size.height - 176, 0))
            VStack {
                Spacer(minLength: 0)
                ZStack {
                    FilledOnboardingImage(name: "onboarding_follow_stories_hero")

                    LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)

                    VStack {
                        HStack {
                            Text(L10n.t("onboarding_status_time"))
                                .font(LexendFont.font(11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(.white.opacity(0.2)).frame(width: 12, height: 12)
                                Circle().fill(.white.opacity(0.2)).frame(width: 12, height: 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        HStack(spacing: 8) {
                            Circle().fill(LingoRiseColors.primary).frame(width: 8, height: 8)
                            Text(L10n.t("onboarding_ai_narrator_active"))
                                .font(LexendFont.font(11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(.top, 2)

                        Spacer()

                        VStack(alignment: .leading, spacing: 0) {
                            Text(L10n.t("onboarding_story_lost_kingdom"))
                                .font(LexendFont.font(22, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer().frame(height: 8)
                            (Text(L10n.t("onboarding_follow_teaser_before"))
                                + Text(L10n.t("onboarding_follow_teaser_highlight"))
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                                + Text(L10n.t("onboarding_follow_teaser_after")))
                                .font(LexendFont.font(12))
                                .foregroundStyle(palette.onSurfaceVariant)
                            Spacer().frame(height: 16)
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(LingoRiseColors.primary)
                                    .frame(width: 40, height: 40)
                                    .overlay(Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                                AudioWaveform(heights: [0.2, 0.4, 0.7, 0.5, 0.35, 0.15, 0.45, 0.6, 0.35, 0.2, 0.4, 0.55, 0.5, 0.3], maxHeight: 24)
                                    .frame(maxWidth: .infinity)
                                Text(L10n.t("onboarding_follow_timer"))
                                    .font(LexendFont.font(11, weight: .medium))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                            .padding(16)
                            .background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(24)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(Color(hex: 0x1A202E))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 176)
        }
    }
}

struct ListeningPuzzleOnboardingStep: View {
    let isDark: Bool
    let onPreviousStep: () -> Void
    let currentStep: Int
    let totalSteps: Int
    @State private var completedCount = 0
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }
    private let words = ["ancient", "map", "showed", "way"]

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                HStack {
                    Button(action: onPreviousStep) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(width: 40, height: 40)
                    }
                    Spacer()
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.surfaceVariant).frame(width: 48, height: 6)
                        Capsule().fill(LingoRiseColors.primary).frame(width: 48 * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 6)
                    }
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer().frame(height: 16)
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(LingoRiseColors.primary).frame(width: 8, height: 8)
                        Text(L10n.t("onboarding_recording"))
                            .font(LexendFont.font(11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(L10n.t("onboarding_practice_timer_example"))
                        .font(LexendFont.font(11, weight: .medium))
                        .foregroundStyle(LingoRiseColors.primaryLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(palette.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Spacer().frame(height: 18)
                HStack(spacing: 12) {
                    Circle()
                        .fill(LingoRiseColors.primary)
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
                    AudioWaveform(
                        heights: [0.22, 0.34, 0.58, 0.44, 0.82, 0.62, 0.96, 0.46, 0.7, 0.38, 0.56, 0.28],
                        maxHeight: 32,
                        minHeight: 8
                    )
                    .frame(height: 40)
                    Text("1x")
                        .font(LexendFont.font(11, weight: .bold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(palette.surfaceVariant)
                        .clipShape(Capsule())
                }
                .padding(12)
                .background(palette.surfaceVariant.opacity(0.74))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer().frame(height: 20)
                VStack(alignment: .leading, spacing: 10) {
                    Text("The \(completedCount > 0 ? words[0] : "____") \(completedCount > 1 ? words[1] : "____") \(completedCount > 2 ? words[2] : "____") the \(completedCount > 3 ? words[3] : "____").")
                        .font(LexendFont.font(18, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        ForEach(words.indices, id: \.self) { index in
                            SentenceSlot(
                                isDark: isDark,
                                word: completedCount > index ? words[index] : "",
                                active: completedCount == index
                            )
                        }
                    }
                }
                .padding(14)
                .background(palette.surfaceVariant.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer().frame(height: 16)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(words.indices, id: \.self) { index in
                        PuzzleWordChip(
                            isDark: isDark,
                            word: words[index],
                            selected: completedCount > index,
                            active: completedCount == index
                        )
                    }
                }

                Spacer().frame(height: 18)
                if completedCount == words.count {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
                        Text(L10n.t("onboarding_excellent")).font(LexendFont.font(11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0x22C55E))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Spacer().frame(height: 30)
                }
            }
            .padding(24)
            .background(palette.surface.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 176)
        .task {
            await runAnimation()
        }
    }

    private func runAnimation() async {
        completedCount = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                completedCount = completedCount >= words.count ? 0 : completedCount + 1
            }
            try? await Task.sleep(nanoseconds: completedCount == words.count ? 1_150_000_000 : 220_000_000)
        }
    }
}

struct SentenceSlot: View {
    let isDark: Bool
    let word: String
    let active: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        Text(word.isEmpty ? " " : word)
            .font(LexendFont.font(11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(word.isEmpty ? palette.surface : LingoRiseColors.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(active ? LingoRiseColors.primaryLight : palette.outlineVariant, lineWidth: active ? 1.4 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct PuzzleWordChip: View {
    let isDark: Bool
    let word: String
    let selected: Bool
    let active: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        Text(word)
            .font(LexendFont.font(13, weight: .bold))
            .foregroundStyle(selected ? palette.onSurfaceVariant : palette.onSurface)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(selected ? palette.surfaceVariant.opacity(0.45) : palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(active ? LingoRiseColors.primary : palette.outlineVariant, lineWidth: active ? 1.6 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(selected ? 0.48 : 1)
            .scaleEffect(active ? 1.03 : 1)
    }
}

struct StartJourneyStep: View {
    let isDark: Bool
    private var palette: OnboardingPalette { OnboardingPalette(isDark: isDark) }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            let cardHeight = min(cardWidth * 1.25, max(geometry.size.height - 176, 0))
            VStack {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    FilledOnboardingImage(name: "onboarding_start_journey_hero")

                    LinearGradient(colors: [.clear, .clear, Color(hex: 0x111621, alpha: 0.8)], startPoint: .top, endPoint: .bottom)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(LingoRiseColors.primary)
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "book.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("onboarding_new_story_label"))
                                .font(LexendFont.font(11, weight: .semibold))
                                .foregroundStyle(LingoRiseColors.primaryLight)
                            Text(L10n.t("onboarding_the_lost_city"))
                                .font(LexendFont.font(14))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: 0x111621, alpha: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 26)
                    .padding(.bottom, 32)
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(palette.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 176)
        }
    }
}

struct AudioWaveform: View {
    let heights: [CGFloat]
    let maxHeight: CGFloat
    var minHeight: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 999)
                    .fill(LingoRiseColors.primary.opacity(0.6 + Double(height) * 0.4))
                    .frame(width: 4, height: max(maxHeight * height, minHeight))
            }
        }
    }
}

private func onboardingImage(_ name: String) -> Image {
    if let image = UIImage(named: name) {
        return Image(uiImage: image)
    }

    for fileExtension in ["jpg", "png", "webp"] {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
    }

    return Image(name)
}

private struct FilledOnboardingImage: View {
    let name: String

    var body: some View {
        GeometryReader { geometry in
            onboardingImage(name)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}
