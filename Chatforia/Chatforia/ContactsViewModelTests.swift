import XCTest
@testable import Chatforia

@MainActor
final class ContactsViewModelTests: XCTestCase {

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
