import SwiftUI

private let totalQuestionSteps = 4

enum LearningGoal: String, CaseIterable {
    case speakConfidently
    case travel
    case workCareer
    case moviesContent
    case dailyEnglish

    var titleKey: String {
        switch self {
        case .speakConfidently: return "personalization_goal_speak_confidently"
        case .travel: return "personalization_goal_travel"
        case .workCareer: return "personalization_goal_work_career"
        case .moviesContent: return "personalization_goal_movies_content"
        case .dailyEnglish: return "personalization_goal_daily_english"
        }
    }

    var milestoneKey: String {
        switch self {
        case .speakConfidently: return "personalization_milestone_speak_confidently"
        case .travel: return "personalization_milestone_travel"
        case .workCareer: return "personalization_milestone_work_career"
        case .moviesContent: return "personalization_milestone_movies_content"
        case .dailyEnglish: return "personalization_milestone_daily_english"
        }
    }

    var symbol: String {
        switch self {
        case .speakConfidently: return "person.wave.2.fill"
        case .travel: return "airplane.departure"
        case .workCareer: return "briefcase.fill"
        case .moviesContent: return "movieclapper.fill"
        case .dailyEnglish: return "sun.max.fill"
        }
    }

    var analyticsKey: String {
        switch self {
        case .speakConfidently: return "speak_confidently"
        case .travel: return "travel"
        case .workCareer: return "work_career"
        case .moviesContent: return "movies_content"
        case .dailyEnglish: return "daily_english"
        }
    }
}

enum LearningLevel: String, CaseIterable {
    case beginner
    case basic
    case intermediate
    case advanced

    var titleKey: String {
        switch self {
        case .beginner: return "personalization_level_beginner"
        case .basic: return "personalization_level_basic"
        case .intermediate: return "personalization_level_intermediate"
        case .advanced: return "personalization_level_advanced"
        }
    }

    var symbol: String {
        switch self {
        case .beginner: return "sun.max.fill"
        case .basic: return "book.pages.fill"
        case .intermediate: return "chart.line.uptrend.xyaxis"
        case .advanced: return "graduationcap.fill"
        }
    }

    var analyticsKey: String { rawValue }
}

enum DailyCommitment: String, CaseIterable {
    case five
    case ten
    case fifteen
    case twenty
    case thirty
    case flexible

    var titleKey: String {
        switch self {
        case .five: return "personalization_commitment_5"
        case .ten: return "personalization_commitment_10"
        case .fifteen: return "personalization_commitment_15"
        case .twenty: return "personalization_commitment_20"
        case .thirty: return "personalization_commitment_30"
        case .flexible: return "personalization_commitment_flexible"
        }
    }

    var weeklyTargetKey: String {
        switch self {
        case .five: return "personalization_weekly_target_5"
        case .ten: return "personalization_weekly_target_10"
        case .fifteen: return "personalization_weekly_target_15"
        case .twenty: return "personalization_weekly_target_20"
        case .thirty: return "personalization_weekly_target_30"
        case .flexible: return "personalization_weekly_target_flexible"
        }
    }

    var symbol: String {
        switch self {
        case .five: return "bolt.fill"
        case .ten: return "timer"
        case .fifteen: return "clock"
        case .twenty: return "chart.line.uptrend.xyaxis"
        case .thirty: return "hourglass"
        case .flexible: return "timelapse"
        }
    }

    var analyticsKey: String {
        switch self {
        case .five: return "5_minutes"
        case .ten: return "10_minutes"
        case .fifteen: return "15_minutes"
        case .twenty: return "20_minutes"
        case .thirty: return "30_minutes"
        case .flexible: return "flexible"
        }
    }
}

enum ConsistencyMotivation: String, CaseIterable, Hashable {
    case dailyReminders
    case fastProgress
    case shortLessons
    case aiGuidance
    case weeklyGoals
    case vocabularyGrowth

    var titleKey: String {
        switch self {
        case .dailyReminders: return "personalization_motivation_daily_reminders"
        case .fastProgress: return "personalization_motivation_fast_progress"
        case .shortLessons: return "personalization_motivation_short_lessons"
        case .aiGuidance: return "personalization_motivation_ai_guidance"
        case .weeklyGoals: return "personalization_motivation_weekly_goals"
        case .vocabularyGrowth: return "personalization_motivation_vocabulary_growth"
        }
    }

