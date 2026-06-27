import CoreText
import SwiftUI

enum LexendFont {
    static func register() {
        guard let url = Bundle.main.url(forResource: "Lexend-VariableFont_wght", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(fontName(for: weight), size: size)
    }

    private static func fontName(for weight: Font.Weight) -> String {
        if weight == .bold {
            return "Lexend-Bold"
        }
        if weight == .semibold {
            return "Lexend-SemiBold"
        }
        if weight == .medium {
            return "Lexend-Medium"
        }
        if weight == .light {
            return "Lexend-Light"
        }
        return "Lexend-Regular"
    }
}
