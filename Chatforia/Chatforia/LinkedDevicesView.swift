import SwiftUI
import Combine

@MainActor
final class LinkedDevicesViewModel: ObservableObject {
    @Published var devices: [LinkedDeviceDTO] = []
    @Published var pending: [LinkedDeviceDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let service = LinkedDevicesService.shared
    private let identity = DeviceIdentityStorage.shared
    private let crypto = DeviceProvisioningCrypto.shared

    func load(token: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let allDevices = try await service.fetchMine(token: token)
            let pendingDevices = try await service.fetchPendingPairing(token: token)

            let currentDeviceId = identity.getOrCreateDeviceId()

            pending = pendingDevices.filter {
                $0.pairingStatus == "pending"
            }

            devices = allDevices.filter { device in
                if device.deviceId == currentDeviceId {
                    return device.pairingStatus != "pending"
                }

                return device.pairingStatus == nil ||
                       device.pairingStatus == "approved"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func requestPairing(token: String) async {
        do {
            let deviceId = identity.getOrCreateDeviceId()
            let publicKey = try identity.publicKeyBase64()

            try await service.requestPairing(
                token: token,
                request: LinkedDeviceRegisterRequest(
                    deviceId: deviceId,
                    name: identity.currentDeviceName(),
                    platform: identity.currentPlatform(),
                    publicKey: publicKey,
                    keyAlgorithm: "curve25519",
                    keyVersion: 1
                )
            )

            successMessage = "Device approval requested."
            await load(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approve(
        token: String,
        userId: Int,
        device: LinkedDeviceDTO
    ) async {
        do {
            guard let targetPublicKey = device.publicKey else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Pending device is missing required secure message information."]
                )
            }

            guard let accountPrivateKey =
                    AccountKeyManager.shared.privateKeyBase64(userId: userId)
            else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "This device is missing your secure message key."]
                )
            }

            let wrapped = try crypto.wrapAccountKeyForDevice(
                accountPrivateKeyBase64: accountPrivateKey,
                targetDevicePublicKeyBase64: targetPublicKey
            )

            try await service.approve(
                token: token,
                deviceId: device.deviceId,
                wrappedAccountKey: wrapped
            )

            successMessage = "Device approved."
            await load(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reject(token: String, deviceId: String) async {
        do {
            try await service.reject(token: token, deviceId: deviceId)
            successMessage = "Device rejected."
            await load(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revoke(token: String, deviceId: String) async {
        do {
            try await service.revoke(token: token, deviceId: deviceId)
            successMessage = "Device revoked."
            await load(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishApproval(
        token: String,
        userId: Int,
        accountPublicKey: String?
    ) async {
        do {
            let deviceId = identity.getOrCreateDeviceId()

            guard let device = try await service.fetchPairingStatus(
                token: token,
                deviceId: deviceId
            ) else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Device pairing request was not found."]
                )
            }

            guard device.pairingStatus == "approved" else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "This device has not been approved yet."]
                )
            }

            guard let wrapped = device.wrappedAccountKey else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Approved device is missing secure message recovery information."]
                )
            }

            let privateDeviceKey = try identity.privateKey()

            let restoredPrivateKey = try crypto.unwrapProvisionedAccountKey(
                wrappedAccountKeyJson: wrapped,
                currentDevicePrivateKey: privateDeviceKey
            )

            guard let accountPublicKey = accountPublicKey?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !accountPublicKey.isEmpty else {
                throw NSError(
                    domain: "LinkedDevicesViewModel",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Missing secure message key for this account."]
                )
            }

            try AccountKeyManager.shared.saveAccountKeys(
                userId: userId,
                publicKeyBase64: accountPublicKey,
                privateKeyBase64: restoredPrivateKey
            )

            successMessage = "This device is now linked."
            await load(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LinkedDevicesView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var vm = LinkedDevicesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Linked Devices")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(themeManager.palette.primaryText)

                actionButtons

                if vm.isLoading {
                    ProgressView()
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let success = vm.successMessage {
                    Text(success)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                sectionTitle("Your devices")

                if vm.devices.isEmpty {
                    emptyCard("No linked devices yet.")
                } else {
                    ForEach(vm.devices) { device in
                        deviceCard(device: device, showRevoke: true)
                    }
                }

                sectionTitle("Pending approvals")

                if vm.pending.isEmpty {
                    emptyCard("No pending approvals.")
                } else {
                    ForEach(vm.pending) { device in
                        pendingCard(device: device)
                    }
                }
            }
            .padding(20)
        }
        .background(themeManager.palette.screenBackground.ignoresSafeArea())
        .task {
            await load()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            gradientButton("Request approval for this device") {
                Task {
                    guard let token = auth.currentToken else { return }
                    await vm.requestPairing(token: token)
                }
            }

            gradientButton("Finish device approval") {
                Task {
                    guard let token = auth.currentToken,
                          let user = auth.currentUser else { return }

                    await vm.finishApproval(
                        token: token,
                        userId: user.id,
                        accountPublicKey: user.publicKey
                    )

                    await auth.refreshCurrentUser()
                    auth.markKeyRestoreComplete()
                }
            }
        }
    }

    private func load() async {
        guard let token = auth.currentToken else { return }
        await vm.load(token: token)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(themeManager.palette.primaryText)
            .padding(.top, 6)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(themeManager.palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(themeManager.palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func deviceCard(
        device: LinkedDeviceDTO,
        showRevoke: Bool
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name ?? "Unknown device")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Text(
                    [device.platform, device.pairingStatus]
                        .compactMap { $0 }
                        .joined(separator: " • ")
                )
                .font(.caption)
                .foregroundStyle(themeManager.palette.secondaryText)
            }

            Spacer()

            if showRevoke {
                Button("Revoke", role: .destructive) {
                    Task {
                        guard let token = auth.currentToken else { return }
                        await vm.revoke(token: token, deviceId: device.deviceId)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .background(themeManager.palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func pendingCard(device: LinkedDeviceDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            deviceCard(device: device, showRevoke: false)

            HStack {
                Button("Approve") {
                    Task {
                        guard let token = auth.currentToken,
                              let user = auth.currentUser else { return }

                        await vm.approve(
                            token: token,
                            userId: user.id,
                            device: device
                        )
                    }
                }

                Spacer()

                Button("Reject", role: .destructive) {
                    Task {
                        guard let token = auth.currentToken else { return }
                        await vm.reject(token: token, deviceId: device.deviceId)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func gradientButton(
        _ text: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .font(.body.weight(.bold))
                .foregroundStyle(themeManager.palette.buttonForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [
                            themeManager.palette.buttonStart,
                            themeManager.palette.buttonEnd
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
        }
    }
}
