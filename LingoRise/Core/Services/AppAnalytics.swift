import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
import FirebaseCore
#endif

enum AppAnalytics {
    static func logEvent(_ name: String, parameters: [String: Any] = [:]) {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() != nil else {
            #if DEBUG
            print("analytics_skipped", name, parameters)
            #endif
            return
        }
        Analytics.logEvent(name, parameters: parameters)
        #else
        #if DEBUG
        print("analytics", name, parameters)
        #endif
        #endif
    }

    static func logScreenView(_ screenName: String, screenClass: String? = nil) {
        var params: [String: Any] = ["screen_name": screenName]
        if let screenClass {
            params["screen_class"] = screenClass
        }
        logEvent("screen_view", parameters: params)
    }

    static func logStoryView(storyId: String, storyTitle: String, level: String?, categoryName: String?) {
        var params: [String: Any] = [
            "story_id": storyId,
            "story_title": storyTitle,
            "item_id": storyId,
            "item_name": storyTitle
        ]
        if let level {
            params["level"] = level
        }
        if let categoryName {
            params["category_name"] = categoryName
        }
        logEvent("story_view", parameters: params)
    }

    static func logCategorySelect(categoryId: String, categoryName: String) {
        logEvent("category_select", parameters: [
            "category_id": categoryId,
            "category_name": categoryName
        ])
    }

    static func logStartReading(storyId: String, storyTitle: String) {
        logEvent("start_reading", parameters: [
            "story_id": storyId,
            "story_title": storyTitle
        ])
    }

    static func logReadingComplete(storyId: String, storyTitle: String) {
        logEvent("reading_complete", parameters: [
            "story_id": storyId,
            "story_title": storyTitle
        ])
    }

    static func logReadingPlaybackSpeed(storyId: String, speed: Double) {
        logEvent("reading_playback_speed", parameters: [
            "story_id": storyId,
            "playback_speed": speed
        ])
    }

    static func logReadingSeek(storyId: String, progress: Double) {
        logEvent("reading_seek", parameters: [
            "story_id": storyId,
            "value": min(max(progress, 0), 1)
        ])
    }

    static func logReadingReplayForward(storyId: String, action: String) {
        logEvent("reading_replay_forward", parameters: [
            "story_id": storyId,
            "action": action
        ])
    }

    static func logPracticeStart(storyId: String, storyTitle: String, totalSentences: Int) {
        logEvent("practice_start", parameters: [
            "story_id": storyId,
            "story_title": storyTitle,
            "total_sentences": totalSentences
        ])
    }

    static func logPracticeSentenceRecord(storyId: String, sentenceIndex: Int, totalSentences: Int) {
        logEvent("practice_sentence_record", parameters: [
            "story_id": storyId,
            "sentence_index": sentenceIndex,
            "total_sentences": totalSentences
        ])
    }

    static func logPracticeSentenceEvaluated(storyId: String, sentenceIndex: Int, totalSentences: Int, success: Bool) {
        logEvent("practice_sentence_evaluated", parameters: [
            "story_id": storyId,
            "sentence_index": sentenceIndex,
            "total_sentences": totalSentences,
            "success": success
        ])
    }

    static func logListeningPuzzleEvaluated(
        storyId: String,
        storyTitle: String,
        level: String?,
        sentenceIndex: Int,
        questionIndex: Int,
        totalQuestions: Int,
        segmentCount: Int,
        tokenCount: Int,
        success: Bool
    ) {
        var params: [String: Any] = [
            "story_id": storyId,
            "story_title": storyTitle,
            "sentence_index": sentenceIndex,
            "question_index": questionIndex,
            "total_questions": totalQuestions,
            "segment_count": segmentCount,
            "token_count": tokenCount,
            "success": success
        ]
        if let level {
            params["level"] = level
        }
        logEvent("listening_puzzle_evaluated", parameters: params)
    }

    static func logPracticeComplete(storyId: String, storyTitle: String, totalSentences: Int) {
        logEvent("practice_complete", parameters: [
            "story_id": storyId,
            "story_title": storyTitle,
            "total_sentences": totalSentences
        ])
    }

    static func logStoryRating(storyId: String, rating: Int) {
        logEvent("story_rating", parameters: [
            "story_id": storyId,
            "value": min(max(rating, 1), 5)
        ])
    }

    static func logOnboardingStep(_ step: Int, stepName: String) {
        logEvent("onboarding_step", parameters: [
            "step": step,
            "step_name": stepName
        ])
    }

    static func logOnboardingComplete(motivationsCount: Int = 0, level: String? = nil, commitment: String? = nil) {
        var params: [String: Any] = ["motivations_count": motivationsCount]
        if let level {
            params["level"] = level
        }
        if let commitment {
            params["commitment"] = commitment
        }
        logEvent("onboarding_complete", parameters: params)
    }

