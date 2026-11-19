import XCTest
@testable import Chatforia

@MainActor
final class ChatThreadViewModelTests: XCTestCase {

    func testReportSenderInterpolationPreservesRegionalCatalogFormats() {
        XCTAssertEqual(localizedReportSender("Mensaje de {name}", name: "Lucía"), "Mensaje de Lucía")
        XCTAssertEqual(localizedReportSender("来自 %@ 的报告信息", name: "Li"), "来自 Li 的报告信息")
        XCTAssertEqual(localizedReportSender("からの報告メッセージ", name: "花子"), "花子 からの報告メッセージ")
        XCTAssertEqual(localizedReportSender("@@ adresinden mesaj bildiriliyor", name: "Ayşe"), "Ayşe adresinden mesaj bildiriliyor")
        XCTAssertEqual(localizedReportSender("Reporting message from {name}", name: "%@"), "Reporting message from %@")
    }

    func testReportSenderInterpolationResolvesBundledLocales() {
        for code in ["en", "es", "zh-CN", "zh-TW", "ja", "tr"] {
            let template = appText("report.reportingMessageFrom", languageCode: code)
            let rendered = localizedReportSender(template, name: "Sample")
            XCTAssertTrue(rendered.contains("Sample"), "Missing name in \(code)")
            XCTAssertFalse(rendered.contains("{name}"), "Unresolved token in \(code)")
            XCTAssertFalse(rendered.contains("@@"), "Unresolved token in \(code)")
        }
    }

    func testReportPreviewUpdatesWhenDecryptionBecomesAvailable() {
        let id = 906
        let store = DecryptedMessageTextStore.shared
        store.activateAccount(7)
        defer { store.deactivateAccount() }
        let sender = SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil)
        let message = MessageDTO(
            id: id, contentCiphertext: "synthetic-ciphertext", rawContent: nil,
            createdAt: Date(), sender: sender, chatRoomId: 10
        )
        DecryptedMessageTextStore.shared.removeText(for: id)
        XCTAssertNil(ReportMessagePreview.resolve(
            message: message,
            decryptedText: DecryptedMessageTextStore.shared.text(for: id),
            languageCode: "en"
        ).evidenceText)