    var symbol: String {
        switch self {
        case .dailyReminders: return "bell.fill"
        case .fastProgress: return "chart.line.uptrend.xyaxis"
        case .shortLessons: return "bolt.fill"
        case .aiGuidance: return "sparkles"
        case .weeklyGoals: return "trophy.fill"
        case .vocabularyGrowth: return "book.pages.fill"
        }
    }

    var analyticsKey: String {
        switch self {
        case .dailyReminders: return "daily_reminders"
        case .fastProgress: return "fast_progress"
        case .shortLessons: return "short_lessons"
        case .aiGuidance: return "ai_guidance"
        case .weeklyGoals: return "weekly_goals"
        case .vocabularyGrowth: return "vocabulary_growth"
        }
    }
}

private struct PersonalizationPalette {
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

struct PersonalizationScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("personalization_step") private var savedStep = 0
    @AppStorage("personalization_goal") private var savedGoal = ""
    @AppStorage("personalization_level") private var savedLevel = ""
    @AppStorage("personalization_commitment") private var savedCommitment = ""
    @AppStorage("personalization_motivations") private var savedMotivations = ""
    @State private var step = 0
    @State private var goal: LearningGoal?
    @State private var level: LearningLevel?
    @State private var commitment: DailyCommitment?
    @State private var motivations: Set<ConsistencyMotivation> = []
    @State private var generatedItems = 0
    @State private var lastContinueAt = Date.distantPast
    @State private var generationTask: Task<Void, Never>?
    @State private var restoredState = false

