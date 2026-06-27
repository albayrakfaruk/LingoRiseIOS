import Foundation

#if canImport(FirebaseFunctions)
import FirebaseCore
import FirebaseFunctions
#endif

struct StoryRatingResult {
    let rating: Int
    let ratingCount: Int
    let averageRating: Double
}

@MainActor
final class StoryRatingService {
    private let projectId = "lingorise-d8497"
    private let functionsRegion = "europe-west1"
    private let session: URLSession
    private let preferences: AppPreferences

    init(session: URLSession = .shared, preferences: AppPreferences = .shared) {
        self.session = session
        self.preferences = preferences
    }

    func getLocalRating(storyId: String) -> Int {
        preferences.getStoryRating(storyId: storyId)
    }

    func rateStory(storyId: String, rating: Int) async throws -> StoryRatingResult {
        let normalized = min(max(rating, 1), 5)
        preferences.setStoryRating(storyId: storyId, rating: normalized)
        let ratingDeviceId = preferences.getOrCreateRatingDeviceId()

        #if canImport(FirebaseFunctions)
        if FirebaseApp.app() != nil {
            let result = try await Functions.functions(region: functionsRegion)
                .httpsCallable("rateContent")
                .call([
                    "contentId": storyId,
                    "rating": normalized,
                    "ratingDeviceId": ratingDeviceId
                ])
            let data = result.data as? [String: Any] ?? [:]
            return StoryRatingResult(
                rating: (data["rating"] as? NSNumber)?.intValue ?? normalized,
                ratingCount: (data["ratingCount"] as? NSNumber)?.intValue ?? 0,
                averageRating: (data["averageRating"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        #endif

        let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/rateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "contentId": storyId,
                "rating": normalized,
                "ratingDeviceId": ratingDeviceId
            ]
        ])

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(CallableRatingResponse.self, from: data)
        return StoryRatingResult(
            rating: decoded.result.rating ?? normalized,
            ratingCount: decoded.result.ratingCount ?? 0,
            averageRating: decoded.result.averageRating ?? 0
        )
    }
}

private struct CallableRatingResponse: Decodable {
    let result: RatingPayload
}

private struct RatingPayload: Decodable {
    let rating: Int?
    let ratingCount: Int?
    let averageRating: Double?
}
