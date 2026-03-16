import Security
import Foundation

/// Keychain wrapper for storing and retrieving a single GitHub Personal Access Token.
///
/// Uses raw Security.framework SecItem APIs (no external dependencies).
/// Injectable service and account parameters allow test isolation.
struct TokenStore: Sendable {

    let service: String
    let account: String

    init(
        service: String = "com.github.haad.clipsmith.github-pat",
        account: String = "github-personal-access-token"
    ) {
        self.service = service
        self.account = account
    }

    // MARK: - Save

    /// Saves (or overwrites) the GitHub PAT in the Keychain.
    ///
    /// Deletes any existing entry first to avoid `errSecDuplicateItem` (PITFALL 7).
    func saveToken(_ token: String) {
        deleteToken()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(token.utf8)
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Load

    /// Loads the GitHub PAT from the Keychain.
    ///
    /// Returns `nil` if no token has been saved.
    func loadToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    // MARK: - Delete

    /// Removes the GitHub PAT from the Keychain.
    ///
    /// No-op if no token exists.
    func deleteToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
