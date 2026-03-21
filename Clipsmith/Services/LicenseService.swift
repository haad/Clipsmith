import Foundation
import AppKit

// MARK: - Codable Response Types

struct LSActivateResponse: Codable, Sendable {
    let activated: Bool
    let error: String?
    let licenseKey: LSLicenseKey
    let instance: LSInstance
    let meta: LSMeta

    enum CodingKeys: String, CodingKey {
        case activated, error
        case licenseKey = "license_key"
        case instance, meta
    }
}

struct LSValidateResponse: Codable, Sendable {
    let valid: Bool
    let error: String?
    let licenseKey: LSLicenseKey
    let instance: LSInstance?
    let meta: LSMeta

    enum CodingKeys: String, CodingKey {
        case valid, error
        case licenseKey = "license_key"
        case instance, meta
    }
}

struct LSDeactivateResponse: Codable, Sendable {
    let deactivated: Bool
    let error: String?
    let licenseKey: LSLicenseKey
    let meta: LSMeta

    enum CodingKeys: String, CodingKey {
        case deactivated, error
        case licenseKey = "license_key"
        case meta
    }
}

struct LSLicenseKey: Codable, Sendable {
    let id: Int
    let status: String
    let key: String
    let activationLimit: Int
    let activationUsage: Int
    let createdAt: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct LSInstance: Codable, Sendable {
    let id: String
    let name: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct LSMeta: Codable, Sendable {
    let storeId: Int
    let orderId: Int
    let productId: Int
    let variantId: Int
    let customerName: String
    let customerEmail: String

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case orderId = "order_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case customerName = "customer_name"
        case customerEmail = "customer_email"
    }
}

// MARK: - LicenseError

enum LicenseError: Error, LocalizedError {
    case wrongProduct
    case activationLimitReached
    case invalidKey
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .wrongProduct:
            return "This key is for a different product."
        case .activationLimitReached:
            return "Activation limit reached. Deactivate on another machine first."
        case .invalidKey:
            return "License key not found. Check your key and try again."
        case .networkError(let underlying):
            return "Could not reach the license server. Check your connection. (\(underlying.localizedDescription))"
        case .apiError(let message):
            return message
        }
    }
}

// MARK: - LicenseService

@MainActor @Observable
final class LicenseService {

    // MARK: - Constants

    /// TODO: set before shipping — assign your real Lemon Squeezy store ID here
    static let expectedStoreId: Int = 322611
    /// TODO: set before shipping — assign your real Lemon Squeezy product ID here
    static let expectedProductId: Int = 909754

    // MARK: - Observable Properties

    var isLicensed: Bool = false
    var isValidating: Bool = false
    var lastError: String? = nil
    var customerEmail: String? = nil

    // MARK: - Private Properties

    private let session: URLSession
    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
        // Restore persisted license state on init
        let key = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey)
        let instanceId = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseInstanceId)
        if let key, !key.isEmpty, let instanceId, !instanceId.isEmpty {
            self.isLicensed = true
        }
    }

    // MARK: - Public API

    /// Activates a license key by calling the Lemon Squeezy /activate endpoint.
    ///
    /// On success: persists licenseKey + licenseInstanceId to UserDefaults and sets isLicensed=true.
    /// Throws LicenseError.wrongProduct if the key belongs to a different store/product.
    /// Throws LicenseError.activationLimitReached if the activation limit is exceeded.
    /// Throws LicenseError.invalidKey if the key is not found.
    /// Throws LicenseError.networkError for URLErrors.
    func activate(key: String) async throws {
        isValidating = true
        lastError = nil
        defer { isValidating = false }

        do {
            let instanceName = Host.current().localizedName ?? "Mac"
            let response: LSActivateResponse
            do {
                response = try await post(
                    path: "/activate",
                    params: ["license_key": key, "instance_name": instanceName]
                )
            } catch let error as URLError {
                throw LicenseError.networkError(error)
            }

            // Check for activation limit exceeded
            if let errorMsg = response.error, errorMsg.lowercased().contains("limit") {
                throw LicenseError.activationLimitReached
            }

            // Check for invalid key
            if !response.activated {
                if let errorMsg = response.error {
                    throw LicenseError.apiError(errorMsg)
                }
                throw LicenseError.invalidKey
            }

            // Security: verify this key is for our store/product
            guard response.meta.storeId == LicenseService.expectedStoreId,
                  response.meta.productId == LicenseService.expectedProductId else {
                throw LicenseError.wrongProduct
            }

            // Persist license state
            UserDefaults.standard.set(key, forKey: AppSettingsKeys.licenseKey)
            UserDefaults.standard.set(response.instance.id, forKey: AppSettingsKeys.licenseInstanceId)

            isLicensed = true
            customerEmail = response.meta.customerEmail
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Validates the persisted license key against the Lemon Squeezy /validate endpoint.
    ///
    /// Reads persisted licenseKey + licenseInstanceId. If either is missing, sets isLicensed=false.
    /// On network errors (URLError), keeps existing isLicensed state (Pitfall 2 — offline tolerance).
    /// On API rejection (valid==false), clears persisted keys and sets isLicensed=false.
    func validate() async {
        guard let key = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey),
              !key.isEmpty,
              let instanceId = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseInstanceId),
              !instanceId.isEmpty else {
            isLicensed = false
            return
        }

        isValidating = true
        defer { isValidating = false }

        let response: LSValidateResponse
        do {
            response = try await post(
                path: "/validate",
                params: ["license_key": key, "instance_id": instanceId]
            )
        } catch is URLError {
            // Network error — do NOT revoke existing license (Pitfall 2)
            return
        } catch {
            // Other error — also do not revoke
            return
        }

        if response.valid,
           response.meta.storeId == LicenseService.expectedStoreId,
           response.meta.productId == LicenseService.expectedProductId {
            isLicensed = true
            customerEmail = response.meta.customerEmail
        } else {
            // API explicitly rejected the key
            isLicensed = false
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseKey)
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseInstanceId)
        }
    }

    /// Deactivates the license on this machine by calling /deactivate.
    ///
    /// Clears persisted licenseKey + licenseInstanceId and sets isLicensed=false.
    func deactivate() async {
        guard let key = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey),
              !key.isEmpty,
              let instanceId = UserDefaults.standard.string(forKey: AppSettingsKeys.licenseInstanceId),
              !instanceId.isEmpty else {
            isLicensed = false
            return
        }

        isValidating = true
        defer { isValidating = false }

        // Best-effort POST to /deactivate — always clear local state
        _ = try? await post(
            path: "/deactivate",
            params: ["license_key": key, "instance_id": instanceId]
        ) as LSDeactivateResponse

        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseInstanceId)
        isLicensed = false
        customerEmail = nil
    }

    /// Returns true if the nag dialog should be shown based on lastNagShownDate.
    ///
    /// Returns true if lastNagShownDate is nil (never shown) or was more than 30 days ago.
    /// Returns false if the nag was shown within the last 30 days.
    static func shouldShowNag() -> Bool {
        guard let lastNag = UserDefaults.standard.object(forKey: AppSettingsKeys.lastNagShownDate) as? Date else {
            return true
        }
        return lastNag.timeIntervalSinceNow < -(30 * 24 * 3600)
    }

    // MARK: - Private Helpers

    private func post<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