    static func logPersonalizationStep(_ step: Int, stepName: String) {
        logEvent("personalization_step", parameters: [
            "step": step,
            "step_name": stepName
        ])
    }

    static func logPersonalizationAnswer(question: String, answer: String) {
        logEvent("personalization_answer", parameters: [
            "question": question,
            "answer": answer
        ])
    }

    static func logPersonalizationComplete(goal: String?, level: String?, commitment: String?, motivationsCount: Int) {
        var params: [String: Any] = ["motivations_count": motivationsCount]
        if let goal {
            params["goal"] = goal
        }
        if let level {
            params["level"] = level
        }
        if let commitment {
            params["commitment"] = commitment
        }
        logEvent("personalization_complete", parameters: params)
    }

    static func logPersonalizationEditAnswers() {
        logEvent("personalization_edit_answers")
    }

    static func logPaywallView(source: PaywallSource) {
        logEvent("paywall_view", parameters: ["paywall_source": source.analyticsKey])
    }

    static func logPaywallPlanSelect(source: PaywallSource, optionLabel: String, hasIntroOffer: Bool, hasSavingsTag: Bool) {
        logEvent("paywall_plan_select", parameters: [
            "paywall_source": source.analyticsKey,
            "subscription_option": optionLabel,
            "has_intro_offer": hasIntroOffer,
            "has_savings_tag": hasSavingsTag
        ])
    }

    static func logPaywallDismiss(source: PaywallSource) {
        logEvent("paywall_dismiss", parameters: ["paywall_source": source.analyticsKey])
    }

    static func logPurchaseStart(optionId: String, optionLabel: String, source: PaywallSource) {
        logEvent("purchase_start", parameters: [
            "item_id": optionId,
            "subscription_option": optionLabel,
            "paywall_source": source.analyticsKey
        ])
    }

    static func logPurchaseSuccess(optionId: String, optionLabel: String, source: PaywallSource) {
        logEvent("purchase_success", parameters: [
            "item_id": optionId,
            "subscription_option": optionLabel,
            "paywall_source": source.analyticsKey
        ])
    }

    static func logPurchaseFail(optionId: String, errorMessage: String?, source: PaywallSource) {
        logEvent("purchase_fail", parameters: [
            "item_id": optionId,
            "error_message": normalizedError(errorMessage),
            "paywall_source": source.analyticsKey
        ])
    }

    static func logPurchaseCancel(optionId: String, optionLabel: String, source: PaywallSource) {
        logEvent("purchase_cancel", parameters: [
            "item_id": optionId,
            "subscription_option": optionLabel,
            "paywall_source": source.analyticsKey
        ])
    }

    static func logRestoreStart(source: PaywallSource) {
        logEvent("restore_start", parameters: ["paywall_source": source.analyticsKey])
    }

    static func logRestoreSuccess(source: PaywallSource) {
        logEvent("restore_success", parameters: ["paywall_source": source.analyticsKey])
    }

    static func logRestoreFail(errorMessage: String?, source: PaywallSource) {
        logEvent("restore_fail", parameters: [
            "paywall_source": source.analyticsKey,
            "error_message": normalizedError(errorMessage)
        ])
    }

    static func logAppLanguageChange(previousLanguage: String, newLanguage: String) {
        logEvent("app_language_change", parameters: [
            "previous_language": normalizedLanguageTag(previousLanguage),
            "new_language": normalizedLanguageTag(newLanguage)
        ])
    }

    private static func normalizedLanguageTag(_ tag: String) -> String {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return String((value.isEmpty ? "system" : value).prefix(24))
    }

    private static func normalizedError(_ message: String?) -> String {
        let value = (message ?? "").lowercased()
        if value.isEmpty { return "unknown" }
        if value.contains("cancel") { return "cancelled" }
        if value.contains("network") || value.contains("internet") { return "network" }
        if value.contains("configured") { return "not_configured" }
        if value.contains("package") || value.contains("product") { return "package_unavailable" }
        if value.contains("entitlement") || value.contains("subscription") { return "no_entitlement" }
        return "sdk_error"
    }
}

extension PaywallSource {
    var analyticsKey: String {
        switch self {
        case .personalizedOnboarding:
            return "personalized_onboarding"
        case .onboarding:
            return "onboarding"
        case .home:
            return "home"
        case .explore:
            return "explore"
        case .profile, .profileYearlyUpgrade:
            return "profile"
        case .storyDetail:
            return "story_detail"
        case .reading:
            return "reading"
        case .practice:
            return "practice"
        }
    }
}
