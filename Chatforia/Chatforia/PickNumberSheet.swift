import SwiftUI
import UniformTypeIdentifiers

private func regulatoryFieldLabel(_ field: String) -> String {
    field
        .split(separator: "_")
        .map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }
        .joined(separator: " ")
}

struct NumberRegulatoryVerificationView: View {
    @ObservedObject var vm: PhoneNumberViewModel
    let token: String?
    let onAssigned: () -> Void

    @State private var requirements: RegulatoryRequirementsDTO?
    @State private var identityAttributes: [String: String] = [:]
    @State private var missingIdentityFields: [String] = []

    @State private var selectedDocumentTypes: [String: String] = [:]
    @State private var documentRequiredFields: [String: [String]] = [:]
    @State private var documentAttributes: [String: [String: String]] = [:]
    @State private var completedDocuments: Set<String> = []
    @State private var activeDocumentRequirement: String?
    @State private var showingFileImporter = false

    @State private var bundleEmail = ""
    @State private var loadingDocumentFields = false
    @State private var uploadingDocument = false
    @State private var submittingBundle = false

    @State private var loading = false
    @State private var submittingIdentity = false
    @State private var checkingStatus = false
    @State private var identityReady = false
    @State private var reviewPending = false
    @State private var reviewRejected = false
    @State private var errorText: String?
    @State private var startedE164: String?

    private var verification: NumberRegulatoryVerificationState? {
        vm.regulatoryVerification
    }

    private var requiredIdentityFields: [String] {
        guard let requirements else {
            return []
        }

        var result: [String] = []

        for requirement in requirements.endUser ?? [] {
            for field in requirement.fields ?? [] {
                let trimmed = field.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !trimmed.isEmpty && !result.contains(trimmed) {
                    result.append(trimmed)
                }
            }
        }

        return result
    }

    private var documentRequirements:
        [RegulatorySupportingDocumentRequirementDTO] {
        guard let requirements else {
            return []
        }

        var result: [RegulatorySupportingDocumentRequirementDTO] = []
        var seen: Set<String> = []

        for group in requirements.supportingDocument ?? [] {
            for requirement in group {
                guard let name = requirement.requirementName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty,
                      !seen.contains(name)
                else {
                    continue
                }

                seen.insert(name)
                result.append(requirement)
            }
        }

        return result
    }

