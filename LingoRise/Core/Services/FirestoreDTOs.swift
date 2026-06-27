import Foundation

struct FirestoreListResponse: Decodable {
    let documents: [FirestoreDocument]?
}

struct FirestoreDocument: Decodable {
    let name: String
    let fields: [String: FirestoreValue]?

    var documentId: String {
        name.split(separator: "/").last.map(String.init) ?? ""
    }

    func string(_ key: String) -> String? { fields?[key]?.stringValue }
    func bool(_ key: String) -> Bool? { fields?[key]?.booleanValue }
    func int(_ key: String) -> Int? { fields?[key]?.intValue }
    func double(_ key: String) -> Double? { fields?[key]?.doubleValue }
    func array(_ key: String) -> [FirestoreValue] { fields?[key]?.arrayValue?.values ?? [] }
    func timestamp(_ key: String) -> Date? {
        guard let text = fields?[key]?.timestampValue else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

indirect enum FirestoreValue: Decodable {
    case stringValue(String)
    case integerValue(String)
    case doubleValue(Double)
    case booleanValue(Bool)
    case timestampValue(String)
    case arrayValue(FirestoreArray)
    case mapValue(FirestoreMap)
    case null

    var stringValue: String? {
        if case let .stringValue(value) = self { return value }
        return nil
    }

    var booleanValue: Bool? {
        if case let .booleanValue(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .integerValue(value): return Int(value)
        case let .doubleValue(value): return Int(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .doubleValue(value): return value
        case let .integerValue(value): return Double(value)
        default: return nil
        }
    }

    var timestampValue: String? {
        if case let .timestampValue(value) = self { return value }
        return nil
    }

    var arrayValue: FirestoreArray? {
        if case let .arrayValue(value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .stringValue(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .integerValue) {
            self = .integerValue(value)
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .doubleValue(value)
        } else if let value = try container.decodeIfPresent(Bool.self, forKey: .booleanValue) {
            self = .booleanValue(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .timestampValue) {
            self = .timestampValue(value)
        } else if let value = try container.decodeIfPresent(FirestoreArray.self, forKey: .arrayValue) {
            self = .arrayValue(value)
        } else if let value = try container.decodeIfPresent(FirestoreMap.self, forKey: .mapValue) {
            self = .mapValue(value)
        } else {
            self = .null
        }
    }

    enum CodingKeys: String, CodingKey {
        case stringValue
        case integerValue
        case doubleValue
        case booleanValue
        case timestampValue
        case arrayValue
        case mapValue
    }
}

struct FirestoreArray: Decodable {
    let values: [FirestoreValue]?
}

struct FirestoreMap: Decodable {
    let fields: [String: FirestoreValue]?
}

struct CallablePackageResponse: Decodable {
    let result: StoryPackage

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let package = try container.decodeIfPresent(StoryPackage.self, forKey: .result) {
            result = package
            return
        }
        if let data = try container.decodeIfPresent(StoryPackage.self, forKey: .data) {
            result = data
            return
        }
        result = try StoryPackage(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case result
        case data
    }
}

struct StoryPackage: Decodable {
    let sentences: [SentenceAudio]
    let targetWords: [TargetWord]
    let practiceSentenceIndexes: [Int]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentences = try container.decodeIfPresent([SentenceAudio].self, forKey: .sentences) ?? []
        targetWords = try container.decodeIfPresent([TargetWord].self, forKey: .targetWords) ?? []
        practiceSentenceIndexes = try container.decodeIfPresent([Int].self, forKey: .practiceSentenceIndexes) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case sentences
        case targetWords
        case practiceSentenceIndexes
    }
}
