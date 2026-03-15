import SwiftUI

struct ContainersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var searchText = ""
    @State private var filter = ContainerFilter.all
    @State private var sortOrder = [KeyPathComparator<ContainerRow>(\.name, order: .forward)]
    @State private var selectedContainerIDs = Set<String>()
    @State private var containers: [ContainerListItem] = []
    @State private var decodeWarnings: [String] = []
    @State private var rawFallbackOutput: String?
    @State private var isLoading = false
    @State private var isPresentingCreateSheet = false
    @State private var lastError: AppError?
    @State private var confirmationAction: ConfirmationAction?
    @State private var listTask: Task<Void, Never>?
    @State private var showInspector = true
    @State private var hasCompletedInitialLoad = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                listHeaderBar

                Divider()

                if filteredRows.isEmpty {
                    emptyStateSidebar
                } else {
                    containerTable
                }

                if showsFooter {
                    footerBar
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
            .background(.background)

            if showInspector {
                detailPane
                    .frame(minWidth: 550, idealWidth: 550, maxWidth: 700)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                filterPicker
                lifecycleButtons

                Button {
                    isPresentingCreateSheet = true
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .disabled(isBusy)
                .help("Create a new container (\u{2318}N)")
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    reloadContainers()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
                .help("Refresh container list (\u{2318}R)")
                .keyboardShortcut("r", modifiers: .command)

                if isBusy {
                    Button {
                        cancelRunningTask()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .help("Cancel running operation")
                    .keyboardShortcut(.cancelAction)
                }

                destructiveButtons
            }

            ToolbarItem(placement: .navigation) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings (\u{2318},)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        showInspector.toggle()
                    }
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (\u{2318}I)")
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .sheet(isPresented: $isPresentingCreateSheet) {
            ContainerCreateSheet(
                suggestedImageReference: appModel.images.first?.reference ?? "",
                availableImageReferences: appModel.images.map(\.reference),
                availableNetworkNames: appModel.networks.map(\.name),
                onCreate: { request in
                    executeContainerOperation(request: request)
                }
            )
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            presenting: confirmationAction
        ) { action in
            switch action {
            case .kill(let ids, let count):
                Button("Kill \(count == 1 ? "Container" : "Containers")", role: .destructive) {
                    enqueueLifecycleAction(
                        title: "Kill \(count) container(s)",
                        summary: "Killed \(count) container(s).",
                        commandDescription: "container kill \(ids.joined(separator: " "))"
                    ) {
                        try await containerCLIAdapter.killContainers(ids: ids)
                    }
                }
            case .delete(let ids, let count):
                Button("Delete \(count == 1 ? "Container" : "Containers")", role: .destructive) {
                    enqueueLifecycleAction(
                        title: "Delete \(count) container(s)",
                        summary: "Deleted \(count) container(s).",
                        commandDescription: "container delete \(ids.joined(separator: " "))"
                    ) {
                        try await containerCLIAdapter.deleteContainers(ids: ids)
                    }
                }
            case .prune:
                Button("Prune Stopped Containers", role: .destructive) {
                    enqueueLifecycleAction(
                        title: "Prune stopped containers",
                        summary: "Pruned stopped containers.",
                        commandDescription: "container prune"
                    ) {
                        try await containerCLIAdapter.pruneContainers()
                    }
                }
            }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
        .task {
            if containers.isEmpty, !appModel.cachedContainerItems.isEmpty {
                containers = appModel.cachedContainerItems
                hasCompletedInitialLoad = true
            }
            reloadContainers()
        }
        .onChange(of: appModel.refreshRevision(for: .containers)) { _, _ in
            guard !isLoading else { return }
            reloadContainers()
        }
        .onChange(of: selectedContainerIDs) { _, newValue in
            if newValue.count == 1 && !showInspector {
                showInspector = true
            }
        }
        .onDisappear {
            listTask?.cancel()
        }
        .navigationTitle("")
    }

    // MARK: - Toolbar Components

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ContainerFilter.allCases) { f in
                Text(f.title).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var lifecycleButtons: some View {
        ControlGroup {
            Button {
                let ids = selectedStoppedContainers.map(\.id)
                enqueueLifecycleAction(
                    title: "Start \(ids.count) container(s)",
                    summary: "Started \(ids.count) container(s).",
                    commandDescription: "container start \(ids.joined(separator: " "))"
                ) {
                    try await containerCLIAdapter.startContainers(ids: ids)
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(isBusy || selectedStoppedContainers.isEmpty)
            .help("Start selected containers")

            Button {
                let ids = selectedRunningContainers.map(\.id)
                enqueueLifecycleAction(
                    title: "Stop \(ids.count) container(s)",
                    summary: "Stopped \(ids.count) container(s).",
                    commandDescription: "container stop \(ids.joined(separator: " "))"
                ) {
                    try await containerCLIAdapter.stopContainers(ids: ids)
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(isBusy || selectedRunningContainers.isEmpty)
            .help("Stop selected containers")

            Button {
                let ids = selectedRunningContainers.map(\.id)
                enqueueLifecycleAction(
                    title: "Restart \(ids.count) container(s)",
                    summary: "Restarted \(ids.count) container(s).",
                    commandDescription: "container restart \(ids.joined(separator: " "))"
                ) {
                    try await containerCLIAdapter.restartContainers(ids: ids)
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy || selectedRunningContainers.isEmpty)
            .help("Restart selected containers")
        }
    }

    @ViewBuilder
    private var destructiveButtons: some View {
        Button {
            confirmationAction = .kill(
                ids: selectedRunningContainers.map(\.id),
                count: selectedRunningContainers.count
            )
        } label: {
            Label("Kill", systemImage: "xmark.octagon")
        }
        .disabled(isBusy || selectedRunningContainers.isEmpty)
        .help("Kill selected running containers")

        Button {
            confirmationAction = .delete(
                ids: selectedContainers.map(\.id),
                count: selectedContainers.count
            )
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(isBusy || selectedContainers.isEmpty || !selectedRunningContainers.isEmpty)
        .help("Delete selected stopped containers")

        Button {
            confirmationAction = .prune
        } label: {
            Label("Prune", systemImage: "scissors")
        }
        .disabled(isBusy || containers.isEmpty)
        .help("Prune all stopped containers")
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func containerContextMenu(for row: ContainerRow) -> some View {
        if let container = containers.first(where: { $0.id == row.id }) {
            if !container.isRunning {
                Button {
                    enqueueLifecycleAction(
                        title: "Start 1 container(s)",
                        summary: "Started 1 container(s).",
                        commandDescription: "container start \(container.id)"
                    ) {
                        try await containerCLIAdapter.startContainers(ids: [container.id])
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            } else {
                Button {
                    enqueueLifecycleAction(
                        title: "Stop 1 container(s)",
                        summary: "Stopped 1 container(s).",
                        commandDescription: "container stop \(container.id)"
                    ) {
                        try await containerCLIAdapter.stopContainers(ids: [container.id])
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                Button {
                    enqueueLifecycleAction(
                        title: "Restart 1 container(s)",
                        summary: "Restarted 1 container(s).",
                        commandDescription: "container restart \(container.id)"
                    ) {
                        try await containerCLIAdapter.restartContainers(ids: [container.id])
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }

            Divider()

            Button {
                let command = "container inspect \(container.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Label("Copy Inspect Command", systemImage: "doc.on.doc")
            }

            Button {
                let command = "container exec -it \(container.id) /bin/sh"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Label("Copy Shell Command", systemImage: "terminal")
            }

            Divider()

            Button(role: .destructive) {
                confirmationAction = .delete(ids: [container.id], count: 1)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(container.isRunning)
        }
    }

    // MARK: - List Header Bar

    private var listHeaderBar: some View {
        HStack {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !selectedContainerIDs.isEmpty {
                Text("\(selectedContainerIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let selectedContainer {
                ContainerDetailWorkspaceView(container: selectedContainer)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView {
                    Label("No Container Selected", systemImage: "shippingbox")
                } description: {
                    Text("Select a container to view logs, stats, and details.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
    }

    // MARK: - List Pane

    private var emptyStateSidebar: some View {
        ResourceEmptyStateSurface(backgroundOpacity: 0.08) {
            Group {
                if !hasCompletedInitialLoad || isLoading {
                    ProgressView("Loading containers\u{2026}")
                        .frame(maxWidth: .infinity)
                } else if searchText.isEmpty, filter == .all, let lastError {
                    ResourceInspectorStateView(
                        descriptor: resourceListFailureDescriptor(
                            resourceName: "containers",
                            error: lastError.localizedDescription,
                            systemHealth: appModel.latestSystemHealthSnapshot
                        )
                    )
                } else {
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: "shippingbox")
                    } description: {
                        Text(emptyStateDetail)
                    }
                }
            }
        }
    }

    private var containerTable: some View {
        Table(of: ContainerRow.self, selection: $selectedContainerIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .fontWeight(.medium)
                    Text(row.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 100, ideal: 200)

            TableColumn("State", value: \.stateSortKey) { row in
                HStack(spacing: 4) {
                    Circle()
                        .fill(row.stateColor)
                        .frame(width: 8, height: 8)
                    Text(row.stateDisplay)
                        .foregroundStyle(row.stateColor)
                }
            }
            .width(min: 60, ideal: 90)

            TableColumn("Image", value: \.imageDisplayName) { row in
                Text(row.imageDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 100, ideal: 240)
        } rows: {
            ForEach(filteredRows) { row in
                TableRow(row)
                    .contextMenu {
                        containerContextMenu(for: row)
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Footer

    private var footerBar: some View {
        ResourceListFeedbackBar(
            activity: activeSectionActivity,
            warningMessages: decodeWarnings,
            errorMessage: lastError?.localizedDescription
        )
    }

    // MARK: - Computed Properties

    private var isBusy: Bool {
        isLoading || appModel.hasActiveActivity(for: .containers)
    }

    private var allRows: [ContainerRow] {
        containers.map(ContainerRow.init)
    }

    private var filteredRows: [ContainerRow] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var rows = allRows.filter { row in
            switch filter {
            case .all:
                true
            case .running:
                row.isRunning
            case .stopped:
                !row.isRunning
            }
        }

        if !search.isEmpty {
            rows = rows.filter { $0.searchBlob.contains(search) }
        }

        rows.sort(using: sortOrder)
        return rows
    }

    private var selectedContainers: [ContainerListItem] {
        containers.filter { selectedContainerIDs.contains($0.id) }
    }

    private var selectedRunningContainers: [ContainerListItem] {
        selectedContainers.filter(\.isRunning)
    }

    private var selectedStoppedContainers: [ContainerListItem] {
        selectedContainers.filter { !$0.isRunning }
    }

    private var selectedContainer: ContainerListItem? {
        guard selectedContainers.count == 1 else { return nil }
        return selectedContainers.first
    }

    private var summaryText: String {
        let total = containers.count
        let running = containers.filter(\.isRunning).count
        let stopped = total - running
        return "\(running) running, \(stopped) stopped, \(total) total"
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            "No Matching Containers"
        } else if filter == .running {
            "No Running Containers"
        } else if filter == .stopped {
            "No Stopped Containers"
        } else {
            "No Containers"
        }
    }

    private var emptyStateDetail: String {
        if !searchText.isEmpty {
            return "Adjust the search or filter to broaden the results."
        }
        return "Refresh the list after starting or creating containers."
    }

    private var showsFooter: Bool {
        activeSectionActivity != nil || !decodeWarnings.isEmpty || lastError != nil
    }

    private var confirmationTitle: String {
        switch confirmationAction {
        case .kill(_, let count):
            "Kill \(count == 1 ? "Container" : "Containers")"
        case .delete(_, let count):
            "Delete \(count == 1 ? "Container" : "Containers")"
        case .prune:
            "Prune Stopped Containers"
        case .none:
            ""
        }
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { confirmationAction != nil },
            set: { isPresented in
                if !isPresented {
                    confirmationAction = nil
                }
            }
        )
    }

    private var latestSectionActivity: ActivityRecord? {
        appModel.latestActivity(for: .containers)
    }

    private var activeSectionActivity: ActivityRecord? {
        guard let latestSectionActivity, latestSectionActivity.status.isActive else {
            return nil
        }
        return latestSectionActivity
    }

    // MARK: - Actions

    private func reloadContainers() {
        listTask?.cancel()
        let shouldShowLoading = containers.isEmpty
        if shouldShowLoading {
            isLoading = true
        }
        lastError = nil

        listTask = Task {
            do {
                let result = try await containerCLIAdapter.listContainers()

                await MainActor.run {
                    applyListResult(result)
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    if shouldShowLoading {
                        containers = []
                        appModel.updateContainers(from: [])
                        decodeWarnings = []
                        rawFallbackOutput = nil
                    }
                    lastError = error
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            } catch {
                await MainActor.run {
                    if shouldShowLoading {
                        containers = []
                        appModel.updateContainers(from: [])
                        decodeWarnings = []
                        rawFallbackOutput = nil
                    }
                    lastError = .commandLaunchFailed(
                        command: "container list --all --format json",
                        reason: error.localizedDescription
                    )
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            }
        }
    }

    private func executeContainerOperation(request: ContainerCreateViewRequest) {
        lastError = nil

        let adapterRequest = ContainerCreateRequest(
            imageReference: request.imageReference,
            name: request.name,
            commandArguments: request.commandArguments,
            environment: request.environment,
            publishedPorts: request.publishedPorts,
            volumeMounts: request.volumeMounts,
            network: request.network,
            workingDirectory: request.workingDirectory,
            cpuCount: request.cpuCount,
            memory: request.memory,
            initializeContainer: request.initializeContainer,
            initImageReference: request.initImageReference,
            readOnlyRootFilesystem: request.readOnlyRootFilesystem,
            removeWhenStopped: request.removeWhenStopped,
            platform: request.platform,
            architecture: request.architecture,
            operatingSystem: request.operatingSystem,
            virtualization: request.virtualization,
            useRosetta: request.useRosetta,
            enableDefaultSSHForwarding: request.enableDefaultSSHForwarding,
            sshAgents: request.sshAgents,
            environmentFiles: request.environmentFiles,
            user: request.user,
            uid: request.uid,
            gid: request.gid,
            mounts: request.mounts
        )
        let titleName = request.name ?? request.imageReference
        let title: String
        let completionSummary: String
        let fallbackCommand: String

        switch request.operation {
        case .createOnly:
            title = "Create \(titleName)"
            completionSummary = "Created container \(titleName)."
            fallbackCommand = "container create"
        case .createAndStart:
            title = "Create & start \(titleName)"
            completionSummary = "Created and started container \(titleName)."
            fallbackCommand = "container create"
        case .runDetached:
            title = "Run \(titleName)"
            completionSummary = "Started container \(titleName)."
            fallbackCommand = "container run"
        }

        _ = appModel.enqueueActivity(
            title: title,
            section: .containers,
            kind: .container,
            commandDescription: request.commandDescription
        ) { _ in
            do {
                switch request.operation {
                case .createOnly:
                    _ = try await containerCLIAdapter.createContainer(request: adapterRequest)
                case .createAndStart:
                    let createdID = try await containerCLIAdapter.createContainer(request: adapterRequest)
                    let startIdentifier = createdID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallbackName = request.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !startIdentifier.isEmpty {
                        try await containerCLIAdapter.startContainers(ids: [startIdentifier])
                    } else if !fallbackName.isEmpty {
                        try await containerCLIAdapter.startContainers(ids: [fallbackName])
                    }
                case .runDetached:
                    _ = try await containerCLIAdapter.runContainer(request: adapterRequest, detached: true)
                }
                await refreshContainerSummary()
                return ActivityOperationOutcome(summary: completionSummary)
            } catch let error as AppError {
                await refreshContainerSummary()
                throw error
            } catch {
                await refreshContainerSummary()
                throw AppError.commandLaunchFailed(
                    command: fallbackCommand,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func enqueueLifecycleAction(
        title: String,
        summary: String,
        commandDescription: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        confirmationAction = nil
        lastError = nil
        let completionSummary = summary

        _ = appModel.enqueueActivity(
            title: title,
            section: .containers,
            kind: .container,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await operation()
                await refreshContainerSummary()
                return ActivityOperationOutcome(summary: completionSummary)
            } catch let error as AppError {
                await refreshContainerSummary()
                throw error
            } catch {
                await refreshContainerSummary()
                throw AppError.commandLaunchFailed(
                    command: commandDescription,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func refreshContainerSummary() async {
        if let result = try? await containerCLIAdapter.listContainers() {
            if case .parsed(let value, _) = result {
                appModel.cachedContainerItems = value
            }
            appModel.updateContainerSummary(from: result)
        }
        appModel.bumpRefreshRevision(for: .containers)
    }

    private func applyListResult(_ result: NonCriticalDecodeResult<[ContainerListItem]>) {
        switch result {
        case .parsed(let value, let diagnostics):
            containers = value
            appModel.cachedContainerItems = value
            appModel.updateContainers(from: value)
            decodeWarnings = diagnostics.warnings
            rawFallbackOutput = nil
        case .raw(let output, let diagnostics):
            decodeWarnings = diagnostics.warnings
            rawFallbackOutput = output
        }

        let validIDs = Set(containers.map(\.id))
        selectedContainerIDs = selectedContainerIDs.intersection(validIDs)
    }

    private func cancelRunningTask() {
        if isLoading {
            listTask?.cancel()
            isLoading = false
            listTask = nil
        } else {
            appModel.cancelLatestActiveActivity(in: .containers)
        }
    }

    private func confirmationMessage(for action: ConfirmationAction) -> String {
        switch action {
        case .kill(_, let count):
            "This sends SIGKILL to \(count == 1 ? "the selected container" : "the selected containers")."
        case .delete(_, let count):
            "This removes \(count == 1 ? "the selected stopped container" : "the selected stopped containers")."
        case .prune:
            "This removes all stopped containers."
        }
    }
}

private enum ContainerFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case stopped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .running:
            "Running"
        case .stopped:
            "Stopped"
        }
    }
}

private enum ConfirmationAction: Identifiable {
    case kill(ids: [String], count: Int)
    case delete(ids: [String], count: Int)
    case prune

    var id: String {
        switch self {
        case .kill(let ids, _):
            "kill-\(ids.joined(separator: "-"))"
        case .delete(let ids, _):
            "delete-\(ids.joined(separator: "-"))"
        case .prune:
            "prune"
        }
    }
}

private struct ContainerRow: Identifiable, Hashable {
    let item: ContainerListItem

    var id: String { item.id }
    var name: String { item.name }
    var stateDisplay: String { item.stateDisplay }
    var stateSortKey: String { item.state.lowercased() }
    var imageDisplayName: String { item.imageDisplayName }
    var statusDisplay: String { item.statusDisplay }
    var isRunning: Bool { item.isRunning }
    var searchBlob: String { item.matchesSearchText }

    var stateColor: Color {
        if isRunning {
            return .green
        }
        return .secondary
    }
}

private enum ContainerLaunchOperation: String, CaseIterable, Identifiable {
    case createOnly
    case createAndStart
    case runDetached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createOnly:
            "Create Only"
        case .createAndStart:
            "Create + Start"
        case .runDetached:
            "Run Now"
        }
    }

    var description: String {
        switch self {
        case .createOnly:
            "Uses container create and leaves the container stopped."
        case .createAndStart:
            "Uses container create, then starts the created container."
        case .runDetached:
            "Uses container run --detach for immediate execution."
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .createOnly:
            "Create"
        case .createAndStart:
            "Create & Start"
        case .runDetached:
            "Run"
        }
    }

    var commandName: String {
        switch self {
        case .createOnly, .createAndStart:
            "create"
        case .runDetached:
            "run"
        }
    }
}

private struct ContainerCreateViewRequest {
    let operation: ContainerLaunchOperation
    let imageReference: String
    let name: String?
    let commandArguments: [String]
    let environment: [String: String]
    let environmentFiles: [String]
    let publishedPorts: [String]
    let volumeMounts: [String]
    let mounts: [String]
    let network: String?
    let workingDirectory: String?
    let cpuCount: Int?
    let memory: String?
    let initializeContainer: Bool
    let initImageReference: String?
    let readOnlyRootFilesystem: Bool
    let removeWhenStopped: Bool
    let platform: String?
    let architecture: String?
    let operatingSystem: String?
    let virtualization: String?
    let useRosetta: Bool
    let enableDefaultSSHForwarding: Bool
    let sshAgents: [String]
    let user: String?
    let uid: String?
    let gid: String?

    var commandDescription: String {
        var components = ["container", operation.commandName]
        if operation == .runDetached {
            components.append("--detach")
        }

        if let name = Self.trimmedNonEmpty(name) {
            components.append(contentsOf: ["--name", name])
        }

        if let cpuCount, cpuCount > 0 {
            components.append(contentsOf: ["--cpus", String(cpuCount)])
        }

        if let memory = Self.trimmedNonEmpty(memory) {
            components.append(contentsOf: ["--memory", memory])
        }

        if initializeContainer {
            components.append("--init")
        }

        if let initImageReference = Self.trimmedNonEmpty(initImageReference) {
            components.append(contentsOf: ["--init-image", initImageReference])
        }

        if readOnlyRootFilesystem {
            components.append("--read-only")
        }

        if removeWhenStopped {
            components.append("--rm")
        }

        if let platform = Self.trimmedNonEmpty(platform) {
            components.append(contentsOf: ["--platform", platform])
        } else {
            if let architecture = Self.trimmedNonEmpty(architecture) {
                components.append(contentsOf: ["--arch", architecture])
            }

            if let operatingSystem = Self.trimmedNonEmpty(operatingSystem) {
                components.append(contentsOf: ["--os", operatingSystem])
            }
        }

        if let virtualization = Self.trimmedNonEmpty(virtualization) {
            components.append(contentsOf: ["--virtualization", virtualization])
        }

        if useRosetta {
            components.append("--rosetta")
        }

        if let network = Self.trimmedNonEmpty(network) {
            components.append(contentsOf: ["--network", network])
        }

        if let workingDirectory = Self.trimmedNonEmpty(workingDirectory) {
            components.append(contentsOf: ["--workdir", workingDirectory])
        }

        for key in environment.keys.sorted(by: <) {
            components.append(contentsOf: ["--env", "\(key)=<redacted>"])
        }

        for environmentFile in Self.trimmedLineValues(environmentFiles) {
            components.append(contentsOf: ["--env-file", environmentFile])
        }

        for publishedPort in Self.trimmedLineValues(publishedPorts) {
            components.append(contentsOf: ["--publish", publishedPort])
        }

        for volume in Self.trimmedLineValues(volumeMounts) {
            components.append(contentsOf: ["--volume", volume])
        }

        for mount in Self.trimmedLineValues(mounts) {
            components.append(contentsOf: ["--mount", mount])
        }

        if let user = Self.trimmedNonEmpty(user) {
            components.append(contentsOf: ["--user", user])
        }

        if let uid = Self.trimmedNonEmpty(uid) {
            components.append(contentsOf: ["--uid", uid])
        }

        if let gid = Self.trimmedNonEmpty(gid) {
            components.append(contentsOf: ["--gid", gid])
        }

        if enableDefaultSSHForwarding {
            components.append("--ssh")
        }

        for sshAgent in Self.trimmedLineValues(sshAgents) {
            components.append(contentsOf: ["--ssh", sshAgent])
        }

        components.append("--")
        components.append(imageReference)
        components.append(contentsOf: commandArguments)

        let command = components.joined(separator: " ")
        if operation == .createAndStart {
            return "\(command) && container start <created-id>"
        }
        return command
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedLineValues(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private enum PlatformSelectionMode: String, CaseIterable, Identifiable {
    case automatic
    case platform
    case architectureAndOS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .platform:
            "Platform"
        case .architectureAndOS:
            "Arch + OS"
        }
    }
}

private struct ContainerCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    let suggestedImageReference: String
    let availableImageReferences: [String]
    let availableNetworkNames: [String]
    let onCreate: (ContainerCreateViewRequest) -> Void

    @State private var selectedImageReference = ""
    @State private var customImageReference = ""
    @State private var useCustomImageReference = false
    @State private var operation: ContainerLaunchOperation = .createAndStart
    @State private var name = ""
    @State private var commandText = ""
    @State private var selectedNetworkName = ""
    @State private var customNetworkName = ""
    @State private var workingDirectory = ""
    @State private var setsCPULimit = false
    @State private var cpuCount = 2
    @State private var setsMemoryLimit = false
    @State private var memoryMB = 512
    @State private var initializeContainer = false
    @State private var initImageReference = ""
    @State private var readOnlyRootFilesystem = false
    @State private var removeWhenStopped = false
    @State private var platformSelectionMode: PlatformSelectionMode = .automatic
    @State private var platform = ""
    @State private var architecture = ""
    @State private var operatingSystem = ""
    @State private var virtualization = ""
    @State private var useRosetta = false
    @State private var enableDefaultSSHForwarding = false
    @State private var sshAgentsText = ""
    @State private var environmentText = ""
    @State private var environmentFilesText = ""
    @State private var portsText = ""
    @State private var volumesText = ""
    @State private var mountsText = ""
    @State private var userText = ""
    @State private var uidText = ""
    @State private var gidText = ""
    @State private var showsAdvancedOptions = false
    @State private var validationError: String?
    @State private var isLoadingLookupChoices = false
    @State private var userChangedCustomImageMode = false
    @State private var runtimeImageReferences: [String] = []
    @State private var runtimeNetworkNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(operation == .runDetached ? "Run Container" : "Create Container")
                .font(.title3.weight(.semibold))

            Form {
                Section("Container") {
                    if imageChoices.isEmpty {
                        if isLoadingLookupChoices {
                            LabeledContent("Image") {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else {
                            TextField("Image reference", text: $customImageReference)
                                .font(.system(.body, design: .monospaced))
                        }
                    } else {
                        Picker("Image", selection: $selectedImageReference) {
                            Text("Select image")
                                .tag("")
                            ForEach(imageChoices, id: \.self) { reference in
                                Text(reference)
                                    .tag(reference)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle(
                            "Use custom image reference",
                            isOn: Binding(
                                get: { useCustomImageReference },
                                set: { value in
                                    userChangedCustomImageMode = true
                                    useCustomImageReference = value
                                }
                            )
                        )

                        if useCustomImageReference {
                            TextField("Custom image reference", text: $customImageReference)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    TextField("Container name (optional)", text: $name)
                        .font(.system(.body, design: .monospaced))

                    Picker("Action", selection: $operation) {
                        ForEach(ContainerLaunchOperation.allCases) { selectedOperation in
                            Text(selectedOperation.title)
                                .tag(selectedOperation)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(operation.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Runtime") {
                    Picker("Network", selection: $selectedNetworkName) {
                        Text("Default")
                            .tag("")
                        ForEach(networkChoices, id: \.self) { network in
                            Text(network)
                                .tag(network)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Set CPU limit", isOn: $setsCPULimit)

                    if setsCPULimit {
                        Stepper(value: $cpuCount, in: 1 ... 16) {
                            HStack {
                                Text("CPUs")
                                Spacer()
                                Text("\(cpuCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle("Set memory limit", isOn: $setsMemoryLimit)

                    if setsMemoryLimit {
                        Stepper(value: $memoryMB, in: 256 ... 32768, step: 256) {
                            HStack {
                                Text("Memory")
                                Spacer()
                                Text(Self.memoryLabel(for: memoryMB))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle("Enable init process (--init)", isOn: $initializeContainer)

                    TextField("Init image override (--init-image)", text: $initImageReference)
                        .font(.system(.body, design: .monospaced))

                    Toggle("Read-only root filesystem (--read-only)", isOn: $readOnlyRootFilesystem)
                    Toggle("Remove container when it exits (--rm)", isOn: $removeWhenStopped)
                }

                Section("Platform & Virtualization") {
                    Picker("Selection mode", selection: $platformSelectionMode) {
                        ForEach(PlatformSelectionMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch platformSelectionMode {
                    case .automatic:
                        Text("Use engine defaults for platform, architecture, and OS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .platform:
                        TextField("Platform (--platform)", text: $platform)
                            .font(.system(.body, design: .monospaced))
                    case .architectureAndOS:
                        TextField("Architecture (--arch)", text: $architecture)
                            .font(.system(.body, design: .monospaced))
                        TextField("Operating system (--os)", text: $operatingSystem)
                            .font(.system(.body, design: .monospaced))
                    }

                    TextField("Virtualization mode (--virtualization)", text: $virtualization)
                        .font(.system(.body, design: .monospaced))
                    Toggle("Enable Rosetta (--rosetta)", isOn: $useRosetta)
                    Toggle("Forward default SSH agent (--ssh)", isOn: $enableDefaultSSHForwarding)
                }

                Section {
                    DisclosureGroup("Advanced Options", isExpanded: $showsAdvancedOptions) {
                        TextField("Command arguments (optional)", text: $commandText)
                            .font(.system(.body, design: .monospaced))
                            .padding(.top, 6)

                        TextField("Custom network override (optional)", text: $customNetworkName)
                            .font(.system(.body, design: .monospaced))

                        TextField("Working directory in container (optional)", text: $workingDirectory)
                            .font(.system(.body, design: .monospaced))

                        HStack {
                            TextField("User (--user)", text: $userText)
                                .font(.system(.body, design: .monospaced))
                            TextField("UID (--uid)", text: $uidText)
                                .font(.system(.body, design: .monospaced))
                            TextField("GID (--gid)", text: $gidText)
                                .font(.system(.body, design: .monospaced))
                        }

                        multilineInputField(
                            title: "Environment",
                            text: $environmentText,
                            height: 84,
                            help: "One key=value entry per line. Example: NODE_ENV=production"
                        )

                        multilineInputField(
                            title: "Environment Files",
                            text: $environmentFilesText,
                            height: 64,
                            help: "One file path per line. Example: ./app.env"
                        )

                        multilineInputField(
                            title: "Port Publishing",
                            text: $portsText,
                            height: 72,
                            help: "One mapping per line. Example: 8080:80 or 127.0.0.1:8080:80/tcp"
                        )

                        multilineInputField(
                            title: "Volume Mounts",
                            text: $volumesText,
                            height: 72,
                            help: "One mapping per line. Example: /host/path:/container/path"
                        )

                        multilineInputField(
                            title: "Mounts",
                            text: $mountsText,
                            height: 72,
                            help: "One --mount entry per line. Example: type=bind,source=/host,target=/app"
                        )

                        multilineInputField(
                            title: "SSH Agents",
                            text: $sshAgentsText,
                            height: 64,
                            help:
                                "One SSH socket or key spec per line. Example: default=/run/host-services/ssh-auth.sock"
                        )
                    }
                }
            }
            .formStyle(.grouped)

            GroupBox("Command Preview") {
                ScrollView {
                    Text(commandPreviewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(minHeight: 64, maxHeight: 120)
            }

            if let validationError {
                Text(validationError)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(operation.primaryActionTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreateDisabled)
            }
        }
        .padding(20)
        .frame(width: 760)
        .task {
            applyInitialSelections()
            await loadLookupChoices()
            applyInitialSelections()
        }
        .onChange(of: imageChoices) { _, _ in
            applyInitialSelections()
        }
        .onChange(of: networkChoices) { _, _ in
            applyInitialSelections()
        }
    }

    private var imageChoices: [String] {
        Self.normalizedUniqueValues(availableImageReferences + runtimeImageReferences)
    }

    private var networkChoices: [String] {
        Self.normalizedUniqueValues(availableNetworkNames + runtimeNetworkNames)
    }

    private var resolvedImageReference: String {
        if imageChoices.isEmpty || useCustomImageReference {
            return customImageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedImageReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCreateDisabled: Bool {
        resolvedImageReference.isEmpty
    }

    private var resolvedPlatform: String? {
        guard platformSelectionMode == .platform else { return nil }
        return Self.normalizedOptionalText(platform)
    }

    private var resolvedArchitecture: String? {
        guard platformSelectionMode == .architectureAndOS else { return nil }
        return Self.normalizedOptionalText(architecture)
    }

    private var resolvedOperatingSystem: String? {
        guard platformSelectionMode == .architectureAndOS else { return nil }
        return Self.normalizedOptionalText(operatingSystem)
    }

    private var commandPreviewText: String {
        do {
            return try buildRequest(requireImage: false).commandDescription
        } catch {
            return "Preview unavailable: \(error.localizedDescription)"
        }
    }

    private func applyInitialSelections() {
        if customImageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customImageReference = suggestedImageReference
        }

        if imageChoices.isEmpty {
            if !userChangedCustomImageMode {
                useCustomImageReference = true
            }
            return
        }

        if !userChangedCustomImageMode {
            useCustomImageReference = false
        }

        if selectedImageReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !imageChoices.contains(selectedImageReference)
        {
            if imageChoices.contains(suggestedImageReference) {
                selectedImageReference = suggestedImageReference
            } else if let first = imageChoices.first {
                selectedImageReference = first
            }
        }
    }

    private func loadLookupChoices() async {
        isLoadingLookupChoices = true
        async let imagesResult = try? containerCLIAdapter.listImages()
        async let networksResult = try? containerCLIAdapter.listNetworks()

        let images = await imagesResult
        let networks = await networksResult

        if case .parsed(let value, _) = images {
            runtimeImageReferences = value.map(\.reference)
        }

        if case .parsed(let value, _) = networks {
            runtimeNetworkNames = value.map(\.name)
        }

        isLoadingLookupChoices = false
    }

    @ViewBuilder
    private func multilineInputField(
        title: String,
        text: Binding<String>,
        height: CGFloat,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))

            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                }

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        do {
            let request = try buildRequest(requireImage: true)
            onCreate(request)
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func buildRequest(requireImage: Bool) throws -> ContainerCreateViewRequest {
        let image = resolvedImageReference
        if requireImage && image.isEmpty {
            throw ContainerCreateSheetError.imageReferenceRequired
        }

        return ContainerCreateViewRequest(
            operation: operation,
            imageReference: image.isEmpty ? "<image-reference>" : image,
            name: Self.normalizedOptionalText(name),
            commandArguments: try Self.parseArguments(commandText),
            environment: try Self.parseKeyValueText(environmentText),
            environmentFiles: Self.parseLineList(environmentFilesText),
            publishedPorts: Self.parseLineList(portsText),
            volumeMounts: Self.parseLineList(volumesText),
            mounts: Self.parseLineList(mountsText),
            network: Self.normalizedOptionalText(customNetworkName)
                ?? Self.normalizedOptionalText(selectedNetworkName),
            workingDirectory: Self.normalizedOptionalText(workingDirectory),
            cpuCount: setsCPULimit ? cpuCount : nil,
            memory: setsMemoryLimit ? "\(memoryMB)MB" : nil,
            initializeContainer: initializeContainer,
            initImageReference: Self.normalizedOptionalText(initImageReference),
            readOnlyRootFilesystem: readOnlyRootFilesystem,
            removeWhenStopped: removeWhenStopped,
            platform: resolvedPlatform,
            architecture: resolvedArchitecture,
            operatingSystem: resolvedOperatingSystem,
            virtualization: Self.normalizedOptionalText(virtualization),
            useRosetta: useRosetta,
            enableDefaultSSHForwarding: enableDefaultSSHForwarding,
            sshAgents: Self.parseLineList(sshAgentsText),
            user: Self.normalizedOptionalText(userText),
            uid: Self.normalizedOptionalText(uidText),
            gid: Self.normalizedOptionalText(gidText)
        )
    }

    private static func parseArguments(_ value: String) throws -> [String] {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }

        var arguments: [String] = []
        var current = ""
        var inSingleQuotes = false
        var inDoubleQuotes = false
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if inSingleQuotes {
                if character == "'" {
                    inSingleQuotes = false
                } else {
                    current.append(character)
                }
                continue
            }

            if inDoubleQuotes {
                if character == "\"" {
                    inDoubleQuotes = false
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" {
                inSingleQuotes = true
                continue
            }

            if character == "\"" {
                inDoubleQuotes = true
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if escaping || inSingleQuotes || inDoubleQuotes {
            throw ContainerCreateSheetError.invalidCommandArguments
        }

        if !current.isEmpty {
            arguments.append(current)
        }

        return arguments
    }

    private static func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func memoryLabel(for megabytes: Int) -> String {
        if megabytes >= 1024, megabytes % 1024 == 0 {
            return "\(megabytes / 1024) GB"
        }
        return "\(megabytes) MB"
    }

    private static func normalizedUniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result.sorted()
    }

    private static func parseLineList(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseKeyValueText(_ text: String) throws -> [String: String] {
        var output: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw ContainerCreateSheetError.invalidKeyValue(trimmed)
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                throw ContainerCreateSheetError.invalidKeyValue(trimmed)
            }
            output[key] = value
        }
        return output
    }
}

private enum ContainerCreateSheetError: LocalizedError {
    case imageReferenceRequired
    case invalidKeyValue(String)
    case invalidCommandArguments

    var errorDescription: String? {
        switch self {
        case .imageReferenceRequired:
            "Image reference is required."
        case .invalidKeyValue(let entry):
            "Invalid environment entry: \(entry)"
        case .invalidCommandArguments:
            "Invalid command arguments. Check unmatched quotes or trailing escape characters."
        }
    }
}