    var body: some View {
        GeometryReader { geometry in
            let isDarkMode = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
            let palette = PersonalizationPalette(isDark: isDarkMode)
            ZStack {
                LinearGradient(
                    colors: [palette.background, palette.surfaceVariant, palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Circle()
                    .fill(LingoRiseColors.primary.opacity(0.24))
                    .frame(width: 300, height: 300)
                    .blur(radius: 54)
                    .offset(y: -104)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    PersonalizationProgress(step: step, palette: palette)
                        .padding(.top, geometry.safeAreaInsets.top + 2)

                    Spacer().frame(height: 8)

                    ZStack {
                        switch step {
                        case 0:
                            TransitionStep(palette: palette)
                        case 1:
                            GoalStep(selected: $goal, palette: palette)
                        case 2:
                            LevelStep(selected: $level, palette: palette)
                        case 3:
                            CommitmentStep(selected: $commitment, palette: palette)
                        case 4:
                            MotivationStep(selected: $motivations, palette: palette)
                        case 5:
                            GeneratingStep(generatedItems: generatedItems, palette: palette)
                        default:
                            ResultStep(
                                goal: goal ?? .speakConfidently,
                                commitment: commitment ?? .ten,
                                palette: palette,
                                onEdit: editAnswers
                            )
                        }
                    }
                    .frame(maxWidth: 440, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                    .animation(.easeInOut(duration: 0.22), value: step)

                    if step != 5 {
                        Spacer().frame(height: 4)
                        PrimaryCtaButton(
                            title: L10n.t("personalization_continue"),
                            enabled: canContinue,
                            action: continueFlow
                        )
                        .frame(maxWidth: 440)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 2, 10))
            }
        }
        .onAppear(perform: restoreState)
        .onChange(of: goal) { _, newValue in
            persistState()
            guard restoredState, let newValue else { return }
            AppAnalytics.logPersonalizationAnswer(question: "goal", answer: newValue.analyticsKey)
        }
        .onChange(of: level) { _, newValue in
            persistState()
            guard restoredState, let newValue else { return }
            AppAnalytics.logPersonalizationAnswer(question: "level", answer: newValue.analyticsKey)
        }
        .onChange(of: commitment) { _, newValue in
            persistState()
            guard restoredState, let newValue else { return }
            AppAnalytics.logPersonalizationAnswer(question: "commitment", answer: newValue.analyticsKey)
        }
        .onChange(of: motivations) { oldValue, newValue in
            persistState()
            guard restoredState else { return }
            let changed = newValue.symmetricDifference(oldValue)
            changed.forEach {
                AppAnalytics.logPersonalizationAnswer(question: "motivation", answer: $0.analyticsKey)
            }
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return true
        case 1: return goal != nil
        case 2: return level != nil
        case 3: return commitment != nil
        case 4: return !motivations.isEmpty
        case 6: return true
        default: return false
        }
    }

    private func continueFlow() {
        let now = Date()
        guard now.timeIntervalSince(lastContinueAt) >= 0.35, canContinue else { return }
        lastContinueAt = now

        switch step {
        case 0...3:
            moveToStep(step + 1)
        case 4:
            startPlanGeneration()
        case 6:
            persistState()
            AppAnalytics.logPersonalizationComplete(
                goal: goal?.analyticsKey,
                level: level?.analyticsKey,
                commitment: commitment?.analyticsKey,
                motivationsCount: motivations.count
            )
            appState.finishPersonalization()
        default:
            break
        }
    }

    private func editAnswers() {
        AppAnalytics.logPersonalizationEditAnswers()
        moveToStep(1)
    }

    private func moveToStep(_ nextStep: Int) {
        withAnimation(.easeInOut(duration: 0.24)) {
            step = nextStep
        }
        persistState()
        AppAnalytics.logPersonalizationStep(nextStep, stepName: stepName(nextStep))
    }

    private func startPlanGeneration() {
        moveToStep(5)
        generatedItems = 0
        generationTask?.cancel()
        generationTask = Task {
            for index in 1...4 {
                try? await Task.sleep(nanoseconds: 850_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        generatedItems = index
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                moveToStep(6)
            }
        }
    }

    private func restoreState() {
        let restoredStep = min(max(savedStep, 0), 6)
        step = restoredStep == 5 ? 4 : restoredStep
        goal = LearningGoal(rawValue: savedGoal)
        level = LearningLevel(rawValue: savedLevel)
        commitment = DailyCommitment(rawValue: savedCommitment)
        motivations = Set(savedMotivations.split(separator: ",").compactMap { ConsistencyMotivation(rawValue: String($0)) })
        restoredState = true
        AppAnalytics.logPersonalizationStep(step, stepName: stepName(step))
    }

    private func persistState() {
        savedStep = step
        savedGoal = goal?.rawValue ?? ""
        savedLevel = level?.rawValue ?? ""
        savedCommitment = commitment?.rawValue ?? ""
        savedMotivations = motivations.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 1: return "goal"
        case 2: return "current_level"
        case 3: return "daily_commitment"
        case 4: return "motivation"
        case 5: return "generating_plan"
        case 6: return "personalized_result"
        default: return "transition"
        }
    }
}

private struct PersonalizationProgress: View {
    let step: Int
    let palette: PersonalizationPalette

    private var progressSteps: Int {
        switch step {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        case 3: return 3
        case 4, 5, 6: return 4
        default: return 0
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalQuestionSteps, id: \.self) { index in
                Capsule()
                    .fill(index < progressSteps ? LingoRiseColors.primary : palette.surfaceVariant)
                    .frame(height: 5)
            }
        }
        .frame(maxWidth: 440)
    }
}

private struct TransitionStep: View {
    let palette: PersonalizationPalette

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 96)
                PersonalizationCircleIcon(symbol: "sparkles", size: 68, iconSize: 32)
                Spacer().frame(height: 22)
                Text(L10n.t("personalization_transition_title"))
                    .font(LexendFont.font(20, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 8)
                Text(L10n.t("personalization_transition_subtitle"))
                    .font(LexendFont.font(16))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 26)
                MiniPlanCard(palette: palette)
                Spacer(minLength: 96)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct GoalStep: View {
    @Binding var selected: LearningGoal?
    let palette: PersonalizationPalette

    var body: some View {
        QuestionShell(
            eyebrow: L10n.t("personalization_goal_eyebrow"),
            title: L10n.t("personalization_goal_title"),
            subtitle: L10n.t("personalization_goal_subtitle"),
            palette: palette,
            topSpacing: 60
        ) {
            VStack(spacing: 12) {
                ForEach(LearningGoal.allCases, id: \.self) { goal in
                    SelectableRowCard(
                        title: L10n.t(goal.titleKey),
                        symbol: goal.symbol,
                        selected: selected == goal,
                        palette: palette
                    ) {
                        selected = goal
                    }
                }
            }
        }
    }
}

private struct LevelStep: View {
    @Binding var selected: LearningLevel?
    let palette: PersonalizationPalette

