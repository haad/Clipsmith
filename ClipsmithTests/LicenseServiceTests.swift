import XCTest
@testable import Clipsmith

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeLicenseActivateSuccessResponse(
    storeId: Int = 322611,
    productId: Int = 909754,
    instanceId: String = "test-instance-id",
    licenseKey: String = "test-key"
) -> (HTTPURLResponse, Data) {
    let json = """
    {
        "activated": true,
        "error": null,
        "license_key": {
            "id": 1,
            "status": "active",
            "key": "\(licenseKey)",
            "activation_limit": 3,
            "activation_usage": 1,
            "created_at": "2026-01-01T00:00:00.000Z",
            "expires_at": null
        },
        "instance": {
            "id": "\(instanceId)",
            "name": "TestMac",
            "created_at": "2026-01-01T00:00:00.000Z"
        },
        "meta": {
            "store_id": \(storeId),
            "order_id": 100,
            "product_id": \(productId),
            "variant_id": 200,
            "customer_name": "Test User",
            "customer_email": "test@example.com"
        }
    }
    """.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json)
}

private func makeLicenseActivateFailedResponse(error: String = "License key not found") -> (HTTPURLResponse, Data) {
    let json = """
    {
        "activated": false,
        "error": "\(error)",
        "license_key": {
            "id": 1,
            "status": "inactive",
            "key": "invalid-key",
            "activation_limit": 3,
            "activation_usage": 0,
            "created_at": "2026-01-01T00:00:00.000Z",
            "expires_at": null
        },
        "instance": {
            "id": "placeholder",
            "name": "TestMac",
            "created_at": "2026-01-01T00:00:00.000Z"
        },
        "meta": {
            "store_id": 0,
            "order_id": 0,
            "product_id": 0,
            "variant_id": 0,
            "customer_name": "",
            "customer_email": ""
        }
    }
    """.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json)
}

private func makeLicenseValidateSuccessResponse(
    valid: Bool = true,
    storeId: Int = 322611,
    productId: Int = 909754,
    instanceId: String = "test-instance-id"
) -> (HTTPURLResponse, Data) {
    let json = """
    {
        "valid": \(valid),
        "error": null,
        "license_key": {
            "id": 1,
            "status": "active",
            "key": "test-key",
            "activation_limit": 3,
            "activation_usage": 1,
            "created_at": "2026-01-01T00:00:00.000Z",
            "expires_at": null
        },
        "instance": {
            "id": "\(instanceId)",
            "name": "TestMac",
            "created_at": "2026-01-01T00:00:00.000Z"
        },
        "meta": {
            "store_id": \(storeId),
            "order_id": 100,
            "product_id": \(productId),
            "variant_id": 200,
            "customer_name": "Test User",
            "customer_email": "test@example.com"
        }
    }
    """.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json)
}

private func makeLicenseDeactivateSuccessResponse() -> (HTTPURLResponse, Data) {
    let json = """
    {
        "deactivated": true,
        "error": null,
        "license_key": {
            "id": 1,
            "status": "inactive",
            "key": "test-key",
            "activation_limit": 3,
            "activation_usage": 0,
            "created_at": "2026-01-01T00:00:00.000Z",
            "expires_at": null
        },
        "meta": {
            "store_id": 0,
            "order_id": 100,
            "product_id": 0,
            "variant_id": 200,
            "customer_name": "Test User",
            "customer_email": "test@example.com"
        }
    }
    """.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/deactivate")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json)
}

// MARK: - LicenseServiceTests

