import Foundation

struct PracticePuzzleToken: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct PracticePuzzleSegment: Identifiable, Hashable {
    let id: Int
    let correctTokens: [PracticePuzzleToken]
    let shuffledTokens: [PracticePuzzleToken]

    var text: String {
        correctTokens.map(\.text).joined(separator: " ")
    }
}

struct ListeningPuzzle: Identifiable, Hashable {
    var id: Int { sentenceIndex }
    let sentenceIndex: Int
    let audioUrl: String
    let segments: [PracticePuzzleSegment]
    let correctTokens: [PracticePuzzleToken]
    let shuffledTokens: [PracticePuzzleToken]
}

func selectListeningPuzzleSentences(
    sentences: [SentenceAudio],
    preferredIndexes: [Int],
    level: String
) -> [SentenceAudio] {
    let preferred = preferredIndexes.compactMap { index in sentences.first(where: { $0.index == index }) }
    let fallback = sentences.filter { sentence in !preferred.contains(where: { $0.index == sentence.index }) }
    let ordered = uniqueByIndex(preferred + fallback)
    let ideal = Array(ordered.filter { isEligiblePuzzleSentence($0, level: level, flexible: false) }.prefix(3))
    if ideal.count >= 2 { return ideal }

    let selectedIndexes = Set(ideal.map(\.index))
    let flexible = ordered
        .filter { !selectedIndexes.contains($0.index) }
        .filter { isEligiblePuzzleSentence($0, level: level, flexible: true) }
        .sorted { lhs, rhs in
            let rules = levelRules(level)
            let left = tokenRangeDistance(tokenizeSentence(lhs.text).count, rules: rules)
            let right = tokenRangeDistance(tokenizeSentence(rhs.text).count, rules: rules)
            if left != right { return left < right }
            return (ordered.firstIndex(where: { $0.index == lhs.index }) ?? 0) < (ordered.firstIndex(where: { $0.index == rhs.index }) ?? 0)
        }
    return Array(uniqueByIndex(ideal + flexible).prefix(3))
}

private func isEligiblePuzzleSentence(_ sentence: SentenceAudio, level: String, flexible: Bool) -> Bool {
    guard !sentence.audioUrl.isEmpty else { return false }
    let tokens = tokenizeSentence(sentence.text)
    let rules = levelRules(level)
    guard tokens.count >= 5 else { return false }
    if !flexible, !(rules.minTokens...rules.maxTokens).contains(tokens.count) { return false }
    if flexible, tokens.count > 24 { return false }
    if !flexible, sentence.text.count > 130 { return false }
    if flexible, sentence.text.count > 170 { return false }
    if !flexible, [":", ";", "(", ")", "—"].contains(where: { sentence.text.contains($0) }) { return false }
    if buildPuzzleSegments(tokens: tokens, sentenceIndex: sentence.index, sentenceText: sentence.text, storyId: "", rules: rules).isEmpty { return false }
    let counts = Dictionary(grouping: tokens.map { $0.lowercased() }, by: { $0 }).mapValues(\.count)
    return !counts.values.contains { $0 >= 3 }
}

func sentenceToListeningPuzzle(_ sentence: SentenceAudio, storyId: String, level: String) -> ListeningPuzzle {
    let rules = levelRules(level)
    let tokens = tokenizeSentence(sentence.text)
    let segments = buildPuzzleSegments(tokens: tokens, sentenceIndex: sentence.index, sentenceText: sentence.text, storyId: storyId, rules: rules)
    let correctTokens = tokens.enumerated().map { PracticePuzzleToken(id: $0.offset, text: $0.element) }
    var shuffled = stableShuffle(correctTokens, seed: stableSeed("\(storyId)_\(sentence.index)_\(sentence.text)"))
    if shuffled.map(\.id) == correctTokens.map(\.id), shuffled.count > 1 {
        shuffled = Array(shuffled.dropFirst() + shuffled.prefix(1))
    }
    return ListeningPuzzle(
        sentenceIndex: sentence.index,
        audioUrl: sentence.audioUrl,
        segments: segments,
        correctTokens: correctTokens,
        shuffledTokens: shuffled
    )
}