    var body: some View {
        QuestionShell(
            eyebrow: L10n.t("personalization_level_eyebrow"),
            title: L10n.t("personalization_level_title"),
            subtitle: L10n.t("personalization_level_subtitle"),
            palette: palette
        ) {
            VStack(spacing: 12) {
                ForEach(LearningLevel.allCases, id: \.self) { level in
                    SelectableRowCard(
                        title: L10n.t(level.titleKey),
                        symbol: level.symbol,
                        selected: selected == level,
                        palette: palette
                    ) {
                        selected = level
                    }
                }
            }
        }
    }
}

private struct CommitmentStep: View {
    @Binding var selected: DailyCommitment?
    let palette: PersonalizationPalette

    var body: some View {
        QuestionShell(
            eyebrow: L10n.t("personalization_commitment_eyebrow"),
            title: L10n.t("personalization_commitment_title"),
            subtitle: L10n.t("personalization_commitment_subtitle"),
            palette: palette
        ) {
            VStack(spacing: 12) {
                ForEach(DailyCommitment.allCases, id: \.self) { commitment in
                    SelectableRowCard(
                        title: L10n.t(commitment.titleKey),
                        symbol: commitment.symbol,
                        selected: selected == commitment,
                        palette: palette
                    ) {
                        selected = commitment
                    }
                }
            }
        }
    }
}

private struct MotivationStep: View {
    @Binding var selected: Set<ConsistencyMotivation>
    let palette: PersonalizationPalette

    var body: some View {
        QuestionShell(
            eyebrow: L10n.t("personalization_motivation_eyebrow"),
            title: L10n.t("personalization_motivation_title"),
            subtitle: L10n.t("personalization_motivation_subtitle"),
            palette: palette
        ) {
            PersonalizationFlowLayout(spacing: 10, rowSpacing: 10) {
                ForEach(ConsistencyMotivation.allCases, id: \.self) { motivation in
                    MotivationChip(
                        title: L10n.t(motivation.titleKey),
                        symbol: motivation.symbol,
                        selected: selected.contains(motivation),
                        palette: palette
                    ) {
                        if selected.contains(motivation) {
                            selected.remove(motivation)
                        } else {
                            selected.insert(motivation)
                        }
                    }
                }
            }
        }
    }
}

private struct GeneratingStep: View {
    let generatedItems: Int
    let palette: PersonalizationPalette
    private let items = [
        "personalization_generating_analyzing",
        "personalization_generating_pace",
        "personalization_generating_path",
        "personalization_generating_milestone"
    ]

    var body: some View {
        CenteredStepShell(
            symbol: "sparkles",
            title: L10n.t("personalization_generating_title"),
            subtitle: L10n.t("personalization_generating_subtitle"),
            palette: palette
        ) {
            VStack(spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, key in
                    ChecklistRow(
                        title: L10n.t(key),
                        checked: generatedItems > index,
                        active: generatedItems == index,
                        palette: palette
                    )
                }
            }
        }
    }
}

private struct ResultStep: View {
    let goal: LearningGoal
    let commitment: DailyCommitment
    let palette: PersonalizationPalette
    let onEdit: () -> Void

