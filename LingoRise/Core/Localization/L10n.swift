import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        AppLocalization.localizedString(for: key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: t(key),
            locale: Locale(identifier: AppLocalization.localeIdentifier(for: AppLocalization.selectedLanguageTag)),
            arguments: arguments
        )
    }
}

enum AppLocalization {
    static let storageKey = "app_language"
    static let systemTag = "system"

    static var selectedLanguageTag: String {
        normalizedLanguageTag(UserDefaults.standard.string(forKey: storageKey))
    }

    static func setLanguageTag(_ tag: String) {
        UserDefaults.standard.set(normalizedLanguageTag(tag), forKey: storageKey)
    }

    static func normalizedLanguageTag(_ tag: String?) -> String {
        guard let tag, tag.isEmpty == false else { return systemTag }
        return tag
    }

    static func localizedString(for key: String) -> String {
        let localized = bundle(for: selectedLanguageTag).localizedString(forKey: key, value: nil, table: nil)
        if localized != key {
            return localized
        }
        if let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) {
            let fallback = englishBundle.localizedString(forKey: key, value: nil, table: nil)
            if fallback != key {
                return fallback
            }
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func localeIdentifier(for tag: String) -> String {
        let normalized = normalizedLanguageTag(tag)
        if normalized == systemTag {
            return Locale.preferredLanguages.first ?? Locale.current.identifier
        }
        return normalized.replacingOccurrences(of: "-", with: "_")
    }

    private static func bundle(for tag: String) -> Bundle {
        let normalized = normalizedLanguageTag(tag)
        guard normalized != systemTag else { return .main }

        for candidate in lprojCandidates(for: normalized) {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    private static func lprojCandidates(for tag: String) -> [String] {
        let pieces = tag.split(separator: "-")
        var candidates = [tag]
        if pieces.count > 1 {
            candidates.append("\(pieces[0])-\(pieces[1].uppercased())")
            candidates.append("\(pieces[0])-\(pieces[1])")
        }
        if let language = pieces.first {
            candidates.append(String(language))
        }
        return candidates.reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }
}
