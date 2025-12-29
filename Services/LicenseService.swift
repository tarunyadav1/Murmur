import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "License")

/// Errors that can occur during license validation
enum LicenseError: LocalizedError {
    case invalidLicenseKey
    case emptyLicenseKey
    case networkError(String)
    case refundedPurchase
    case disputedPurchase
    case serverError(String)
    case noStoredLicense

    var errorDescription: String? {
        switch self {
        case .invalidLicenseKey:
            return "The license key is invalid. Please check and try again."
        case .emptyLicenseKey:
            return "Please enter a license key."
        case .networkError(let message):
            return "Network error: \(message). Please check your connection."
        case .refundedPurchase:
            return "This purchase has been refunded."
        case .disputedPurchase:
            return "This purchase is under dispute."
        case .serverError(let message):
            return "Server error: \(message)"
        case .noStoredLicense:
            return "No license found. Please enter your license key."
        }
    }
}

/// Validation state for UI display
enum LicenseValidationState: Equatable {
    case idle
    case validating
    case valid
    case invalid(String)
}

/// Service for validating and caching Gumroad licenses
@MainActor
final class LicenseService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var licenseInfo: LicenseInfo?
    @Published private(set) var validationState: LicenseValidationState = .idle
    @Published var licenseKeyInput: String = ""

    // MARK: - Private Properties

    private let userDefaults: UserDefaults
    private let session: URLSession
    private let gumroadAPIURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    // MARK: - Computed Properties

    /// Whether the app is licensed and can be used
    var isLicensed: Bool {
        return licenseInfo?.canUseLicense ?? false
    }

    /// Whether we need to re-validate (cache expired)
    var needsRevalidation: Bool {
        guard let info = licenseInfo else { return true }
        return !info.isWithinGracePeriod
    }

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        loadStoredLicense()
    }

    // MARK: - License Storage

    private func loadStoredLicense() {
        guard let data = userDefaults.data(forKey: Constants.UserDefaultsKeys.license),
              let decoded = try? JSONDecoder().decode(LicenseInfo.self, from: data) else {
            licenseInfo = nil
            return
        }
        licenseInfo = decoded
        logger.info("Loaded stored license: \(decoded.licenseKey.prefix(8))...")
    }

    private func saveLicense(_ info: LicenseInfo) {
        if let encoded = try? JSONEncoder().encode(info) {
            userDefaults.set(encoded, forKey: Constants.UserDefaultsKeys.license)
        }
        licenseInfo = info
    }

    /// Clear stored license (for testing/support)
    func clearLicense() {
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.license)
        licenseInfo = nil
        licenseKeyInput = ""
        validationState = .idle
        logger.info("License cleared")
    }

    // MARK: - Validation

    /// Check license on app launch - uses cache if within grace period
    func checkLicenseOnLaunch() async -> Bool {
        guard let info = licenseInfo else {
            logger.info("No stored license")
            return false
        }

        if info.canUseLicense {
            logger.info("License within grace period, skipping re-validation")
            validationState = .valid
            return true
        }

        // Cache expired, need to re-validate
        logger.info("Cache expired, re-validating...")
        do {
            _ = try await validateLicense(info.licenseKey)
            return true
        } catch {
            logger.error("Re-validation failed: \(error.localizedDescription)")
            validationState = .invalid(error.localizedDescription)
            return false
        }
    }

    /// Validate a license key with Gumroad API
    @discardableResult
    func validateLicense(_ key: String? = nil) async throws -> LicenseInfo {
        let licenseKey = (key ?? licenseKeyInput).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !licenseKey.isEmpty else {
            throw LicenseError.emptyLicenseKey
        }

        validationState = .validating
        logger.info("Validating license: \(licenseKey.prefix(8))...")

        do {
            // Build request
            var request = URLRequest(url: gumroadAPIURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let productId = Constants.License.gumroadProductId
            let encodedKey = licenseKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? licenseKey
            let encodedProductId = productId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? productId
            let body = "product_id=\(encodedProductId)&license_key=\(encodedKey)"
            request.httpBody = body.data(using: .utf8)

            // Make request
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                validationState = .invalid("Invalid response")
                throw LicenseError.networkError("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let message = httpResponse.statusCode == 404 ? "Invalid license key" : "Server error (HTTP \(httpResponse.statusCode))"
                validationState = .invalid(message)
                throw LicenseError.serverError(message)
            }

            // Parse response
            let decoder = JSONDecoder()
            let gumroadResponse = try decoder.decode(GumroadLicenseResponse.self, from: data)

            // Check for success
            guard gumroadResponse.success else {
                let message = gumroadResponse.message ?? "Invalid license key"
                logger.warning("License invalid: \(message)")
                validationState = .invalid(message)
                throw LicenseError.invalidLicenseKey
            }

            // Check purchase status
            if let purchase = gumroadResponse.purchase {
                if purchase.refunded {
                    validationState = .invalid("Purchase refunded")
                    throw LicenseError.refundedPurchase
                }
                if purchase.disputed ?? false || purchase.chargebacked ?? false {
                    validationState = .invalid("Purchase disputed")
                    throw LicenseError.disputedPurchase
                }
            }

            // Create and save license info
            let info = LicenseInfo(
                licenseKey: licenseKey,
                lastValidatedAt: Date(),
                isValid: true,
                email: gumroadResponse.purchase?.email,
                productName: gumroadResponse.purchase?.productName,
                purchaseDate: gumroadResponse.purchase?.purchaseDate
            )

            saveLicense(info)
            validationState = .valid
            logger.info("License validated successfully")

            return info

        } catch let error as LicenseError {
            throw error
        } catch let error as DecodingError {
            logger.error("Decoding error: \(error.localizedDescription)")
            validationState = .invalid("Invalid server response")
            throw LicenseError.serverError("Invalid response format")
        } catch {
            logger.error("Validation error: \(error.localizedDescription)")
            validationState = .invalid("Network error. Please check your connection.")
            throw LicenseError.networkError(error.localizedDescription)
        }
    }
}
