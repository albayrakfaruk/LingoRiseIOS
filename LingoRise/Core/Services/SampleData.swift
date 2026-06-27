import Foundation

enum SampleData {
    static let categories = [
        Category(id: "short_easy", title: "Short & Easy", symbol: "book.fill"),
        Category(id: "travel", title: "Travel", symbol: "airplane"),
        Category(id: "business", title: "Business", symbol: "briefcase.fill")
    ]

    static let sentences = [
        SentenceAudio(index: 0, text: "The mist rolled in from the northern peaks.", audioUrl: "", durationMs: 4200, pronunciation: ""),
        SentenceAudio(index: 1, text: "She listened closely as the ancient stones began to glow.", audioUrl: "", durationMs: 5600, pronunciation: ""),
        SentenceAudio(index: 2, text: "Every story became a new path into English.", audioUrl: "", durationMs: 4700, pronunciation: "")
    ]

    static let contents: [Content] = [
        Content(
            id: "sample-lost-city",
            title: "The Lost City of Z",
            author: "LingoRise",
            summary: "A short immersive story for listening, reading, and speaking practice.",
            category: categories[0],
            level: "B1",
            duration: "15 min",
            imageUrl: "",
            durationMs: 900000,
            sentences: sentences,
            isPremium: false,
            createdAt: Date(),
            wordCount: 840,
            targetWords: [
                TargetWord(text: "mist", pronunciation: "/mɪst/", audioUrl: ""),
                TargetWord(text: "ancient", pronunciation: "/ˈeɪnʃənt/", audioUrl: ""),
                TargetWord(text: "journey", pronunciation: "/ˈdʒɜːrni/", audioUrl: "")
            ],
            contentType: .story,
            rating: 4.8,
            ratingCount: 124,
            accent: .us,
            newsScope: nil,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
            practiceSentenceIndexes: [0, 1, 2]
        ),
        Content(
            id: "sample-coffee",
            title: "Coffee Culture in Italy",
            author: "LingoRise",
            summary: "Learn everyday English through a warm travel scene in an Italian cafe.",
            category: categories[1],
            level: "A2",
            duration: "8 min",
            imageUrl: "",
            durationMs: 480000,
            sentences: sentences,
            isPremium: true,
            createdAt: Date().addingTimeInterval(-86400),
            wordCount: 520,
            targetWords: [TargetWord(text: "culture", pronunciation: "/ˈkʌltʃər/", audioUrl: "")],
            contentType: .article,
            rating: 4.6,
            ratingCount: 89,
            accent: .uk,
            newsScope: nil,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
            practiceSentenceIndexes: [0, 1]
        ),
        Content(
            id: "sample-tech",
            title: "Tech Trends 2024",
            author: "LingoRise",
            summary: "A modern reading about technology, habits, and clear business vocabulary.",
            category: categories[2],
            level: "B2",
            duration: "12 min",
            imageUrl: "",
            durationMs: 720000,
            sentences: sentences,
            isPremium: true,
            createdAt: Date().addingTimeInterval(-172800),
            wordCount: 720,
            targetWords: [TargetWord(text: "trend", pronunciation: "/trend/", audioUrl: "")],
            contentType: .news,
            rating: nil,
            ratingCount: 0,
            accent: .us,
            newsScope: .global,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
            practiceSentenceIndexes: [1, 2]
        )
    ]
}
