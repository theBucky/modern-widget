import Foundation

struct QuotaSnapshot: Sendable {
    let fetchedAt: Date
    let pairs: [QuotaPair]
}

struct QuotaPair: Identifiable, Sendable {
    let id: Int
    let key: String
    let value: String
}
