import Foundation

extension String {
    var firstMatchNumber: Int? {
        firstMatchNumber(pattern: #"\d+"#)
    }

    func firstMatchNumber(pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else {
            return nil
        }
        let matchedRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
            ? match.range(at: 1)
            : match.range
        guard let range = Range(matchedRange, in: self) else { return nil }
        return Int(self[range])
    }
}
