import XCTest
@testable import Chatforia

@MainActor
final class ContactsViewModelTests: XCTestCase {

    func testTabRefreshPolicyReusesRecentSameAccountDataButRefreshesOldOrOtherAccount() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(TabRefreshPolicy.shouldLoad(
            token: "one", loadedToken: "one", loadedAt: now.addingTimeInterval(-10), now: now
        ))
        XCTAssertTrue(TabRefreshPolicy.shouldLoad(
            token: "one", loadedToken: "one", loadedAt: now.addingTimeInterval(-60), now: now
        ))
        XCTAssertTrue(TabRefreshPolicy.shouldLoad(
            token: "two", loadedToken: "one", loadedAt: now, now: now
        ))
        XCTAssertTrue(TabRefreshPolicy.shouldLoad(
            token: "one", loadedToken: "one", loadedAt: now.addingTimeInterval(10), now: now
        ))
    }

    func testTabReentryReusesLoadedContactsButExplicitRefreshStillFetches() async {
        let counter = ContactFetchCounter()
        let vm = ContactsViewModel { _, _ in
            await counter.record()
            return ContactsResponseDTO(items: [makeContact(alias: "Saved")], nextCursor: nil, count: 1)
        }

        await vm.loadContactsIfNeeded(token: "account-one")
        await vm.loadContactsIfNeeded(token: "account-one")
        let initialCount = await counter.count
        XCTAssertEqual(initialCount, 1)
        XCTAssertEqual(vm.contacts.first?.alias, "Saved")

        await vm.loadContacts(token: "account-one")
        let refreshedCount = await counter.count
        XCTAssertEqual(refreshedCount, 2)

        vm.invalidateForNextOpen()
        await vm.loadContactsIfNeeded(token: "account-one")
        let resumedCount = await counter.count
        XCTAssertEqual(resumedCount, 3)
    }

    func testSwitchingSessionsClearsContactsAndRejectsLateResponse() async {
        let firstRequestStarted = expectation(description: "First account request started")
        let vm = ContactsViewModel { _, token in
            if token == "account-one" {
                firstRequestStarted.fulfill()
                try await Task.sleep(nanoseconds: 300_000_000)
                return ContactsResponseDTO(items: [makeContact(alias: "Old account")], nextCursor: nil, count: 1)
            }
            return ContactsResponseDTO(items: [makeContact(alias: "New account")], nextCursor: nil, count: 1)
        }

        let oldLoad = Task { await vm.loadContacts(token: "account-one") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        vm.prepareForSession(token: "account-two")
        XCTAssertTrue(vm.contacts.isEmpty)
        await vm.loadContactsIfNeeded(token: "account-two")
        await oldLoad.value
        XCTAssertEqual(vm.contacts.first?.alias, "New account")
    }

    func testConcurrentSameQueryLoadsCoalesce() async {
        let firstRequestStarted = expectation(description: "First contact request started")
        let counter = ContactFetchCounter()
        let vm = ContactsViewModel { _, _ in
            firstRequestStarted.fulfill()
            await counter.record()
            try await Task.sleep(nanoseconds: 500_000_000)
            return ContactsResponseDTO(items: [], nextCursor: nil, count: 0)
        }

        let first = Task { await vm.loadContactsIfNeeded(token: "account-one") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        await vm.loadContactsIfNeeded(token: "account-one")
        await first.value
        let requestCount = await counter.count
        XCTAssertEqual(requestCount, 1)
    }

    func testStaleSearchResponseCannotReplaceNewQueryResults() async {
        let firstRequestStarted = expectation(description: "Old query request started")
        let vm = ContactsViewModel { query, _ in
            if query == "old" {
                firstRequestStarted.fulfill()
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            return ContactsResponseDTO(
                items: [makeContact(alias: query)], nextCursor: nil, count: 1
            )
        }

        vm.searchText = "old"
        let oldLoad = Task { await vm.loadContacts(token: "account-one") }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        vm.searchText = "new"
        await vm.loadContacts(token: "account-one")
        await oldLoad.value
        XCTAssertEqual(vm.contacts.first?.alias, "new")
    }

    func testLoadContactsWithoutTokenSetsErrorAndClearsContacts() async {
        let vm = ContactsViewModel()
        vm.contacts = [
            makeContact(alias: "Existing")
        ]

        await vm.loadContacts(token: nil)

        XCTAssertNotNil(vm.errorText)
        XCTAssertTrue(vm.contacts.isEmpty)
    }

    func testDisplayNameUsesAliasFirst() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: "  Jules  ",
            username: "julian",
            externalName: "External Name",
            externalPhone: "5551234567"
        )

        XCTAssertEqual(vm.displayName(for: contact), "Jules")
    }

    func testDisplayNameUsesUsernameWhenAliasMissing() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: nil,
            username: "  julian  ",
            externalName: "External Name",
            externalPhone: "5551234567"
        )

        XCTAssertEqual(vm.displayName(for: contact), "julian")
    }

    func testDisplayNameUsesExternalNameWhenAliasAndUsernameMissing() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: nil,
            username: nil,
            externalName: "  External Name  ",
            externalPhone: "5551234567"
        )

        XCTAssertEqual(vm.displayName(for: contact), "External Name")
    }

    func testDisplayNameUsesExternalPhoneWhenOtherNamesMissing() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: nil,
            username: nil,
            externalName: nil,
            externalPhone: "  5551234567  "
        )

        XCTAssertEqual(vm.displayName(for: contact), "5551234567")
    }

    func testSubtitleUsesUsernameWhenDifferentFromDisplayName() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: "Jules",
            username: "julian",
            externalPhone: "5551234567"
        )

        XCTAssertEqual(vm.subtitle(for: contact), "@julian")
    }

    func testSubtitleUsesExternalPhoneWhenUsernameIsDisplayName() {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: nil,
            username: "julian",
            externalPhone: "5551234567"
        )

        XCTAssertEqual(vm.subtitle(for: contact), "5551234567")
    }

    func testOpenDirectChatWithoutLinkedUserThrows() async {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: "External Only",
            username: nil,
            externalPhone: "5551234567",
            userId: nil
        )

        do {
            _ = try await vm.openDirectChat(
                for: contact,
                token: "token"
            )

            XCTFail("Expected missing linked user error")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testOpenDirectChatWithoutTokenThrowsUnauthorized() async {
        let vm = ContactsViewModel()

        let contact = makeContact(
            alias: "Julian",
            username: "julian",
            userId: 123
        )

        do {
            _ = try await vm.openDirectChat(
                for: contact,
                token: nil
            )

            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                XCTFail("Expected APIError.unauthorized, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }
    }
}

private actor ContactFetchCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

// MARK: - Helpers

private func makeContact(
    alias: String? = nil,
    username: String? = nil,
    externalName: String? = nil,
    externalPhone: String? = nil,
    userId: Int? = 1
) -> ContactDTO {
    ContactDTO(
        id: 1,
        alias: alias,
        favorite: false,
        externalPhone: externalPhone,
        externalName: externalName,
        createdAt: nil,
        userId: userId,
        user: username == nil && userId == nil
            ? nil
            : ContactUserDTO(
                id: userId ?? 1,
                username: username,
                avatarUrl: nil
            )
    )
}
