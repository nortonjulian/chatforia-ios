import XCTest
@testable import Chatforia

final class TokenStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TokenStore.shared.clear()
    }

    override func tearDown() {
        TokenStore.shared.clear()
        super.tearDown()
    }

    func testReadReturnsNilWhenNoTokenSaved() {
        TokenStore.shared.clear()

        let token = TokenStore.shared.read()

        XCTAssertNil(token)
    }

    func testSaveThenReadReturnsToken() {
        let expectedToken = "test.jwt.token"

        TokenStore.shared.save(expectedToken)

        let savedToken = TokenStore.shared.read()

        XCTAssertEqual(savedToken, expectedToken)
    }

    func testSaveReplacesExistingToken() {
        TokenStore.shared.save("old.token")
        TokenStore.shared.save("new.token")

        let savedToken = TokenStore.shared.read()

        XCTAssertEqual(savedToken, "new.token")
    }

    func testClearRemovesSavedToken() {
        TokenStore.shared.save("test.jwt.token")

        TokenStore.shared.clear()

        let savedToken = TokenStore.shared.read()

        XCTAssertNil(savedToken)
    }

    func testSavingEmptyTokenCanBeReadBack() {
        TokenStore.shared.save("")

        let savedToken = TokenStore.shared.read()

        XCTAssertEqual(savedToken, "")
    }
}
