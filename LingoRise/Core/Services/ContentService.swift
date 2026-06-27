import Foundation

#if canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
enum ContentServiceError: Error {
    case storyNotFound
    case packageFailed(statusCode: Int, body: String)
}

@MainActor
final class ContentService {
    private let projectId = "lingorise-d8497"
    private let functionsRegion = "europe-west1"
    private let session: URLSession
    private var categoryCache: [Category]?
    private var catalogCache: [Content]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getCategories() async throws -> [Category] {
        if let categoryCache { return categoryCache }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let categories = try await fetchFirestoreCategories()
                if !categories.isEmpty {
                    categoryCache = categories
                    return categories
                }
            } catch {
                debugLog("firestore_categories_failed", error)
            }
        }
        #endif
        do {
            let docs = try await fetchDocuments(collection: "categories")
            let categories = docs.compactMap(Self.category(from:)).sorted { lhs, rhs in
                lhs.title < rhs.title
            }
            if !categories.isEmpty {
                categoryCache = categories
                return categories
            }
        } catch {}
        categoryCache = SampleData.categories
        return SampleData.categories
    }

    func getDailyPick() async throws -> Content? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateId = formatter.string(from: Date())
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let document = try await Firestore.firestore()
                    .collection("daily_picks")
                    .document(dateId)
                    .getDocument()
                if let contentId = document.data()?["contentId"] as? String, !contentId.isEmpty {
                    return try await getContent(id: contentId)
                }
            } catch {
                debugLog("firestore_daily_pick_failed", error)
            }
        }
        #endif
        do {
            let document = try await fetchDocument(collection: "daily_picks", id: dateId)
            if let contentId = document.string("contentId"), !contentId.isEmpty {
                return try await getContent(id: contentId)
            }
        } catch {}
        return try await getExploreStories().first
    }

    func getStories(categoryId: String, limit: Int) async throws -> [Content] {
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                return try await fetchFirestoreStories(categoryId: categoryId, limit: limit)
            } catch {
                debugLog("firestore_category_stories_failed", error)
            }
        }
        #endif
        return Array(try await getExploreStories().filter { $0.category.id == categoryId }.prefix(limit))
    }

    func getExploreStories() async throws -> [Content] {
        if let catalogCache { return catalogCache }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let contents = try await fetchFirestoreCatalog()
                if !contents.isEmpty {
                    catalogCache = contents
                    return contents
                }
            } catch {
                debugLog("firestore_catalog_failed", error)
            }
        }
        #endif
        do {
            let docs = try await fetchDocuments(collection: "content_catalog")
            let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
            let contents = docs.compactMap { Self.content(from: $0, categories: categories) }
                .filter { !$0.title.isEmpty }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            if !contents.isEmpty {
                catalogCache = contents
                return contents
            }
        } catch {}
        catalogCache = SampleData.contents
        return SampleData.contents
    }

    func getExploreStoriesPage(
        limit: Int,
        startAfterDocId: String?,
        searchQuery: String?,
        selectedLevels: Set<String>,
        selectedCategories: Set<String>,
        sortOption: ExploreSortOption
    ) async throws -> ExplorePageResult {
        var contents = try await getExploreStories()
        if let searchQuery, !searchQuery.isEmpty {
            let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if needle.count >= 3 {
                contents = contents.filter { content in
                    content.title.localizedCaseInsensitiveContains(needle)
                        || content.author.localizedCaseInsensitiveContains(needle)
                        || content.summary.localizedCaseInsensitiveContains(needle)
                        || content.category.title.localizedCaseInsensitiveContains(needle)
                        || content.targetWords.contains { $0.text.localizedCaseInsensitiveContains(needle) }
                }
            }
        }
        if !selectedLevels.isEmpty {
            let levels = Set(selectedLevels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
            contents = contents.filter { levels.contains($0.level.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
        }
        if !selectedCategories.isEmpty {
            contents = contents.filter { selectedCategories.contains($0.category.id) }
        }
        contents = sortExplore(contents, option: sortOption)

        let startIndex: Int
        if let startAfterDocId,
           let foundIndex = contents.firstIndex(where: { $0.id == startAfterDocId }) {
            startIndex = contents.index(after: foundIndex)
        } else {
            startIndex = contents.startIndex
        }
        guard startIndex < contents.endIndex else {
            return ExplorePageResult(items: [], lastCreatedAt: nil, lastDocId: startAfterDocId, hasMore: false)
        }

        let endIndex = contents.index(startIndex, offsetBy: max(limit, 0), limitedBy: contents.endIndex) ?? contents.endIndex
        let pageItems = Array(contents[startIndex..<endIndex])
        return ExplorePageResult(
            items: pageItems,
            lastCreatedAt: pageItems.last?.createdAt,
            lastDocId: pageItems.last?.id ?? startAfterDocId,
            hasMore: endIndex < contents.endIndex
        )
    }

    private func sortExplore(_ contents: [Content], option: ExploreSortOption) -> [Content] {
        switch option {
        case .newest:
            return contents.sorted {
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        case .shortestDuration:
            return contents.sorted {
                let lhsDuration = durationMsForSort($0)
                let rhsDuration = durationMsForSort($1)
                if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        case .longestDuration:
            return contents.sorted {
                let lhsMissing = durationMsForSort($0) == Int.max
                let rhsMissing = durationMsForSort($1) == Int.max
                if lhsMissing != rhsMissing { return !lhsMissing }
                let lhsDuration = durationMsForSort($0) == Int.max ? Int.min : durationMsForSort($0)
                let rhsDuration = durationMsForSort($1) == Int.max ? Int.min : durationMsForSort($1)
                if lhsDuration != rhsDuration { return lhsDuration > rhsDuration }
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        }
    }

    private func durationMsForSort(_ content: Content) -> Int {
        if content.durationMs > 0 { return content.durationMs }
        let sentenceDuration = content.sentences.reduce(0) { $0 + $1.durationMs }
        if sentenceDuration > 0 { return sentenceDuration }
        return durationLabelToMs(content.duration) ?? Int.max
    }

    private func durationLabelToMs(_ duration: String) -> Int? {
        let normalized = duration.lowercased()
        if let minutes = firstNumber(in: normalized, units: ["min", "minute", "minutes", "dk"]) {
            return minutes * 60_000
        }
        if let seconds = firstNumber(in: normalized, units: ["sec", "second", "seconds", "sn"]) {
            return seconds * 1_000
        }
        guard let number = normalized.firstMatchNumber else { return nil }
        return number * 60_000
    }

    private func firstNumber(in value: String, units: [String]) -> Int? {
        for unit in units {
            let pattern = #"(\d+)\s*"# + NSRegularExpression.escapedPattern(for: unit)
            if let number = value.firstMatchNumber(pattern: pattern) {
                return number
            }
        }
        return nil
    }

    func getContent(id: String) async throws -> Content? {
        if let cached = try await getExploreStories().first(where: { $0.id == id }) {
            return cached
        }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
                let document = try await Firestore.firestore()
                    .collection("content_catalog")
                    .document(id)
                    .getDocument()
                if let content = Self.content(id: document.documentID, data: document.data() ?? [:], categories: categories) {
                    return content
                }
            } catch {
                debugLog("firestore_content_failed", error)
            }
        }
        #endif
        do {
            let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
            let doc = try await fetchDocument(collection: "content_catalog", id: id)
            return Self.content(from: doc, categories: categories)
        } catch {
            return SampleData.contents.first(where: { $0.id == id })
        }
    }

    func getStoryPackage(id: String) async throws -> Content {
        guard let metadata = try await getContent(id: id) else {
            throw ContentServiceError.storyNotFound
        }
        do {
            let package = try await callContentPackage(id: id)
            return metadata.withPackage(
                sentences: package.sentences.isEmpty ? metadata.sentences : package.sentences,
                targetWords: package.targetWords.isEmpty ? metadata.targetWords : package.targetWords,
                practiceSentenceIndexes: package.practiceSentenceIndexes
            )
        } catch {
            debugLog("content_package_failed", error)
            return metadata
        }
    }

    func updateCurrentRating(storyId: String, averageRating: Double, ratingCount: Int) {
        catalogCache = catalogCache?.map { content in
            content.id == storyId
                ? content.withRating(averageRating: averageRating, ratingCount: ratingCount)
                : content
        }
    }

    #if canImport(FirebaseFirestore)
    private func fetchFirestoreCategories() async throws -> [Category] {
        let snapshot = try await Firestore.firestore()
            .collection("categories")
            .getDocuments()

        return snapshot.documents
            .filter { ($0.data()["active"] as? Bool) ?? true }
            .sorted { lhs, rhs in
                Self.intValue(lhs.data()["order"]) < Self.intValue(rhs.data()["order"])
            }
            .compactMap { Self.category(id: $0.documentID, data: $0.data()) }
    }

    private func fetchFirestoreStories(categoryId: String, limit: Int) async throws -> [Content] {
        let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
        let snapshot = try await Firestore.firestore()
            .collection("content_catalog")
            .whereField("categoryId", isEqualTo: categoryId)
            .whereField("status", isEqualTo: "published")
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            Self.content(id: $0.documentID, data: $0.data(), categories: categories)
        }
    }

    private func fetchFirestoreCatalog() async throws -> [Content] {
        let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
        let snapshot = try await Firestore.firestore()
            .collection("content_catalog")
            .whereField("status", isEqualTo: "published")
            .order(by: "publishedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap {
            Self.content(id: $0.documentID, data: $0.data(), categories: categories)
        }
    }
    #endif

    private func fetchDocuments(collection: String) async throws -> [FirestoreDocument] {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return response.documents ?? []
    }

    private func fetchDocument(collection: String, id: String) async throws -> FirestoreDocument {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)/\(id)")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(FirestoreDocument.self, from: data)
    }

    private func callContentPackage(id: String) async throws -> StoryPackage {
        #if canImport(FirebaseFunctions)
        if FirebaseApp.app() != nil {
            let result = try await Functions.functions(region: functionsRegion)
                .httpsCallable("getContentPackage")
                .call(["contentId": id])
            let data = try JSONSerialization.data(withJSONObject: result.data)
            return try JSONDecoder().decode(StoryPackage.self, from: data)
        }
        #endif

        let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/getContentPackage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["contentId": id]])
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw ContentServiceError.packageFailed(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(CallablePackageResponse.self, from: data)
        return decoded.result
    }

    private static func category(from doc: FirestoreDocument) -> Category? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? id
        return Category(id: id, title: title, symbol: symbol(for: doc.string("iconName")))
    }

    private static func category(id documentId: String, data: [String: Any]) -> Category? {
        let id = stringValue(data["id"]) ?? documentId
        let title = stringValue(data["title"]) ?? id
        return Category(id: id, title: title, symbol: symbol(for: stringValue(data["iconName"])))
    }

    private static func content(from doc: FirestoreDocument, categories: [String: Category]) -> Content? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? ""
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let categoryId = doc.string("categoryId") ?? ""
        let category = categories[categoryId] ?? Category(id: categoryId, title: categoryId.isEmpty ? "Stories" : categoryId, symbol: "book.fill")
        let type = ContentType(rawValue: (doc.string("contentType") ?? "story").lowercased()) ?? .story
        let accent = EnglishAccent(rawValue: doc.string("accent") ?? "en-US") ?? .us
        let newsScope = doc.string("newsScope").flatMap { NewsScope(rawValue: $0.lowercased()) }
        return Content(
            id: id,
            title: title,
            author: doc.string("author") ?? "",
            summary: doc.string("summary") ?? "",
            category: category,
            level: doc.string("level") ?? "",
            duration: doc.string("duration") ?? "",
            imageUrl: doc.string("imageUrl") ?? "",
            durationMs: doc.int("durationMs") ?? 0,
            sentences: [],
            isPremium: doc.bool("isPremium") ?? true,
            createdAt: doc.timestamp("publishedAt"),
            wordCount: doc.int("wordCount") ?? 0,
            targetWords: doc.array("targetWords").compactMap(Self.targetWord),
            contentType: type,
            rating: doc.double("averageRating").flatMap { $0 > 0 ? $0 : nil },
            ratingCount: doc.int("ratingCount") ?? 0,
            accent: accent,
            newsScope: newsScope,
            regionCode: doc.string("regionCode") ?? "",
            regionLabel: doc.string("regionLabel") ?? "",
            countryCodes: doc.array("countryCodes").compactMap(\.stringValue),
            sourceReferences: doc.array("sourceReferences").compactMap(Self.sourceReference),
            imageAttribution: doc.fields?["imageAttribution"].flatMap(Self.imageAttribution),
            practiceSentenceIndexes: []
        )
    }

    private static func content(id documentId: String, data: [String: Any], categories: [String: Category]) -> Content? {
        let id = stringValue(data["id"]) ?? documentId
        let title = stringValue(data["title"]) ?? ""
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let categoryId = stringValue(data["categoryId"]) ?? ""
        let category = categories[categoryId] ?? Category(id: categoryId, title: categoryId.isEmpty ? "Stories" : categoryId, symbol: "book.fill")
        let type = ContentType(rawValue: (stringValue(data["contentType"]) ?? "story").lowercased()) ?? .story
        let accent = EnglishAccent(rawValue: stringValue(data["accent"]) ?? "en-US") ?? .us
        let newsScope = stringValue(data["newsScope"]).flatMap { NewsScope(rawValue: $0.lowercased()) }
        return Content(
            id: id,
            title: title,
            author: stringValue(data["author"]) ?? "",
            summary: stringValue(data["summary"]) ?? "",
            category: category,
            level: stringValue(data["level"]) ?? "",
            duration: stringValue(data["duration"]) ?? "",
            imageUrl: stringValue(data["imageUrl"]) ?? "",
            durationMs: intValue(data["durationMs"]),
            sentences: [],
            isPremium: boolValue(data["isPremium"]) ?? true,
            createdAt: dateValue(data["publishedAt"]) ?? dateValue(data["createdAt"]),
            wordCount: intValue(data["wordCount"]),
            targetWords: targetWords(data["targetWords"]),
            contentType: type,
            rating: doubleValue(data["averageRating"]).flatMap { $0 > 0 ? $0 : nil },
            ratingCount: intValue(data["ratingCount"]),
            accent: accent,
            newsScope: newsScope,
            regionCode: stringValue(data["regionCode"]) ?? "",
            regionLabel: stringValue(data["regionLabel"]) ?? "",
            countryCodes: stringArray(data["countryCodes"]),
            sourceReferences: sourceReferences(data["sourceReferences"]),
            imageAttribution: imageAttribution(data["imageAttribution"]),
            practiceSentenceIndexes: []
        )
    }

    private static func targetWord(_ value: FirestoreValue) -> TargetWord? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return TargetWord(
            text: fields["text"]?.stringValue ?? "",
            pronunciation: fields["pronunciation"]?.stringValue ?? "",
            audioUrl: fields["audioUrl"]?.stringValue ?? ""
        )
    }

    private static func sourceReference(_ value: FirestoreValue) -> SourceReference? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return SourceReference(
            title: fields["title"]?.stringValue ?? "",
            publisher: fields["publisher"]?.stringValue ?? "",
            url: fields["url"]?.stringValue ?? "",
            publishedAt: fields["publishedAt"]?.stringValue ?? "",
            countryCode: fields["countryCode"]?.stringValue ?? "",
            isLocal: fields["isLocal"]?.booleanValue ?? false
        )
    }

    private static func imageAttribution(_ value: FirestoreValue) -> ImageAttribution? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return ImageAttribution(
            source: fields["source"]?.stringValue ?? "",
            creator: fields["creator"]?.stringValue ?? "",
            sourcePageUrl: fields["sourcePageUrl"]?.stringValue ?? "",
            license: fields["license"]?.stringValue ?? "",
            attribution: fields["attribution"]?.stringValue ?? ""
        )
    }

    private static func targetWords(_ raw: Any?) -> [TargetWord] {
        (raw as? [[String: Any]])?.compactMap { item in
            guard let text = stringValue(item["text"]), !text.isEmpty else { return nil }
            return TargetWord(
                text: text,
                pronunciation: stringValue(item["pronunciation"]) ?? "",
                audioUrl: stringValue(item["audioUrl"]) ?? ""
            )
        } ?? []
    }

    private static func sourceReferences(_ raw: Any?) -> [SourceReference] {
        (raw as? [[String: Any]])?.compactMap { item in
            guard let publisher = stringValue(item["publisher"]),
                  let url = stringValue(item["url"]) else { return nil }
            return SourceReference(
                title: stringValue(item["title"]) ?? "",
                publisher: publisher,
                url: url,
                publishedAt: stringValue(item["publishedAt"]) ?? "",
                countryCode: stringValue(item["countryCode"]) ?? "",
                isLocal: boolValue(item["isLocal"]) ?? false
            )
        } ?? []
    }

    private static func imageAttribution(_ raw: Any?) -> ImageAttribution? {
        guard let item = raw as? [String: Any] else { return nil }
        return ImageAttribution(
            source: stringValue(item["source"]) ?? "",
            creator: stringValue(item["creator"]) ?? "",
            sourcePageUrl: stringValue(item["sourcePageUrl"]) ?? "",
            license: stringValue(item["license"]) ?? "",
            attribution: stringValue(item["attribution"]) ?? ""
        )
    }

    private static func stringArray(_ raw: Any?) -> [String] {
        (raw as? [String]) ?? (raw as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func stringValue(_ raw: Any?) -> String? {
        raw as? String
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        return 0
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return nil
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        #if canImport(FirebaseFirestore)
        if let timestamp = raw as? Timestamp {
            return timestamp.dateValue()
        }
        #endif
        return raw as? Date
    }

    private func debugLog(_ message: String, _ error: Error) {
        #if DEBUG
        print(message, error.localizedDescription)
        #endif
    }

    private static func symbol(for iconName: String?) -> String {
        switch iconName {
        case "TravelExplore", "Public": return "airplane"
        case "Business": return "briefcase.fill"
        case "Science": return "atom"
        case "LocalCafe": return "cup.and.saucer.fill"
        case "Explore": return "safari.fill"
        case "Movie": return "film.fill"
        case "People": return "person.2.fill"
        case "Article": return "doc.text.fill"
        default: return "book.fill"
        }
    }
}
