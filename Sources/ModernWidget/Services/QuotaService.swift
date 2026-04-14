import Foundation

enum QuotaServiceError: LocalizedError {
    case badStatus(Int)
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case let .badStatus(statusCode):
            return "server returned HTTP \(statusCode)"
        case .unsupportedResponse:
            return "response was not valid JSON"
        }
    }
}

struct QuotaService {
    func fetch(from url: URL) async throws -> QuotaSnapshot {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw QuotaServiceError.badStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(JSONValue.self, from: data) else {
            throw QuotaServiceError.unsupportedResponse
        }

        return QuotaSnapshot(
            fetchedAt: Date(),
            pairs: value.flattenedPairs(limit: 12)
        )
    }
}
