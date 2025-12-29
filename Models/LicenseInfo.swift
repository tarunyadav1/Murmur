import Foundation

/// Represents the cached license validation state
struct LicenseInfo: Codable, Equatable {
    let licenseKey: String
    let lastValidatedAt: Date
    let isValid: Bool
    let email: String?
    let productName: String?
    let purchaseDate: Date?

    /// Check if the cached validation is still within the grace period
    var isWithinGracePeriod: Bool {
        let gracePeriod = TimeInterval(Constants.License.offlineGracePeriodDays * 24 * 60 * 60)
        return Date().timeIntervalSince(lastValidatedAt) < gracePeriod
    }

    /// Check if the license can be used (valid + within grace period)
    var canUseLicense: Bool {
        return isValid && isWithinGracePeriod
    }

    /// Date when the grace period expires
    var gracePeriodExpiresAt: Date {
        Calendar.current.date(
            byAdding: .day,
            value: Constants.License.offlineGracePeriodDays,
            to: lastValidatedAt
        ) ?? lastValidatedAt
    }
}

// MARK: - Gumroad API Response Models

/// Response from Gumroad license verification API
struct GumroadLicenseResponse: Decodable {
    let success: Bool
    let uses: Int?
    let purchase: GumroadPurchase?
    let message: String?
}

struct GumroadPurchase: Decodable {
    let id: String
    let productId: String
    let productName: String
    let email: String
    let createdAt: String
    let refunded: Bool
    let disputed: Bool?
    let chargebacked: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case productId = "product_id"
        case productName = "product_name"
        case email
        case createdAt = "created_at"
        case refunded
        case disputed
        case chargebacked
    }

    /// Check if purchase is in good standing
    var isInGoodStanding: Bool {
        return !refunded && !(disputed ?? false) && !(chargebacked ?? false)
    }

    /// Parse the created_at date
    var purchaseDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAt)
    }
}