@MainActor
final class LicenseServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Clear all license-related UserDefaults keys for test isolation
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseInstanceId)
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.lastNagShownDate)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.licenseInstanceId)
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.lastNagShownDate)
        MockURLProtocol.requestHandler = nil
        try await super.tearDown()
    }

    // MARK: - testActivateSuccess

    func testActivateSuccess() async throws {
        MockURLProtocol.requestHandler = { _ in
            makeLicenseActivateSuccessResponse()
        }
        let service = LicenseService(session: makeMockSession())

        try await service.activate(key: "test-key")

        XCTAssertTrue(service.isLicensed, "isLicensed should be true after successful activation")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey),
            "test-key",
            "licenseKey should be persisted in UserDefaults"
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppSettingsKeys.licenseInstanceId),
            "test-instance-id",
            "licenseInstanceId should be persisted in UserDefaults"
        )
    }

    // MARK: - testActivateWrongProduct

    func testActivateWrongProduct() async throws {
        MockURLProtocol.requestHandler = { _ in
            // storeId=999 does not match expectedStoreId=322611
            makeLicenseActivateSuccessResponse(storeId: 999, productId: 0)
        }
        let service = LicenseService(session: makeMockSession())

        do {
            try await service.activate(key: "wrong-product-key")
            XCTFail("Expected LicenseError.wrongProduct to be thrown")
        } catch LicenseError.wrongProduct {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(service.isLicensed, "isLicensed should remain false after wrong product error")
    }

    // MARK: - testActivateInvalidKey

    func testActivateInvalidKey() async throws {
        MockURLProtocol.requestHandler = { _ in
            makeLicenseActivateFailedResponse(error: "License key not found")
        }
        let service = LicenseService(session: makeMockSession())

        do {
            try await service.activate(key: "invalid-key")
            XCTFail("Expected a LicenseError to be thrown")
        } catch LicenseError.invalidKey {
            // Expected
        } catch LicenseError.apiError {
            // Also acceptable — the error string propagated
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(service.isLicensed, "isLicensed should remain false after invalid key")
    }

    // MARK: - testActivateActivationLimitReached

    func testActivateActivationLimitReached() async throws {
        MockURLProtocol.requestHandler = { _ in
            makeLicenseActivateFailedResponse(error: "activation limit reached")
        }
        let service = LicenseService(session: makeMockSession())

        do {
            try await service.activate(key: "limit-key")
            XCTFail("Expected LicenseError.activationLimitReached to be thrown")
        } catch LicenseError.activationLimitReached {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - testValidateUsesInstanceId

    func testValidateUsesInstanceId() async throws {
        // Pre-set UserDefaults with persisted key + instanceId
        UserDefaults.standard.set("test-key", forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.set("test-instance-id", forKey: AppSettingsKeys.licenseInstanceId)

        var capturedRequestBody: String? = nil
        MockURLProtocol.requestHandler = { request in
            // URLProtocol may deliver body via httpBodyStream or httpBody
            if let bodyData = request.httpBody {
                capturedRequestBody = String(data: bodyData, encoding: .utf8)
            } else if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer {
                    buffer.deallocate()
                    stream.close()
                }
                while stream.hasBytesAvailable {
                    let bytesRead = stream.read(buffer, maxLength: bufferSize)
                    if bytesRead > 0 {
                        data.append(buffer, count: bytesRead)
                    }
                }
                capturedRequestBody = String(data: data, encoding: .utf8)
            }
            return makeLicenseValidateSuccessResponse()
        }

        let service = LicenseService(session: makeMockSession())
        await service.validate()

        XCTAssertTrue(service.isLicensed, "isLicensed should be true after successful validation")
        XCTAssertNotNil(capturedRequestBody, "Request body should be captured")
        XCTAssertTrue(
            capturedRequestBody?.contains("instance_id=test-instance-id") == true,
            "Request body should contain instance_id=test-instance-id, got: \(capturedRequestBody ?? "nil")"
        )
        XCTAssertFalse(
            capturedRequestBody?.contains("instance_name") == true,
            "Validate request should NOT contain instance_name"
        )
    }

    // MARK: - testValidateNetworkErrorKeepsLicense

    func testValidateNetworkErrorKeepsLicense() async throws {
        // Pre-set persisted keys so isLicensed starts true
        UserDefaults.standard.set("test-key", forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.set("test-instance-id", forKey: AppSettingsKeys.licenseInstanceId)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = LicenseService(session: makeMockSession())
        // isLicensed should be true from persisted keys in init
        XCTAssertTrue(service.isLicensed, "isLicensed should be true from persisted keys")

        await service.validate()

        XCTAssertTrue(
            service.isLicensed,
            "isLicensed should remain true after network error (Pitfall 2 — offline tolerance)"
        )
    }

    // MARK: - testValidateApiRejectionRevokesLicense

    func testValidateApiRejectionRevokesLicense() async throws {
        // Pre-set persisted keys
        UserDefaults.standard.set("test-key", forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.set("test-instance-id", forKey: AppSettingsKeys.licenseInstanceId)

        MockURLProtocol.requestHandler = { _ in
            makeLicenseValidateSuccessResponse(valid: false)
        }

        let service = LicenseService(session: makeMockSession())
        await service.validate()

        XCTAssertFalse(service.isLicensed, "isLicensed should be false after API rejection")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey),
            "licenseKey should be cleared from UserDefaults after API rejection"
        )
    }

    // MARK: - testDeactivateClearsState

    func testDeactivateClearsState() async throws {
        // Pre-set persisted keys
        UserDefaults.standard.set("test-key", forKey: AppSettingsKeys.licenseKey)
        UserDefaults.standard.set("test-instance-id", forKey: AppSettingsKeys.licenseInstanceId)

        MockURLProtocol.requestHandler = { _ in
            makeLicenseDeactivateSuccessResponse()
        }

        let service = LicenseService(session: makeMockSession())
        XCTAssertTrue(service.isLicensed, "isLicensed should start true from persisted keys")

        await service.deactivate()

        XCTAssertFalse(service.isLicensed, "isLicensed should be false after deactivation")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: AppSettingsKeys.licenseKey),
            "licenseKey should be nil in UserDefaults after deactivation"
        )
        XCTAssertNil(
            UserDefaults.standard.string(forKey: AppSettingsKeys.licenseInstanceId),
            "licenseInstanceId should be nil in UserDefaults after deactivation"
        )
    }

    // MARK: - testShouldShowNagNilDate

    func testShouldShowNagNilDate() {
        // Ensure no lastNagShownDate in UserDefaults (setUp clears it)
        XCTAssertTrue(
            LicenseService.shouldShowNag(),
            "shouldShowNag should return true when lastNagShownDate is nil"
        )
    }

    // MARK: - testShouldShowNag31DaysAgo

    func testShouldShowNag31DaysAgo() {
        let thirtyOneDaysAgo = Date().addingTimeInterval(-(31 * 24 * 3600))
        UserDefaults.standard.set(thirtyOneDaysAgo, forKey: AppSettingsKeys.lastNagShownDate)

        XCTAssertTrue(
            LicenseService.shouldShowNag(),
            "shouldShowNag should return true when lastNagShownDate is 31 days ago"
        )
    }

    // MARK: - testShouldShowNag29DaysAgo

    func testShouldShowNag29DaysAgo() {
        let twentyNineDaysAgo = Date().addingTimeInterval(-(29 * 24 * 3600))
        UserDefaults.standard.set(twentyNineDaysAgo, forKey: AppSettingsKeys.lastNagShownDate)

        XCTAssertFalse(
            LicenseService.shouldShowNag(),
            "shouldShowNag should return false when lastNagShownDate is only 29 days ago"
        )
    }
}
