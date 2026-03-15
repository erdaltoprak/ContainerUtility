import SwiftUI

struct RegistriesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var registries: [RegistryEntry] = []
    @State private var selectedRegistryID: RegistryEntry.ID?

    @State private var hasLoadedInitialRegistries = false
    @State private var isPresentingLoginSheet = false
    @State private var lastErrorMessage: String?
    @State private var isSilentlyRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            listHeaderBar

            Divider()

            registriesContent

            if showsFooter {
                footerBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task {
                        await refreshRegistriesSilently()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
                .help("Refresh registries (Cmd+R)")
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    isPresentingLoginSheet = true
                } label: {
                    Label("Login", systemImage: "plus")
                }
                .disabled(isBusy)
                .help("Login to a registry")

                Button {
                    performSelectedRegistryLogout()
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(isBusy || selectedRegistry == nil)
                .help("Logout selected registry")

                if appModel.hasActiveActivity(for: .registries) {
                    Button {
                        appModel.cancelLatestActiveActivity(in: .registries)
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings (Cmd+,)")
            }
        }
        .sheet(isPresented: $isPresentingLoginSheet) {
            RegistryLoginSheet { request in
                performRegistryLogin(request: request)
            }
        }
        .task {
            guard !hasLoadedInitialRegistries else { return }
            hasLoadedInitialRegistries = true
            await refreshRegistriesSilently()
        }
        .onAppear {
            if hasLoadedInitialRegistries {
                Task {
                    await refreshRegistriesSilently()
                }
            }
        }
        .navigationTitle("")
    }

    private var listHeaderBar: some View {
        HStack {
            Text(listPanelSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if selectedRegistryID != nil {
                Text("1 selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var registriesContent: some View {
        if isBusy, registries.isEmpty {
            ProgressView("Loading registries…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if registries.isEmpty {
            if let lastErrorMessage, !lastErrorMessage.isEmpty {
                ResourceInspectorStateView(
                    descriptor: resourceListFailureDescriptor(
                        resourceName: "registries",
                        error: lastErrorMessage,
                        systemHealth: appModel.latestSystemHealthSnapshot
                    )
                )
            } else {
                ContentUnavailableView {
                    Label("No Registries Logged In", systemImage: "externaldrive.badge.wifi")
                } description: {
                    Text("Use the + Login button to authenticate a registry session.")
                } actions: {
                    Button("Login") {
                        isPresentingLoginSheet = true
                    }

                    Button("Refresh") {
                        Task {
                            await refreshRegistriesSilently()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Table(of: RegistryEntry.self, selection: $selectedRegistryID) {
                TableColumn("Hostname") { entry in
                    Text(entry.hostname)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 220, ideal: 320)

                TableColumn("Username") { entry in
                    Text(entry.username.isEmpty ? "-" : entry.username)
                        .foregroundStyle(entry.username.isEmpty ? .secondary : .primary)
                }
                .width(min: 140, ideal: 220)
            } rows: {
                ForEach(registries) { entry in
                    TableRow(entry)
                        .contextMenu {
                            Button {
                                selectedRegistryID = entry.id
                                performSelectedRegistryLogout()
                            } label: {
                                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var selectedRegistry: RegistryEntry? {
        guard let selectedRegistryID else { return nil }
        return registries.first(where: { $0.id == selectedRegistryID })
    }

    private var isBusy: Bool {
        appModel.hasActiveActivity(for: .registries) || isSilentlyRefreshing
    }

    private var latestSectionActivity: ActivityRecord? {
        appModel.latestActivity(for: .registries)
    }

    private var activeSectionActivity: ActivityRecord? {
        guard let latestSectionActivity, latestSectionActivity.status.isActive else {
            return nil
        }
        return latestSectionActivity
    }

    private var listPanelSubtitle: String {
        if isBusy, registries.isEmpty {
            return "Loading..."
        }
        return registries.count == 1 ? "1 registry logged in" : "\(registries.count) registries logged in"
    }

    private var footerBar: some View {
        ResourceListFeedbackBar(
            activity: activeSectionActivity,
            warningMessages: [],
            errorMessage: lastErrorMessage
        )
    }

    private var showsFooter: Bool {
        activeSectionActivity != nil || (lastErrorMessage?.isEmpty == false)
    }

    private func refreshRegistriesSilently() async {
        if isSilentlyRefreshing || appModel.hasActiveActivity(for: .registries) {
            return
        }

        isSilentlyRefreshing = true
        defer { isSilentlyRefreshing = false }
        lastErrorMessage = nil

        do {
            let output = try await containerCLIAdapter.listRegistries(format: "json", quiet: false)
            let entries = Self.parseRegistries(from: output)

            await MainActor.run {
                registries = entries
                appModel.registrySessionCount = entries.count
                if let selectedRegistryID, !entries.contains(where: { $0.id == selectedRegistryID }) {
                    self.selectedRegistryID = nil
                }
            }
        } catch let error as AppError {
            await recordRegistryError(error)
        } catch {
            await recordRegistryError(
                .commandLaunchFailed(
                    command: "container registry list --format json",
                    reason: error.localizedDescription
                )
            )
        }
    }

    private func performRegistryLogin(request: RegistryLoginRequest) {
        let server = request.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else { return }

        let username = request.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = request.password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            lastErrorMessage = "Password or access token is required."
            return
        }

        var arguments = ["registry", "login"]
        if !username.isEmpty {
            arguments.append(contentsOf: ["--username", username])
        }
        arguments.append("--password-stdin")
        arguments.append(server)
        let commandDescription = buildCommandDescription(arguments: arguments)

        lastErrorMessage = nil

        _ = appModel.enqueueActivity(
            title: "Registry login \(server)",
            section: .registries,
            kind: .image,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await containerCLIAdapter.loginRegistry(
                    server: server,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password,
                    usePasswordStdin: true
                )

                await MainActor.run {
                    selectedRegistryID = nil
                }
                await refreshRegistriesSilently()
                return ActivityOperationOutcome(summary: "Logged in to \(server).")
            } catch let error as AppError {
                await recordRegistryError(error)
                throw error
            } catch {
                let wrapped = AppError.commandLaunchFailed(
                    command: commandDescription,
                    reason: error.localizedDescription
                )
                await recordRegistryError(wrapped)
                throw wrapped
            }
        }
    }

    private func performSelectedRegistryLogout() {
        guard let selectedRegistry else { return }
        let server = selectedRegistry.hostname
        let commandDescription = buildCommandDescription(arguments: ["registry", "logout", server])

        lastErrorMessage = nil

        _ = appModel.enqueueActivity(
            title: "Registry logout \(server)",
            section: .registries,
            kind: .image,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await containerCLIAdapter.logoutRegistry(registry: server)

                await MainActor.run {
                    selectedRegistryID = nil
                }
                await refreshRegistriesSilently()
                return ActivityOperationOutcome(summary: "Logged out from \(server).")
            } catch let error as AppError {
                await recordRegistryError(error)
                throw error
            } catch {
                let wrapped = AppError.commandLaunchFailed(
                    command: commandDescription,
                    reason: error.localizedDescription
                )
                await recordRegistryError(wrapped)
                throw wrapped
            }
        }
    }

    private func recordRegistryError(_ error: AppError) async {
        let message = rawFailureMessage(from: error)
        await MainActor.run {
            lastErrorMessage = message
        }
    }

    private func rawFailureMessage(from error: AppError) -> String {
        switch error {
        case .commandFailed(_, _, let stderr):
            return stderr
        case .commandLaunchFailed(_, let reason):
            return reason
        case .commandTimedOut(let command, let timeout):
            return "Command timed out after \(Int(timeout))s: \(command)"
        case .commandCancelled(let command):
            return "Command cancelled: \(command)"
        }
    }

    private func buildCommandDescription(arguments: [String]) -> String {
        "container " + arguments.map(shellEscaped).joined(separator: " ")
    }

    private func shellEscaped(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%_+=:,./-"))
        if value.rangeOfCharacter(from: allowed.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func parseRegistries(from output: String) -> [RegistryEntry] {
        guard let data = output.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        guard let array = object as? [[String: Any]] else { return [] }

        let rows = array.compactMap { dictionary -> RegistryEntry? in
            let hostname = stringValue(in: dictionary, keys: ["hostname", "HOSTNAME", "registry", "server", "host"])
            guard !hostname.isEmpty else { return nil }
            let username = stringValue(in: dictionary, keys: ["username", "USERNAME", "user"])
            return RegistryEntry(hostname: hostname, username: username)
        }

        return rows.sorted {
            if $0.hostname == $1.hostname {
                return $0.username.localizedStandardCompare($1.username) == .orderedAscending
            }
            return $0.hostname.localizedStandardCompare($1.hostname) == .orderedAscending
        }
    }

    private nonisolated static func stringValue(in dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = dictionary[key] {
                return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }
}

private struct RegistryEntry: Identifiable, Hashable {
    let hostname: String
    let username: String

    var id: String {
        "\(hostname)|\(username)"
    }
}

private struct RegistryLoginRequest {
    let server: String
    let username: String
    let password: String
}

private struct RegistryLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRegistryOption: RegistryLoginPreset = .dockerHub
    @State private var manualServer = ""
    @State private var username = ""
    @State private var password = ""

    let onLogin: (RegistryLoginRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registry Login")
                .font(.title3.weight(.semibold))

            Form {
                Picker("Registry", selection: $selectedRegistryOption) {
                    ForEach(RegistryLoginPreset.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                if selectedRegistryOption == .manual {
                    TextField("Registry server", text: $manualServer)
                } else {
                    TextField("Registry server", text: .constant(selectedRegistryOption.server))
                        .disabled(true)
                }

                TextField("Username (optional)", text: $username)
                SecureField("Password or access token", text: $password)
            }
            .formStyle(.grouped)

            if isDockerHubEmailWarningVisible {
                Text("For docker.io, use your Docker ID username, not your email address.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Login") {
                    onLogin(
                        RegistryLoginRequest(
                            server: resolvedServer,
                            username: username,
                            password: password
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var trimmedServer: String {
        resolvedServer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedServer.isEmpty && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedServer: String {
        if selectedRegistryOption == .manual {
            return manualServer
        }
        return selectedRegistryOption.server
    }

    private var isDockerHubEmailWarningVisible: Bool {
        let normalizedServer = trimmedServer.lowercased()
        return (normalizedServer == "docker.io" || normalizedServer == "registry-1.docker.io")
            && trimmedUsername.contains("@")
    }
}

private enum RegistryLoginPreset: String, CaseIterable, Identifiable {
    case dockerHub
    case ghcr
    case quay
    case gcr
    case publicECR
    case microsoft
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dockerHub:
            "Docker Hub (docker.io)"
        case .ghcr:
            "GitHub Container Registry (ghcr.io)"
        case .quay:
            "Quay (quay.io)"
        case .gcr:
            "Google Container Registry (gcr.io)"
        case .publicECR:
            "Amazon ECR Public (public.ecr.aws)"
        case .microsoft:
            "Microsoft Container Registry (mcr.microsoft.com)"
        case .manual:
            "Manual..."
        }
    }

    var server: String {
        switch self {
        case .dockerHub:
            "docker.io"
        case .ghcr:
            "ghcr.io"
        case .quay:
            "quay.io"
        case .gcr:
            "gcr.io"
        case .publicECR:
            "public.ecr.aws"
        case .microsoft:
            "mcr.microsoft.com"
        case .manual:
            ""
        }
    }
}