    var body: some View {
        QuestionShell(
            eyebrow: L10n.t("personalization_result_eyebrow"),
            title: L10n.t("personalization_result_title"),
            subtitle: L10n.t("personalization_result_subtitle"),
            palette: palette
        ) {
            VStack(spacing: 12) {
                ResultMetric(label: L10n.t("personalization_result_goal"), value: L10n.t(goal.titleKey), symbol: "flag.fill", palette: palette)
                ResultMetric(label: L10n.t("personalization_result_daily_effort"), value: L10n.t(commitment.titleKey), symbol: "clock", palette: palette)
                ResultMetric(label: L10n.t("personalization_result_first_milestone"), value: L10n.t(goal.milestoneKey), symbol: "checkmark.circle.fill", palette: palette)
                ResultMetric(label: L10n.t("personalization_result_weekly_target"), value: L10n.t(commitment.weeklyTargetKey), symbol: "chart.line.uptrend.xyaxis", palette: palette)
                Button(action: onEdit) {
                    Text(L10n.t("personalization_edit_answers"))
                        .font(LexendFont.font(15, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CenteredStepShell<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    let palette: PersonalizationPalette
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 72)
                PersonalizationCircleIcon(symbol: symbol, size: 72, iconSize: 34)
                Spacer().frame(height: 24)
                Text(title)
                    .font(LexendFont.font(28, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 8)
                Text(subtitle)
                    .font(LexendFont.font(18))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 30)
                content
                Spacer(minLength: 72)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct QuestionShell<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let palette: PersonalizationPalette
    var topSpacing: CGFloat = 76
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: topSpacing)
                Text(eyebrow.uppercased(with: Locale.current))
                    .font(LexendFont.font(11, weight: .bold))
                    .foregroundStyle(LingoRiseColors.primaryLight)
                Spacer().frame(height: 12)
                Text(title)
                    .font(LexendFont.font(28, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 8)
                Text(subtitle)
                    .font(LexendFont.font(14))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 28)
                content
                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SelectableRowCard: View {
    let title: String
    let symbol: String
    let selected: Bool
    let palette: PersonalizationPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? LingoRiseColors.primary : palette.onSurfaceVariant)
                    .frame(width: 24, height: 24)
                Spacer().frame(width: 14)
                Text(title)
                    .font(LexendFont.font(14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 12)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? LingoRiseColors.primaryLight : palette.outline)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(selected ? LingoRiseColors.primary.opacity(0.18) : palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? LingoRiseColors.primaryLight : palette.outlineVariant, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MotivationChip: View {
    let title: String
    let symbol: String
    let selected: Bool
    let palette: PersonalizationPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(LexendFont.font(11, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(selected ? .white : palette.onSurface)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selected ? LingoRiseColors.primary : palette.surface)
            .overlay(
                Capsule()
                    .stroke(selected ? LingoRiseColors.primaryLight : palette.outlineVariant, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ChecklistRow: View {
    let title: String
    let checked: Bool
    let active: Bool
    let palette: PersonalizationPalette
    @State private var ringRotation: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(checked ? LingoRiseColors.primaryLight : palette.surfaceVariant)
                    .scaleEffect(checked ? 1 : 0.92)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color(hex: 0x60A5FA), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(ringRotation - 90))
                    .opacity(active ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(checked ? 1 : 0)
            }
            .frame(width: 28, height: 28)
            .animation(.easeInOut(duration: 0.22), value: checked)
            .animation(.easeInOut(duration: 0.18), value: active)

            Text(title)
                .font(LexendFont.font(14, weight: .semibold))
                .foregroundStyle((checked || active) ? palette.onSurface : palette.onSurfaceVariant)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

private struct ResultMetric: View {
    let label: String
    let value: String
    let symbol: String
    let palette: PersonalizationPalette

    var body: some View {
        HStack(spacing: 14) {
            PersonalizationCircleIcon(symbol: symbol, size: 44, iconSize: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(LexendFont.font(12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
                Text(value)
                    .font(LexendFont.font(14, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MiniPlanCard: View {
    let palette: PersonalizationPalette

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Capsule()
                    .fill(LingoRiseColors.primaryLight)
                    .frame(width: 5, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("personalization_mini_title"))
                        .font(LexendFont.font(16, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(1)
                    Text(L10n.t("personalization_mini_subtitle"))
                        .font(LexendFont.font(12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LingoRiseColors.primary.opacity(0.16 + Double(index) * 0.04))
                        .frame(height: CGFloat(42 + index * 10))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.outlineVariant, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PrimaryCtaButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(LexendFont.font(16, weight: .bold))
                Image(systemName: "arrow.forward")
                    .font(.system(size: 18, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(enabled ? LingoRiseColors.primary : Color(hex: 0x374151).opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? 1 : 0.62)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct PersonalizationCircleIcon: View {
    let symbol: String
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Circle()
            .fill(LingoRiseColors.primary.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(LingoRiseColors.primaryLight)
            )
    }
}

private struct PersonalizationFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                widest = max(widest, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth == 0 ? size.width : spacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        widest = max(widest, rowWidth)
        return CGSize(width: maxWidth == 0 ? widest : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