    private var requiredDocumentNames: [String] {
        documentRequirements.compactMap {
            $0.requirementName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var documentsReady: Bool {
        requiredDocumentNames.allSatisfy {
            completedDocuments.contains($0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Number verification")
                    .font(.title2.bold())

                if let e164 = verification?.e164 {
                    Text(e164)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if loading {
                    HStack {
                        ProgressView()
                        Text("Loading verification requirements…")
                    }
                } else if reviewPending {
                    pendingSection
                } else {
                    if reviewRejected {
                        Text(
                            "The previous verification was rejected. Review and correct the information below, then submit it again."
                        )
                        .foregroundStyle(.red)
                    }

                    if !identityReady {
                        identitySection
                    } else {
                        Text("Identity information complete.")
                            .foregroundStyle(.green)

                        if !documentsReady {
                            documentSection
                        } else {
                            bundleSection
                        }
                    }
                }

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding()
        }
        .task(id: verification?.e164) {
            await start()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [
                .jpeg,
                .png,
                .pdf
            ],
            allowsMultipleSelection: false
        ) { result in
            handleImportedDocument(result)
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        if requiredIdentityFields.isEmpty {
            Text("No additional identity fields are required.")
                .foregroundStyle(.secondary)

            Button("Continue") {
                Task {
                    await submitIdentity()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(submittingIdentity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Identity information")
                    .font(.headline)

                ForEach(requiredIdentityFields, id: \.self) { field in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(regulatoryFieldLabel(field))
                            .font(.subheadline)

                        TextField(
                            regulatoryFieldLabel(field),
                            text: Binding(
                                get: {
                                    identityAttributes[field] ?? ""
                                },
                                set: {
                                    identityAttributes[field] = $0
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        if missingIdentityFields.contains(field) {
                            Text("This field is required.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button {
                    Task {
                        await submitIdentity()
                    }
                } label: {
                    if submittingIdentity {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(submittingIdentity)
            }
        }
    }

    @ViewBuilder
    private var documentSection: some View {
        if documentRequirements.isEmpty {
            bundleSection
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("Supporting documents")
                    .font(.headline)

                Text(
                    "Upload the documents required for this phone number."
                )
                .foregroundStyle(.secondary)

                ForEach(
                    Array(documentRequirements.enumerated()),
                    id: \.offset
                ) { _, requirement in
                    documentRequirementView(requirement)
                }
            }
        }
    }

    @ViewBuilder
    private func documentRequirementView(
        _ requirement: RegulatorySupportingDocumentRequirementDTO
    ) -> some View {
        if let requirementName = requirement.requirementName,
           !requirementName.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(regulatoryFieldLabel(requirementName))
                    .font(.subheadline.bold())

                if completedDocuments.contains(requirementName) {
                    Text("Document uploaded.")
                        .foregroundStyle(.green)
                } else {
                    let accepted =
                        requirement.acceptedDocuments ?? []

                    if accepted.isEmpty {
                        Text(
                            "No accepted document type was returned for this requirement."
                        )
                        .font(.footnote)
                        .foregroundStyle(.red)
                    } else {
                        Picker(
                            "Document type",
                            selection: Binding(
                                get: {
                                    selectedDocumentTypes[
                                        requirementName
                                    ] ?? ""
                                },
                                set: { newValue in
                                    selectedDocumentTypes[
                                        requirementName
                                    ] = newValue

                                    documentRequiredFields[
                                        requirementName
                                    ] = []

                                    documentAttributes[
                                        requirementName
                                    ] = [:]

                                    Task {
                                        await loadDocumentFields(
                                            requirementName:
                                                requirementName,
                                            documentType:
                                                newValue
                                        )
                                    }
                                }
                            )
                        ) {
                            Text("Select a document")
                                .tag("")

                            ForEach(
                                Array(accepted.enumerated()),
                                id: \.offset
                            ) { _, document in
                                if let type = document.type,
                                   !type.isEmpty {
                                    Text(
                                        document.name?
                                            .trimmingCharacters(
                                                in:
                                                    .whitespacesAndNewlines
                                            )
                                            .isEmpty == false
                                        ? document.name!
                                        : regulatoryFieldLabel(type)
                                    )
                                    .tag(type)
                                }
                            }
                        }
                        .pickerStyle(.menu)

                        let fields =
                            documentRequiredFields[
                                requirementName
                            ] ?? []

                        ForEach(fields, id: \.self) { field in
                            TextField(
                                regulatoryFieldLabel(field),
                                text: Binding(
                                    get: {
                                        documentAttributes[
                                            requirementName
                                        ]?[field] ?? ""
                                    },
                                    set: { value in
                                        var attributes =
                                            documentAttributes[
                                                requirementName
                                            ] ?? [:]

                                        attributes[field] = value

                                        documentAttributes[
                                            requirementName
                                        ] = attributes
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            activeDocumentRequirement =
                                requirementName
                            showingFileImporter = true
                        } label: {
                            if uploadingDocument
                                && activeDocumentRequirement
                                    == requirementName {
                                ProgressView()
                            } else {
                                Text("Choose document")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            selectedDocumentTypes[
                                requirementName
                            ]?.isEmpty != false
                            || loadingDocumentFields
                            || uploadingDocument
                        )
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var bundleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !requiredDocumentNames.isEmpty {
                Text("Supporting documents complete.")
                    .foregroundStyle(.green)
            }

            Text("Submit for review")
                .font(.headline)

            TextField(
                "Contact email",
                text: $bundleEmail
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()

            Button {
                Task {
                    await assembleAndSubmit()
                }
            } label: {
                if submittingBundle {
                    ProgressView()
                } else {
                    Text("Submit for review")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                submittingBundle
                || bundleEmail
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            )
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Verification under review")
                .font(.headline)

            Text(
                "Your information has been submitted. Check the status to see whether the number is ready to be assigned."
            )
            .foregroundStyle(.secondary)

            Button {
                Task {
                    await checkStatus()
                }
            } label: {
                if checkingStatus {
                    ProgressView()
                } else {
                    Text("Check status")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(checkingStatus)
        }
    }

    @MainActor
    private func start() async {
        guard let verification else {
            return
        }

        if startedE164 != verification.e164 {
            startedE164 = verification.e164
            requirements = nil
            identityAttributes = [:]
            missingIdentityFields = []
            selectedDocumentTypes = [:]
            documentRequiredFields = [:]
            documentAttributes = [:]
            completedDocuments = []
            activeDocumentRequirement = nil
            showingFileImporter = false
            bundleEmail = ""
            identityReady = false
        }

        errorText = nil
        reviewPending =
            verification.decision == "VERIFICATION_PENDING"
        reviewRejected =
            verification.decision == "VERIFICATION_REJECTED"

        if reviewPending {
            loading = false
            return
        }

        await initialize()
    }

    @MainActor
    private func initialize() async {
        guard let e164 = verification?.e164 else {
            return
        }

        loading = true
        errorText = nil
        defer { loading = false }

        do {
            let response =
                try await NumberRegulatoryService.shared.initialize(
                    e164: e164,
                    token: token
                )

            requirements = response.requirements
            missingIdentityFields =
                response.validation?.missingFields ?? []

            if response.profile?.endUserSid != nil {
                identityReady = true
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func submitIdentity() async {
        guard let e164 = verification?.e164 else {
            return
        }

        let missing = requiredIdentityFields.filter {
            identityAttributes[$0]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty != false
        }

        if !missing.isEmpty {
            missingIdentityFields = missing
            errorText = "Complete all required identity fields."
            return
        }

        submittingIdentity = true
        errorText = nil
        defer { submittingIdentity = false }

        do {
            let response =
                try await NumberRegulatoryService.shared.initialize(
                    e164: e164,
                    endUserAttributes: identityAttributes,
                    token: token
                )

            requirements = response.requirements ?? requirements
            missingIdentityFields =
                response.validation?.missingFields ?? []

            if response.initialized == true,
               response.profile?.endUserSid != nil {
                identityReady = true
                reviewRejected = false
                return
            }

            errorText =
                response.reason
                ?? "Could not complete identity verification."
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadDocumentFields(
        requirementName: String,
        documentType: String
    ) async {
        guard let e164 = verification?.e164,
              !documentType.isEmpty
        else {
            return
        }

        loadingDocumentFields = true
        errorText = nil
        defer { loadingDocumentFields = false }

        do {
            let response =
                try await NumberRegulatoryService.shared
                    .documentRequirements(
                        e164: e164,
                        requirementName: requirementName,
                        documentType: documentType,
                        token: token
                    )

            guard response.resolved == true else {
                errorText =
                    response.reason
                    ?? "Could not load document requirements."
                return
            }

            documentRequiredFields[requirementName] =
                response.requiredFields ?? []

            var attributes =
                documentAttributes[requirementName] ?? [:]

            for field in response.requiredFields ?? [] {
                if attributes[field] == nil {
                    attributes[field] = ""
                }
            }

            documentAttributes[requirementName] = attributes
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func handleImportedDocument(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first,
                  let requirementName =
                    activeDocumentRequirement,
                  let documentType =
                    selectedDocumentTypes[
                        requirementName
                    ],
                  !documentType.isEmpty
            else {
                errorText =
                    "Choose a document type before uploading."
                return
            }

            Task {
                await uploadDocument(
                    url: url,
                    requirementName: requirementName,
                    documentType: documentType
                )
            }
        }
    }

    @MainActor
    private func uploadDocument(
        url: URL,
        requirementName: String,
        documentType: String
    ) async {
        guard let e164 = verification?.e164 else {
            return
        }

        let fields =
            documentRequiredFields[requirementName] ?? []

        let attributes =
            documentAttributes[requirementName] ?? [:]

        let missing = fields.filter {
            attributes[$0]?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty != false
        }

        guard missing.isEmpty else {
            errorText =
                "Complete all required document fields."
            return
        }

        uploadingDocument = true
        errorText = nil
        defer {
            uploadingDocument = false
            activeDocumentRequirement = nil
        }

        let accessed =
            url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values =
                try url.resourceValues(
                    forKeys: [.contentTypeKey]
                )

            let contentType =
                values.contentType
                ?? UTType(filenameExtension:
                    url.pathExtension)

            let mimeType: String

            if contentType?.conforms(to: .jpeg) == true {
                mimeType = "image/jpeg"
            } else if contentType?.conforms(to: .png) == true {
                mimeType = "image/png"
            } else if contentType?.conforms(to: .pdf) == true {
                mimeType = "application/pdf"
            } else {
                errorText =
                    "Choose a JPEG, PNG, or PDF document."
                return
            }

            let data = try Data(contentsOf: url)

            guard data.count <= 5 * 1024 * 1024 else {
                errorText =
                    "Regulatory documents must be 5 MB or smaller."
                return
            }

            let response =
                try await NumberRegulatoryService.shared
                    .uploadDocument(
                        e164: e164,
                        requirementName: requirementName,
                        documentType: documentType,
                        attributes: attributes,
                        fileData: data,
                        fileName:
                            url.lastPathComponent.isEmpty
                            ? "document"
                            : url.lastPathComponent,
                        mimeType: mimeType,
                        token: token
                    )

            if response.provisioned == true
                || response.reused == true {
                completedDocuments.insert(
                    requirementName
                )
                errorText = nil
                return
            }

            documentRequiredFields[requirementName] =
                response.requiredFields
                ?? documentRequiredFields[
                    requirementName
                ]
                ?? []

            errorText =
                response.reason
                ?? "Could not upload the document."
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func assembleAndSubmit() async {
        guard let e164 = verification?.e164 else {
            return
        }

        guard documentsReady else {
            errorText =
                "Upload all required supporting documents first."
            return
        }

        let email =
            bundleEmail.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !email.isEmpty else {
            errorText = "Enter a contact email."
            return
        }

        submittingBundle = true
        errorText = nil
        defer { submittingBundle = false }

        do {
            let assembled =
                try await NumberRegulatoryService.shared
                    .assemble(
                        e164: e164,
                        email: email,
                        token: token
                    )

            guard assembled.assembled == true else {
                errorText =
                    assembled.reason
                    ?? "Could not assemble the verification."
                return
            }

            let submitted =
                try await NumberRegulatoryService.shared
                    .submit(
                        e164: e164,
                        token: token
                    )

            guard submitted.submitted == true else {
                errorText =
                    submitted.reason
                    ?? "Could not submit the verification."
                return
            }

            reviewPending = true
            reviewRejected = false
        } catch let apiError as APIError {
            if case .server(
                let status,
                let code,
                _,
                _
            ) = apiError,
               status == 409,
               code == "REGULATORY_RESERVATION_EXPIRED" {
                errorText =
                    "This number's verification reservation expired. Select the number again to restart verification."
                return
            }

            errorText = apiError.localizedDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func checkStatus() async {
        guard let e164 = verification?.e164 else {
            return
        }

        checkingStatus = true
        errorText = nil
        defer { checkingStatus = false }

        do {
            let response =
                try await NumberRegulatoryService.shared.status(
                    e164: e164,
                    token: token
                )

            switch response.decision {
            case "APPROVED":
                guard response.allowed == true else {
                    errorText =
                        "Verification is not ready for assignment yet."
                    return
                }

                let assigned =
                    await vm.retryRegulatoryLease(token: token)

                if assigned {
                    onAssigned()
                    return
                }

                if let nextVerification = vm.regulatoryVerification {
                    switch nextVerification.decision {
                    case "VERIFICATION_PENDING":
                        reviewPending = true
                        reviewRejected = false

                    case "VERIFICATION_REJECTED":
                        reviewPending = false
                        reviewRejected = true
                        await initialize()

                    case "VERIFICATION_REQUIRED":
                        reviewPending = false
                        reviewRejected = false
                        await initialize()

                    default:
                        errorText =
                            nextVerification.decision
                    }

                    return
                }

                if let vmError = vm.errorText {
                    errorText = vmError
                } else {
                    errorText =
                        "The number could not be assigned yet."
                }

            case "VERIFICATION_PENDING":
                reviewPending = true
                reviewRejected = false

            case "VERIFICATION_REJECTED":
                reviewPending = false
                reviewRejected = true
                await initialize()

            case "VERIFICATION_REQUIRED":
                reviewPending = false
                reviewRejected = false
                await initialize()

            default:
                errorText =
                    response.error
                    ?? response.decision
                    ?? "Could not determine verification status."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct PickNumberSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("chatforia_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    @StateObject var vm: PhoneNumberViewModel
    @State private var showUpgradeSheet = false
    @State private var showRegulatoryVerification = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modePicker
                    subtitleText
                    searchControls
                    lockInfo
                    availableHeader
                    resultsContent
                }
                .padding(16)
            }
            .background(themeManager.palette.screenBackground.ignoresSafeArea())
            .navigationTitle(
                appText(
                    "phoneNumber.pickNumber",
                    languageCode: appLanguage
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(themeManager.palette.secondaryText)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showUpgradeSheet) {
            NavigationStack {
                UpgradeView(trigger: .keepNumber)
            }
            .environmentObject(auth)
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showRegulatoryVerification) {
            NavigationStack {
                NumberRegulatoryVerificationView(
                    vm: vm,
                    token: auth.currentToken,
                    onAssigned: {
                        showRegulatoryVerification = false
                        dismiss()
                    }
                )
                .navigationTitle("Number verification")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            showRegulatoryVerification = false
                        }
                    }
                }
            }
        }
        .onChange(of: vm.regulatoryVerification?.e164) {
            _, newValue in

            if newValue != nil {
                showRegulatoryVerification = true
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(NumberPickMode.allCases) { mode in
                Button {
                    vm.mode = mode
                    vm.availableNumbers = []
                    vm.errorText = nil
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(vm.mode == mode ? themeManager.palette.accent : themeManager.palette.cardBackground)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subtitleText: some View {
        Text(vm.mode.subtitle)
            .font(.subheadline)
            .foregroundStyle(themeManager.palette.secondaryText)
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    appText(
                        "common.country",
                        languageCode: appLanguage
                    )
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Picker(
                    appText(
                        "common.country",
                        languageCode: appLanguage
                    ),
                    selection: $vm.selectedCountry
                ) {
                    ForEach(vm.countryOptions) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .tint(themeManager.palette.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        appText(
                            "phoneNumber.areaCode",
                            languageCode: appLanguage
                        )
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.palette.primaryText)

                    TextField(
                        appText(
                            "phoneNumber.exampleAreaCode",
                            languageCode: appLanguage
                        ),
                        text: $vm.areaCode
                    )
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(themeManager.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(themeManager.palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .frame(maxWidth: .infinity)

                Button {
                    debugLog("🔎 Search tapped")
                    Task {
                        await MainActor.run {
                            debugLog("🚀 calling vm.search()")
                        }
                        await vm.search(token: auth.currentToken)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text(
                            appText(
                                "common.search",
                                languageCode: appLanguage
                            )
                        )                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(themeManager.palette.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vm.isSearching)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    appText(
                        "phoneNumber.capability",
                        languageCode: appLanguage
                    )
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.palette.primaryText)

                Picker(
                    appText(
                        "phoneNumber.capability",
                        languageCode: appLanguage
                    ),
                    selection: $vm.selectedCapability
                ) {
                    Text(appText("phoneNumber.sms", languageCode: appLanguage))
                        .tag("sms")

                    Text(appText("phoneNumber.voice", languageCode: appLanguage))
                        .tag("voice")

                    Text(appText("phoneNumber.smsVoice", languageCode: appLanguage))
                        .tag("both")
                }
                .pickerStyle(.menu)
                .tint(themeManager.palette.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(themeManager.palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(themeManager.palette.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var lockInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(themeManager.palette.secondaryText)

            Text(
                appText(
                    "phoneNumber.premiumProtected",
                    languageCode: appLanguage
                )
            )
                .font(.footnote)
                .foregroundStyle(themeManager.palette.secondaryText)
        }
    }

    private var availableHeader: some View {
        VStack(spacing: 8) {
            Divider()
            Text(
                appText(
                    "dialer.availableNumbers",
                    languageCode: appLanguage
                )
            )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeManager.palette.secondaryText)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let error = vm.errorText, !error.isEmpty {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if vm.isSearching {
            ProgressView(
                appText(
                    "common.searching",
                    languageCode: appLanguage
                )
            )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        } else if vm.availableNumbers.isEmpty {
            Text(
                appText(
                    "phoneNumber.areaCodeSearchHint",
                    languageCode: appLanguage
                )
            )
                .font(.subheadline)
                .foregroundStyle(themeManager.palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        } else {
            VStack(spacing: 12) {
                ForEach(vm.availableNumbers) { number in
                    numberCard(number)
                }
            }
        }
    }

    private func numberCard(_ number: AvailableNumberDTO) -> some View {
        let e164 =
            number.e164
            ?? number.number
            ?? appText(
                "common.unknown",
                languageCode: appLanguage
            )
        let baseLocation = number.locality ?? number.local ?? number.display ?? ""

        let location =
            !baseLocation.isEmpty && !baseLocation.contains(",")
            ? [baseLocation, number.region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            : baseLocation
        
        let caps = number.capabilities?.values ?? []

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "phone")
                    .foregroundStyle(themeManager.palette.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(e164)
                        .font(.system(size: 17, weight: .semibold)) // slightly bigger & clearer
                        .foregroundStyle(themeManager.palette.primaryText)
                    
                    if !location.isEmpty {
                        Text(location)
                            .font(.system(size: 14)) // was too small before
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    if !caps.isEmpty {
                        Text(caps.joined(separator: " • ").uppercased())
                            .font(.system(size: 13, weight: .medium)) // slightly stronger
                            .foregroundStyle(themeManager.palette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer()

                Button(
                    vm.mode == .premium
                        ? appText(
                            "common.keep",
                            languageCode: appLanguage
                        )
                        : appText(
                            "common.select",
                            languageCode: appLanguage
                        )
                ) {
                    if vm.mode == .premium && !auth.isPremium {
                        showUpgradeSheet = true
                        return
                    }

                    Task {
                        let ok = await vm.lease(number, token: auth.currentToken)

                        if !ok,
                           let error = vm.errorText?.lowercased(),
                           error.contains("premium") {
                            showUpgradeSheet = true
                            return
                        }

                        if ok {
                            dismiss()
                        } else if vm.regulatoryVerification != nil {
                            showRegulatoryVerification = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isLeasing || vm.currentNumber != nil)
            }
        }
        .padding(14)
        .background(themeManager.palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(themeManager.palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
