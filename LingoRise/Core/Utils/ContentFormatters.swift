import SwiftUI

func localizedDuration(_ duration: String) -> String {
    duration.replacingOccurrences(of: "minutes", with: "min").replacingOccurrences(of: "minute", with: "min")
}

func difficultyLabel(_ level: String) -> String {
    switch level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "a1", "beginner": return "A1"
    case "a2", "elementary": return "A2"
    case "b1": return "B1"
    case "b2", "intermediate": return "B2"
    case "c1", "advanced": return "C1"
    default:
        let value = level.uppercased()
        return value.isEmpty ? "-" : value
    }
}

func difficultyColor(_ level: String) -> Color {
    switch difficultyLabel(level) {
    case "A1", "A2": return Color(hex: 0x22C55E)
    case "B1", "B2": return Color(hex: 0xEAB308)
    case "C1": return Color(hex: 0xEF4444)
    default: return Color(hex: 0x9CA3AF)
    }
}

func voiceLabel(_ accent: EnglishAccent) -> String {
    let flag = accent == .uk ? "🇬🇧" : "🇺🇸"
    return L10n.format("story_voice_accent_format", flag, accent.label)
}

func formatTime(_ ms: Int) -> String {
    let totalSeconds = max(ms / 1000, 0)
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}
