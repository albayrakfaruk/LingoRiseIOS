import Foundation

enum ContentType: String, Codable {
    case story
    case fact
    case article
    case news

    var label: String {
        switch self {
        case .story: return L10n.t("content_type_story")
        case .fact: return L10n.t("content_type_fact")
        case .article: return L10n.t("content_type_article")
        case .news: return L10n.t("content_type_news")
        }
    }
}

enum EnglishAccent: String, Codable {
    case us = "en-US"
    case uk = "en-GB"

    var label: String {
        switch self {
        case .us: return L10n.t("story_accent_us")
        case .uk: return L10n.t("story_accent_uk")
        }
    }
}

enum NewsScope: String, Codable {
    case global
    case regional
}

enum ExploreSortOption: String, CaseIterable {
    case newest = "Newest"
    case shortestDuration = "Shortest Duration"
    case longestDuration = "Longest Duration"

    var titleKey: String {
        switch self {
        case .newest: return "explore_sort_newest"
        case .shortestDuration: return "explore_sort_shortest"
        case .longestDuration: return "explore_sort_longest"
        }
    }
}

struct ExplorePageResult {
    let items: [Content]
    let lastCreatedAt: Date?
    let lastDocId: String?
    let hasMore: Bool
}

struct Category: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

struct TargetWord: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let pronunciation: String
    let audioUrl: String
}

struct SentenceAudio: Identifiable, Hashable {
    let id = UUID()
    let index: Int
    let text: String
    let audioUrl: String
    let durationMs: Int
    let pronunciation: String
}

struct SourceReference: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let publisher: String
    let url: String
    let publishedAt: String
    let countryCode: String
    let isLocal: Bool
}

struct ImageAttribution: Hashable {
    let source: String
    let creator: String
    let sourcePageUrl: String
    let license: String
    let attribution: String
}

struct Content: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let category: Category
    let level: String
    let duration: String
    let imageUrl: String
    let durationMs: Int
    var sentences: [SentenceAudio]
    let isPremium: Bool
    let createdAt: Date?
    let wordCount: Int
    let targetWords: [TargetWord]
    let contentType: ContentType
    let rating: Double?
    let ratingCount: Int
    let accent: EnglishAccent
    let newsScope: NewsScope?
    let regionCode: String
    let regionLabel: String
    let countryCodes: [String]
    let sourceReferences: [SourceReference]
    let imageAttribution: ImageAttribution?
    let practiceSentenceIndexes: [Int]
}

extension Content {
    func withPackage(sentences: [SentenceAudio], targetWords: [TargetWord], practiceSentenceIndexes: [Int]) -> Content {
        Content(
            id: id,
            title: title,
            author: author,
            summary: summary,
            category: category,
            level: level,
            duration: duration,
            imageUrl: imageUrl,
            durationMs: durationMs,
            sentences: sentences,
            isPremium: isPremium,
            createdAt: createdAt,
            wordCount: wordCount,
            targetWords: targetWords,
            contentType: contentType,
            rating: rating,
            ratingCount: ratingCount,
            accent: accent,
            newsScope: newsScope,
            regionCode: regionCode,
            regionLabel: regionLabel,
            countryCodes: countryCodes,
            sourceReferences: sourceReferences,
            imageAttribution: imageAttribution,
            practiceSentenceIndexes: practiceSentenceIndexes
        )
    }

    func withRating(averageRating: Double, ratingCount: Int) -> Content {
        Content(
            id: id,
            title: title,
            author: author,
            summary: summary,
            category: category,
            level: level,
            duration: duration,
            imageUrl: imageUrl,
            durationMs: durationMs,
            sentences: sentences,
            isPremium: isPremium,
            createdAt: createdAt,
            wordCount: wordCount,
            targetWords: targetWords,
            contentType: contentType,
            rating: averageRating,
            ratingCount: ratingCount,
            accent: accent,
            newsScope: newsScope,
            regionCode: regionCode,
            regionLabel: regionLabel,
            countryCodes: countryCodes,
            sourceReferences: sourceReferences,
            imageAttribution: imageAttribution,
            practiceSentenceIndexes: practiceSentenceIndexes
        )
    }
}

extension SentenceAudio: Decodable {
    enum CodingKeys: String, CodingKey {
        case index
        case text
        case audioUrl
        case durationMs
        case pronunciation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
    }
}

extension TargetWord: Decodable {
    enum CodingKeys: String, CodingKey {
        case text
        case pronunciation
        case audioUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
    }
}
