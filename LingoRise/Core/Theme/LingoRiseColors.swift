import SwiftUI

struct LingoRiseColors {
    static let primary = Color(hex: 0x1955CC)
    static let primaryLight = Color(hex: 0x3B76ED)
    static let lightPrimary = Color(hex: 0x245FD7)
    static let backgroundLight = Color(hex: 0xF7F8FC)
    static let backgroundDark = Color(hex: 0x111621)
    static let onBackgroundLight = Color(hex: 0x171B26)
    static let onBackgroundDark = Color(hex: 0xF9FAFB)
    static let surfaceLight = Color.white
    static let surfaceDark = Color(hex: 0x1A2233)
    static let onSurfaceLight = Color(hex: 0x171B26)
    static let onSurfaceDark = Color.white
    static let surfaceVariantLight = Color(hex: 0xE9EDF5)
    static let surfaceVariantDark = Color(hex: 0x374151)
    static let onSurfaceVariantLight = Color(hex: 0x596274)
    static let onSurfaceVariantDark = Color(hex: 0x9CA3AF)
    static let outlineLight = Color(hex: 0x788295)
    static let outlineDark = Color(hex: 0x748096)
    static let outlineVariantLight = Color(hex: 0xCDD4E0)
    static let outlineVariantDark = Color(hex: 0x334155)
    static let levelGreen = Color(hex: 0x22C55E)
    static let levelYellow = Color(hex: 0xFACC15)
    static let levelRed = Color(hex: 0xEF4444)
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
