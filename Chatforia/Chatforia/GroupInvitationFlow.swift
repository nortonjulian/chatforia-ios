import Foundation
import SwiftUI

struct GroupInvitationLink: Identifiable, Equatable {
    let code: String
    var id: String { code }

    static func extract(from url: URL) -> Self? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let code: String?
        if url.scheme?.lowercased() == "https",
           ["chatforia.com", "www.chatforia.com"].contains(url.host?.lowercased() ?? ""),
           parts.count == 2, parts[0] == "join" {
            code = parts[1]
        } else if url.scheme?.lowercased() == "chatforia",
                  url.host?.lowercased() == "join", parts.count == 1 {
            code = parts[0]
        } else {
            code = nil
        }
        guard let code, code.range(of: "^[A-Za-z0-9_-]{8,128}$",
                                   options: .regularExpression) != nil else {
            return nil
        }
        return Self(code: code)
    }
}

private struct GroupInvitationPreview: Decodable {
    let roomId: Int
    let roomName: String?
    let status: String
}
private struct GroupInvitationJoin: Decodable {
    let ok: Bool
    let roomId: Int
    let alreadyMember: Bool?
}

struct GroupInvitationSheet: View {
    let invitation: GroupInvitationLink
    let token: String?
    let onJoined: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview: GroupInvitationPreview?
    @State private var loading = true
    @State private var joining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if loading {
                    ProgressView("Loading invitation…")
                } else {
                    if let preview {
                        Text("Join “\(preview.roomName ?? "Group chat")”?")
                            .font(.headline)
                        if preview.status != "ok" {
                            Text("This invitation is \(preview.status).")
                                .foregroundStyle(.red)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                    if preview?.status == "ok" {
                        Button(joining ? "Joining…" : "Join Group") {
                            Task { await accept() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(joining || token?.isEmpty != false)
                        if token?.isEmpty != false {
                            Text("Sign in to Chatforia to accept this invitation.")
                                .font(.footnote)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Group invitation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(joining)
                }
            }
            .task(id: invitation.code) {
                loading = true
                errorMessage = nil
                defer { loading = false }
                do {
                    let result: GroupInvitationPreview = try await APIClient.shared.send(
                        APIRequest(path: "invites/\(invitation.code)",
                                   method: .GET, requiresAuth: false),
                        token: nil
                    )
                    preview = result
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor private func accept() async {
        guard let token, !token.isEmpty else {
            errorMessage = "Sign in to Chatforia first."
            return
        }
        joining = true
        errorMessage = nil
        defer { joining = false }
        do {
            let result: GroupInvitationJoin = try await APIClient.shared.send(
                APIRequest(path: "invites/\(invitation.code)/accept",
                           method: .POST, requiresAuth: true),
                token: token
            )
            guard result.ok, result.roomId > 0 else {
                throw NSError(domain: "Chatforia", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Group join was not confirmed."])
            }
            onJoined(result.roomId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