private func tokenizeSentence(_ text: String) -> [String] {
    let pattern = #"\d+(?:[.,]\d+)?|[A-Za-z]+(?:'[A-Za-z]+)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        Range(match.range, in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
    }.filter { !$0.isEmpty }
}

private func buildPuzzleSegments(
    tokens: [String],
    sentenceIndex: Int,
    sentenceText: String,
    storyId: String,
    rules: LevelPuzzleRules
) -> [PracticePuzzleSegment] {
    guard let segmentCount = chooseSegmentCount(tokenCount: tokens.count, rules: rules) else { return [] }
    let sizes = balancedSegmentSizes(tokenCount: tokens.count, segmentCount: segmentCount)
    let seed = stableSeed("\(storyId)_\(sentenceIndex)_\(sentenceText)")
    var nextTokenId = 0
    var cursor = 0
    return sizes.enumerated().map { segmentIndex, size in
        let correct = tokens[cursor..<(cursor + size)].map { token -> PracticePuzzleToken in
            defer { nextTokenId += 1 }
            return PracticePuzzleToken(id: nextTokenId, text: token)
        }
        cursor += size
        var shuffled = stableShuffle(correct, seed: seed + segmentIndex)
        if shuffled.count > 1, shuffled.map(\.id) == correct.map(\.id) {
            shuffled = Array(shuffled.dropFirst() + shuffled.prefix(1))
        }
        return PracticePuzzleSegment(id: segmentIndex, correctTokens: correct, shuffledTokens: shuffled)
    }
}

private func chooseSegmentCount(tokenCount: Int, rules: LevelPuzzleRules) -> Int? {
    let maxSegmentsByTokenCount = tokenCount / 2
    let upper = min(rules.maxSegments, maxSegmentsByTokenCount)
    return upper < 1 ? nil : upper
}

private func balancedSegmentSizes(tokenCount: Int, segmentCount: Int) -> [Int] {
    let base = tokenCount / segmentCount
    let remainder = tokenCount % segmentCount
    return (0..<segmentCount).map { base + ($0 < remainder ? 1 : 0) }
}

private func levelRules(_ level: String) -> LevelPuzzleRules {
    switch level.uppercased() {
    case "A1": return LevelPuzzleRules(minTokens: 5, maxTokens: 7, maxSegments: 2)
    case "A2": return LevelPuzzleRules(minTokens: 6, maxTokens: 9, maxSegments: 3)
    case "B1": return LevelPuzzleRules(minTokens: 8, maxTokens: 12, maxSegments: 4)
    case "B2": return LevelPuzzleRules(minTokens: 10, maxTokens: 16, maxSegments: 5)
    case "C1": return LevelPuzzleRules(minTokens: 12, maxTokens: 20, maxSegments: 6)
    default: return LevelPuzzleRules(minTokens: 8, maxTokens: 12, maxSegments: 4)
    }
}

private func tokenRangeDistance(_ tokenCount: Int, rules: LevelPuzzleRules) -> Int {
    if tokenCount < rules.minTokens { return rules.minTokens - tokenCount }
    if tokenCount > rules.maxTokens { return tokenCount - rules.maxTokens }
    return 0
}

private struct LevelPuzzleRules {
    let minTokens: Int
    let maxTokens: Int
    let maxSegments: Int
}

private func uniqueByIndex(_ sentences: [SentenceAudio]) -> [SentenceAudio] {
    var seen = Set<Int>()
    return sentences.filter { seen.insert($0.index).inserted }
}

private func stableSeed(_ value: String) -> Int {
    var hash = 5381
    for scalar in value.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
    }
    return abs(hash)
}

func stableShuffle<T>(_ values: [T], seed: Int) -> [T] {
    guard values.count > 1 else { return values }
    var result = values
    var generator = SeededGenerator(seed: UInt64(max(seed, 1)))
    for index in stride(from: result.count - 1, through: 1, by: -1) {
        let randomIndex = Int(generator.next() % UInt64(index + 1))
        result.swapAt(index, randomIndex)
    }
    return result
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