        DecryptedMessageTextStore.shared.setText("decrypted later", for: id, accountId: 7)
        defer { DecryptedMessageTextStore.shared.removeText(for: id) }
        XCTAssertEqual(ReportMessagePreview.resolve(
            message: message,
            decryptedText: DecryptedMessageTextStore.shared.text(for: id),
            languageCode: "en"
        ).evidenceText, "decrypted later")
    }

    func testReportPreviewNeverUsesPreviousAccountsDecryptedText() {
        let store = DecryptedMessageTextStore.shared
        let message = MessageDTO(
            id: 907, contentCiphertext: "synthetic-ciphertext", rawContent: nil,
            createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        store.activateAccount(7)
        store.setText("account A secret", for: 907, accountId: 7)
        XCTAssertEqual(store.text(for: 907), "account A secret")

        store.activateAccount(8)
        store.setText("late account A secret", for: 907, accountId: 7)
        XCTAssertNil(store.text(for: 907))
        XCTAssertNil(ReportMessagePreview.resolve(
            message: message, store: store, accountId: 7, languageCode: "en"
        ).evidenceText)

        store.setText("account B text", for: 907, accountId: 8)
        XCTAssertEqual(store.text(for: 907), "account B text")
        store.deactivateAccount()
        XCTAssertNil(store.text(for: 907))
        store.activateAccount(7)
        XCTAssertNil(store.text(for: 907))
        store.deactivateAccount()
    }

    func testPreviousAccountReportPreviewCannotUseEvenLocalRawContent() {
        let store = DecryptedMessageTextStore.shared
        let message = MessageDTO(
            id: 908, rawContent: "account A plaintext", createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        store.activateAccount(7)
        XCTAssertEqual(ReportMessagePreview.resolve(
            message: message, store: store, accountId: 7, languageCode: "en"
        ).evidenceText, "account A plaintext")

        store.activateAccount(8)
        XCTAssertNil(ReportMessagePreview.resolve(
            message: message, store: store, accountId: 7, languageCode: "en"
        ).evidenceText)
        store.deactivateAccount()
    }

    func testReportPreviewUsesLocalTextThenPermittedMedia() {
        let sender = SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil)
        let encrypted = MessageDTO(
            id: 901, contentCiphertext: "synthetic-ciphertext", rawContent: nil,
            createdAt: Date(), sender: sender, chatRoomId: 10
        )
        let pending = ReportMessagePreview.resolve(message: encrypted, decryptedText: nil, languageCode: "en")
        XCTAssertEqual(pending.displayText, appText("messages.encryptedMessage", languageCode: "en"))
        XCTAssertNil(pending.evidenceText)
        let decrypted = ReportMessagePreview.resolve(message: encrypted, decryptedText: "  Private text  ", languageCode: "en")
        XCTAssertEqual(decrypted.displayText, "Private text")
        XCTAssertEqual(decrypted.evidenceText, "Private text")

        let mediaOnly = MessageDTO(
            id: 902, rawContent: "[image]",
            attachments: [AttachmentDTO(id: 8, kind: "IMAGE", url: "synthetic-private-media")],
            createdAt: Date(), sender: sender, chatRoomId: 10
        )
        let photo = ReportMessagePreview.resolve(message: mediaOnly, decryptedText: nil, languageCode: "en")
        XCTAssertEqual(photo.displayText, appText("messages.mediaPhoto", languageCode: "en"))
        XCTAssertNil(photo.evidenceText)

        let captioned = MessageDTO(
            id: 903, rawContent: nil,
            attachments: [AttachmentDTO(id: 9, kind: "IMAGE", url: "synthetic-private-media", caption: "  Visible caption  ")],
            createdAt: Date(), sender: sender, chatRoomId: 10
        )
        XCTAssertEqual(
            ReportMessagePreview.resolve(message: captioned, decryptedText: nil, languageCode: "en").evidenceText,
            "Visible caption"
        )
    }

    func testReportPreviewDoesNotExposeRestrictedVisualMediaOrInventPlaintext() {
        let sender = SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil)
        let restricted = MessageDTO(
            id: 904, rawContent: nil,
            attachments: [AttachmentDTO(id: 10, kind: "IMAGE", url: "synthetic-private-media", caption: "hidden caption")],
            mediaRestricted: true, createdAt: Date(), sender: sender, chatRoomId: 10
        )
        let preview = ReportMessagePreview.resolve(message: restricted, decryptedText: nil, languageCode: "en")
        XCTAssertEqual(preview.displayText, appText("messages.teenMediaRestricted", languageCode: "en"))
        XCTAssertNil(preview.evidenceText)

        let audio = MessageDTO(
            id: 905, rawContent: nil,
            attachments: [
                AttachmentDTO(id: 11, kind: "IMAGE", url: "synthetic-private-media"),
                AttachmentDTO(id: 12, kind: "AUDIO", url: "synthetic-private-audio", mimeType: "audio/mp4")
            ],
            mediaRestricted: true, createdAt: Date(), sender: sender, chatRoomId: 10
        )
        let audioPreview = ReportMessagePreview.resolve(message: audio, decryptedText: nil, languageCode: "en")
        XCTAssertEqual(audioPreview.displayText, appText("messages.mediaAudio", languageCode: "en"))
        XCTAssertNil(audioPreview.evidenceText)
    }

    func testContactAccountReportUsesAuthenticatedModerationRoute() throws {
        let path = ContactAccountReportRequest.path(userId: 29)
        let request = APIRequest(path: path, method: .POST, requiresAuth: true)
        XCTAssertEqual(try APIClient.shared.buildURL(from: request).path, "/reports/users/29")
        let payload = ContactAccountReportRequest(reason: ReportReason.harassment.rawValue, details: "synthetic")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(object["reason"] as? String, "harassment")
        XCTAssertEqual(object["details"] as? String, "synthetic")
    }

    func testReportSubmissionUsesExistingAuthenticatedRouteAndSelectedMessage() async throws {
        let request = APIRequest(
            path: ReportCreateRequest.endpoint,
            method: .POST,
            requiresAuth: true
        )
        XCTAssertEqual(try APIClient.shared.buildURL(from: request).path, "/messages/report")

        let vm = ChatThreadViewModel()
        let previous = MessageDTO(
            id: 801, rawContent: "previous context", createdAt: Date().addingTimeInterval(-30),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        let message = MessageDTO(
            id: 802, rawContent: "synthetic report",
            attachments: [AttachmentDTO(id: 7, kind: "IMAGE", url: "synthetic-private-media")],
            createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        vm.messages = [previous, message]
        var sent = 0
        vm.reportSender = { payload, token in
            sent += 1
            XCTAssertEqual(token, "synthetic-token")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
            XCTAssertEqual(object["messageId"] as? Int, 802)
            XCTAssertEqual(object["chatRoomId"] as? Int, 10)
            XCTAssertEqual(object["reportedUserId"] as? Int, 9)
            XCTAssertEqual(object["reason"] as? String, "sexual_content")
            let snapshots = try XCTUnwrap(object["messages"] as? [[String: Any]])
            XCTAssertEqual(snapshots.count, 2)
            XCTAssertEqual(snapshots[0]["plaintext"] as? String, "previous context")
            XCTAssertEqual(snapshots[1]["plaintext"] as? String, "synthetic report")
            let attachments = try XCTUnwrap(snapshots[1]["attachments"] as? [[String: Any]])
            XCTAssertEqual(attachments.first?["id"] as? Int, 7)
            XCTAssertEqual(object["blockAfterReport"] as? Bool, true)
            return true
        }

        let succeeded = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .sexualContent,
            details: "synthetic media", reportedContent: "synthetic report", contextCount: 5,
            blockAfterReport: true, token: "synthetic-token"
        )
        XCTAssertTrue(succeeded)
        XCTAssertEqual(sent, 1)
        XCTAssertNil(vm.reportErrorText)
    }

    func testFailedReportRetainsErrorAndCanRetryWithoutDuplicateSubmission() async {
        let vm = ChatThreadViewModel()
        let message = MessageDTO(
            id: 803, rawContent: "synthetic report", createdAt: Date(),
            sender: SenderDTO(id: 9, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        var attempts = 0
        vm.reportSender = { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return true
        }
        let first = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .other,
            details: "", contextCount: 0, blockAfterReport: false, token: "synthetic-token"
        )
        XCTAssertFalse(first)
        XCTAssertNotNil(vm.reportErrorText)
        let second = await vm.submitReport(
            targetMessage: message, roomId: 10, reason: .other,
            details: "", contextCount: 0, blockAfterReport: false, token: "synthetic-token"
        )
        XCTAssertTrue(second)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(vm.reportErrorText)
    }

    func testVisibleExpiryAndRestartAfterBackground() {
        let vm = ChatThreadViewModel()
        let expired = MessageDTO(
            id: 801, rawContent: "synthetic expired", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(-60),
            sender: SenderDTO(id: 1, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )
        let live = MessageDTO(
            id: 802, rawContent: "synthetic live", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(60),
            sender: SenderDTO(id: 1, username: "sender", publicKey: nil, avatarUrl: nil),
            chatRoomId: 10
        )

        vm.messages = [expired, live]
        vm.startExpiryLoop()
        XCTAssertEqual(vm.messages.map(\.id), [802])
        vm.stopExpiryLoop()

        vm.messages = [expired]
        vm.startExpiryLoop()
        XCTAssertTrue(vm.messages.isEmpty)
        vm.stopExpiryLoop()
    }

    func testGroupRiaConsentWireContract() throws {
        let on = try JSONDecoder().decode(
            GroupRiaRoomConsent.self,
            from: Data(#"{"me":{"allowAIBot":true},"allowForiaBot":false}"#.utf8)
        )
        XCTAssertTrue(on.me.allowAIBot)

        let off = try JSONDecoder().decode(
            GroupRiaRoomConsent.self,
            from: Data(#"{"me":{"allowAIBot":false}}"#.utf8)
        )
        XCTAssertFalse(off.me.allowAIBot)
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(GroupRiaConsentUpdate(allow: false)), encoding: .utf8),
            #"{"allow":false}"#
        )
    }


    func testConfigureRandomSessionCreatesSession() {
        let vm = ChatThreadViewModel()

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Me",
            partnerAlias: "Partner"
        )

        XCTAssertEqual(vm.randomSession?.roomId, 123)
        XCTAssertEqual(vm.randomSession?.myAlias, "Me")
        XCTAssertEqual(vm.randomSession?.partnerAlias, "Partner")
    }

    func testConfigureRandomSessionDoesNotReplaceSameRoomSession() {
        let vm = ChatThreadViewModel()

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Me",
            partnerAlias: "Partner"
        )

        vm.configureRandomSession(
            roomId: 123,
            myAlias: "Changed",
            partnerAlias: "Changed"
        )

        XCTAssertEqual(vm.randomSession?.myAlias, "Me")
        XCTAssertEqual(vm.randomSession?.partnerAlias, "Partner")
    }

    func testReceivedTypingAddsTrimmedUsername() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "  Julian  ")

        XCTAssertEqual(vm.typingUsernames, ["Julian"])
    }

    func testReceivedTypingIgnoresEmptyUsername() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "   ")

        XCTAssertTrue(vm.typingUsernames.isEmpty)
    }

    func testClearTypingUsersRemovesAllTypingUsers() {
        let vm = ChatThreadViewModel()

        vm.receivedTyping(username: "Julian")
        vm.receivedTyping(username: "Alex")

        vm.clearTypingUsers()

        XCTAssertTrue(vm.typingUsernames.isEmpty)
    }

    func testConfigureCurrentUserPersistsUserId() {
        let vm = ChatThreadViewModel()

        UserDefaults.standard.removeObject(forKey: "chatforia.currentUserId")

        vm.configureCurrentUser(
            id: 42,
            username: "julian",
            publicKey: "public-key"
        )

        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "chatforia.currentUserId"),
            42
        )
    }

    func testSendMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendMessage(
            roomId: 1,
            token: nil,
            text: "Hello",
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testSendMessageReturnsFalseWhenTextIsEmpty() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendMessage(
            roomId: 1,
            token: "token",
            text: "   ",
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
    }

    func testOfflinePreparationFailureDoesNotLeaveOptimisticBubble() async {
        MessageStore.shared.clearAll()
        let vm = ChatThreadViewModel(textPayloadBuilder: { _, _, _, _ in
            throw URLError(.notConnectedToInternet)
        })

        let sent = await vm.sendMessage(
            roomId: 77, token: "synthetic-token", text: "Preserved draft",
            senderId: 42, senderUsername: "sender", senderPublicKey: nil
        )

        XCTAssertFalse(sent)
        XCTAssertTrue(MessageStore.shared.currentWindow().filter { $0.chatRoomId == 77 }.isEmpty)
        XCTAssertEqual(vm.errorText, appText("chat.sendMessageFailed", languageCode:
            UserDefaults.standard.string(forKey: "chatforia_language") ?? "en"))
        MessageStore.shared.clearAll()
    }

    func testLocalizedGIFFailureDoesNotExposeInterpolationMarkerOrRawNetworkError() {
        let english = localizedGIFSendFailure(languageCode: "en")
        let spanish = localizedGIFSendFailure(languageCode: "es")
        XCTAssertFalse(english.contains("{error}"))
        XCTAssertFalse(spanish.contains("{error}"))
        XCTAssertTrue(english.contains("Try Again"))
        XCTAssertTrue(spanish.contains("Inténtelo de nuevo"))
    }

    func testSendImageMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendImageMessage(
            roomId: 1,
            token: nil,
            imageData: Data([1, 2, 3]),
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testSendImageMessageReturnsFalseWhenImageDataIsEmpty() async {
        let vm = ChatThreadViewModel()

        let result = await vm.sendImageMessage(
            roomId: 1,
            token: "token",
            imageData: Data(),
            senderId: 1,
            senderUsername: "julian",
            senderPublicKey: "public-key"
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testDeleteMessageReturnsFalseWhenTokenMissing() async {
        let vm = ChatThreadViewModel()

        let result = await vm.deleteMessage(
            messageId: 1,
            token: nil,
            deleteForEveryone: false
        )

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.errorText)
    }

    func testDeleteMessageReturnsTrueForLocalOnlyMessage() async {
        let vm = ChatThreadViewModel()

        let result = await vm.deleteMessage(
            messageId: -123,
            token: "token",
            deleteForEveryone: false
        )

        XCTAssertTrue(result)
    }
}

