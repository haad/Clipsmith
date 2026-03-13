import XCTest
import Security
@testable import Clipsmith

final class TokenStoreTests: XCTestCase {

    // Use a test-specific service string to avoid polluting production keychain
    private let testService = "com.generalarcade.flycut.github-pat.test"
    private let testAccount = "github-personal-access-token-test"

    private var tokenStore: TokenStore!

    override func setUp() {
        super.setUp()
        tokenStore = TokenStore(service: testService, account: testAccount)
        // Ensure clean state before each test
        tokenStore.deleteToken()
    }

    override func tearDown() {
        // Clean up keychain after each test
        tokenStore.deleteToken()
        tokenStore = nil
        super.tearDown()
    }

    // MARK: - testSaveAndLoad

    func testSaveAndLoad() {
        tokenStore.saveToken("ghp_testtoken123")
        let loaded = tokenStore.loadToken()
        XCTAssertEqual(loaded, "ghp_testtoken123", "loadToken should return the saved token")
    }

    // MARK: - testLoadWithNoTokenReturnsNil

    func testLoadWithNoTokenReturnsNil() {
        // tearDown already deleted any token; load should return nil
        let loaded = tokenStore.loadToken()
        XCTAssertNil(loaded, "loadToken should return nil when no token is stored")
    }

    // MARK: - testDeleteRemovesToken

    func testDeleteRemovesToken() {
        tokenStore.saveToken("ghp_deletetest")
        // Verify saved
        XCTAssertNotNil(tokenStore.loadToken(), "Token should be present before delete")

        tokenStore.deleteToken()

        let loaded = tokenStore.loadToken()
        XCTAssertNil(loaded, "loadToken should return nil after deleteToken")
    }

    // MARK: - testSaveOverwritesPreviousValue

    func testSaveOverwritesPreviousValue() {
        tokenStore.saveToken("ghp_first_token")
        XCTAssertEqual(tokenStore.loadToken(), "ghp_first_token")

        // Save a second token — should overwrite without errSecDuplicateItem
        tokenStore.saveToken("ghp_second_token")

        let loaded = tokenStore.loadToken()
        XCTAssertEqual(loaded, "ghp_second_token", "saveToken should overwrite the previous token")
    }
}
