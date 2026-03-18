import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var phone = ""
    @State private var smsConsent = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let registrationService = RegistrationService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Create Account")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)

                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .textFieldStyle(.roundedBorder)

                if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Toggle(isOn: $smsConsent) {
                        Text("I consent to receive SMS messages from Chatforia.")
                            .font(.subheadline)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let successMessage {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                Text("By creating an account you agree to our Terms of Service and Privacy Policy.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        errorMessage = nil
        successMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            errorMessage = "Username is required."
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Password is required."
            return
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        if !trimmedPhone.isEmpty && !smsConsent {
            errorMessage = "Please consent to SMS messages or remove the phone number."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await registrationService.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                smsConsent: trimmedPhone.isEmpty ? nil : smsConsent
            )

            // If backend auto-logs in on registration, use the token path you already have.
            if let token = response.token {
                await auth.setTokenAndLoadUser(token)
                return
            }

            successMessage = response.message ?? "Account created successfully. Please log in."
        } catch {
            errorMessage = friendlyRegistrationError(error)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func friendlyRegistrationError(_ error: Error) -> String {
        let nsError = error as NSError

        if let apiMessage = nsError.userInfo["message"] as? String, !apiMessage.isEmpty {
            return apiMessage
        }

        return error.localizedDescription
    }
}
