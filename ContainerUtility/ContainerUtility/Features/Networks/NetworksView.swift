import AppKit
import SwiftUI

struct NetworksView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<NetworkRow>] = [KeyPathComparator(\.name, order: .forward)]
    @State private var selectedNetworkNames = Set<String>()
    @State private var networks: [NetworkListItem] = []
    @State private var relationshipScan = ResourceRelationshipScan.empty
    @State private var decodeWarnings: [String] = []
    @State private var rawFallbackOutput: String?
    @State private var inspectSnapshot: NetworkInspectSnapshot?
    @State private var inspectError: String?
    @State private var isLoading = false
    @State private var isPresentingCreateSheet = false
    @State private var isPresentingHostDNSSheet = false
    @State private var lastError: AppError?
    @State private var confirmationAction: NetworkConfirmationAction?
    @State private var listTask: Task<Void, Never>?
    @State private var inspectTask: Task<Void, Never>?
    @State private var showInspector = true
    @State private var hasCompletedInitialLoad = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                listHeaderBar

                Divider()

                networkTableContent

                if showsFooter {
                    footerBar
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
            .background(.background)

            if showInspector {
                networkInspectorPane
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                primaryActionButtons(iconOnly: true)
            }

            ToolbarItem(placement: .navigation) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingHostDNSSheet = true
                } label: {
                    Label("Host DNS", systemImage: "globe")
                }
                .help("Manage host DNS entries")
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings (⌘,)")
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
        .overlay {
            if isLoading && networks.isEmpty {
                loadingOverlay
            }
        }
        .sheet(isPresented: $isPresentingCreateSheet) {
            NetworkCreateSheet { request in
                enqueueNetworkAction(
                    title: "Create network \(request.name)",
                    summary: "Created network \(request.name).",
                    commandDescription: buildCreateNetworkCommand(request)
                ) {
                    try await containerCLIAdapter.createNetwork(
                        name: request.name,
                        ipv4Subnet: request.ipv4Subnet,
                        ipv6Subnet: request.ipv6Subnet,
                        labels: request.labels,
                        isInternal: request.isInternal
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentingHostDNSSheet) {
            HostDNSManagementSheet()
        }
        .alert("Delete Network?", isPresented: confirmationPresented) {
            if let action = confirmationAction {
                switch action {
                case .delete(let names):
                    Button("Cancel", role: .cancel) {}
                    Button("Delete \(names.count == 1 ? "Network" : "Networks")", role: .destructive) {
                        performDelete(names: names)
                    }
                }
            }
        } message: {
            if let action = confirmationAction {
                Text(confirmationMessage(for: action))
            }
        }
        .task {
            if networks.isEmpty, !appModel.cachedNetworkItems.isEmpty {
                networks = appModel.cachedNetworkItems
                hasCompletedInitialLoad = true
            }
            reloadNetworks()
        }
        .onChange(of: appModel.refreshRevision(for: .networks)) { _, _ in
            guard !isLoading else { return }
            reloadNetworks()
        }
        .onChange(of: selectedNetworkName) { _, newValue in
            guard let newValue else {
                inspectTask?.cancel()
                inspectSnapshot = nil
                inspectError = nil
                return
            }
            if !showInspector {
                showInspector = true
            }
            loadInspect(name: newValue)
        }
        .onDisappear {
            listTask?.cancel()
            inspectTask?.cancel()
        }
        .navigationTitle("")
    }

    private var networkTableContent: some View {
        Group {
            if filteredRows.isEmpty && hasCompletedInitialLoad && !isLoading {
                emptyStateView
            } else {
                networkTable
            }
        }
    }

    private var networkInspectorPane: some View {
        ResourceInspectorPane(showsHeader: false) {
            if selectedNetworkName != nil {
                HStack(spacing: 8) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        if let selectedNetworkName {
                            loadInspect(name: selectedNetworkName)
                        }
                    }
                    .disabled(isBusy)
                    .labelStyle(.iconOnly)

                    Button("Copy JSON", systemImage: "doc.on.doc") {
                        copyJSON(inspectSnapshot?.rawJSON)
                    }
                    .disabled(inspectSnapshot == nil)
                    .labelStyle(.iconOnly)
                }
            }
        } content: {
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorContent: some View {
        Group {
            if let selectedNetworkName {
                networkDetailContent(name: selectedNetworkName)
            } else {
                emptyInspectorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyInspectorView: some View {
        ResourceInspectorStateView(
            descriptor: ResourceInspectorStateDescriptor(
                title: "No Network Selected",
                message: "Select a network to inspect addresses, labels, and attached containers.",
                systemImage: "network"
            )
        )
    }

    private var listHeaderBar: some View {
        HStack {
            Text(listPanelSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !selectedNetworkNames.isEmpty {
                Text("\(selectedNetworkNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func primaryActionButtons(iconOnly: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                reloadNetworks()
            } label: {
                toolbarButtonLabel("Refresh", systemImage: "arrow.clockwise", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .help("Refresh network list (\u{2318}R)")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                isPresentingCreateSheet = true
            } label: {
                toolbarButtonLabel("Create Network", systemImage: "plus", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .keyboardShortcut("n", modifiers: .command)
            .help("Create network")

            Button {
                initiateDelete()
            } label: {
                toolbarButtonLabel("Delete Selected", systemImage: "trash", iconOnly: iconOnly)
            }
            .disabled(!canDeleteSelected)
            .help("Delete selected networks")
            .keyboardShortcut(.delete, modifiers: .command)

            if isBusy {
                Button {
                    cancelRunningTask()
                } label: {
                    toolbarButtonLabel("Cancel", systemImage: "xmark", iconOnly: true)
                }
                .keyboardShortcut(.cancelAction)
                .help("Cancel running operation")
            }
        }
    }

    @ViewBuilder
    private func toolbarButtonLabel(_ title: String, systemImage: String, iconOnly: Bool) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var canDeleteSelected: Bool {
        !isBusy && !selectedNetworks.isEmpty && selectedProtectedNetworks.isEmpty
    }

    private func initiateDelete() {
        let names = selectedNetworks.map(\.name)
        confirmationAction = .delete(names: names)
    }

    private func performDelete(names: [String]) {
        enqueueNetworkAction(
            title: "Delete \(names.count) network(s)",
            summary: "Deleted \(names.count) network(s).",
            commandDescription: "container network delete \(names.joined(separator: " "))"
        ) {
            try await containerCLIAdapter.deleteNetworks(names: names)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ResourceEmptyStateSurface(backgroundOpacity: 0.08) {
            if searchText.isEmpty, let lastError {
                ResourceInspectorStateView(
                    descriptor: resourceListFailureDescriptor(
                        resourceName: "networks",
                        error: lastError.localizedDescription,
                        systemHealth: appModel.latestSystemHealthSnapshot
                    )
                )
            } else {
                ContentUnavailableView {
                    Label(emptyStateTitle, systemImage: "network")
                } description: {
                    Text(emptyStateDetail)
                }
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.85)

            VStack(spacing: 16) {
                ProgressView("Loading networks...")
                    .controlSize(.large)
            }
            .padding(32)
            .background(.ultraThickMaterial)
            .cornerRadius(12)
        }
        .ignoresSafeArea()
    }

    private var networkTable: some View {
        Table(of: NetworkRow.self, selection: $selectedNetworkNames, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .fontWeight(.medium)
                        if row.isProtected {
                            Text("Built-in")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(row.pluginDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 220, ideal: 280)

            TableColumn("State", value: \.stateSortKey) { row in
                Text(row.stateDisplay)
                    .foregroundStyle(row.stateColor)
            }
            .width(min: 100, ideal: 120)

            TableColumn("IPv4 Subnet", value: \.ipv4SubnetSortKey) { row in
                Text(row.ipv4SubnetDisplay)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 180, ideal: 220)

            TableColumn("Mode", value: \.modeSortKey) { row in
                Text(row.modeDisplay)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Containers", value: \.attachedCount) { row in
                Text(String(row.attachedCount))
            }
            .width(min: 90, ideal: 110)
        } rows: {
            ForEach(filteredRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button {
                            selectedNetworkNames = [row.name]
                            loadInspect(name: row.name)
                        } label: {
                            Label("Inspect", systemImage: "eye")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.name, forType: .string)
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }

                        if !row.isProtected {
                            Divider()

                            Button(role: .destructive) {
                                selectedNetworkNames = [row.name]
                                confirmationAction = .delete(names: [row.name])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerBar: some View {
        ResourceListFeedbackBar(
            activity: activeSectionActivity,
            warningMessages: decodeWarnings,
            errorMessage: lastError?.localizedDescription
        )
    }

    @ViewBuilder
    private func networkDetailContent(name: String) -> some View {
        if let inspectSnapshot {
            networkDetailPane(snapshot: inspectSnapshot, name: name)
        } else if let inspectError {
            ResourceInspectorStateView(
                descriptor: resourceInspectorFailureDescriptor(
                    resourceName: "network",
                    error: inspectError,
                    systemHealth: appModel.latestSystemHealthSnapshot
                )
            )
        } else {
            ResourceInspectorLoadingView()
        }
    }

    private func networkDetailPane(snapshot: NetworkInspectSnapshot, name: String) -> some View {
        let attachedContainers = networkUsages(for: name)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ResourcePanel(
                    title: "Summary",
                    subtitle: "Addressing, mode, plugin, and creation metadata for the selected network."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ResourceFactRow(title: "Name", value: snapshot.name)
                        ResourceFactRow(title: "State", value: snapshot.state?.capitalized ?? "Unknown")
                        ResourceFactRow(title: "Mode", value: formatMode(snapshot.mode))
                        ResourceFactRow(title: "IPv4 Subnet", value: snapshot.ipv4Subnet ?? "Unknown")
                        ResourceFactRow(title: "IPv6 Subnet", value: snapshot.ipv6Subnet ?? "Unknown")
                        ResourceFactRow(title: "Gateway", value: snapshot.ipv4Gateway ?? "Unknown")
                        ResourceFactRow(title: "Plugin", value: pluginDescription(for: snapshot))
                        ResourceFactRow(title: "Created", value: formatDate(snapshot.createdAt))
                    }
                }

                relationshipPanel(attachedContainers: attachedContainers)
                labelsPanel(snapshot: snapshot)

                ResourcePanel(
                    title: "Raw Inspect JSON",
                    subtitle: "Low-level network metadata returned by the runtime."
                ) {
                    ResourceMonospacedOutput(
                        text: snapshot.rawJSON,
                        placeholder: "Inspect output not loaded yet."
                    )
                    .frame(minHeight: 220)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func relationshipPanel(attachedContainers: [NetworkUsageRow]) -> some View {
        ResourcePanel(
            title: "Container Relationships",
            subtitle: "Derived from container configuration."
        ) {
            if attachedContainers.isEmpty {
                Text("No container relationship hints were found for this network.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(attachedContainers) { usage in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(usage.containerName)
                                    .fontWeight(.medium)
                                Text(usage.containerID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(usage.containerState.capitalized)
                                .foregroundStyle(usage.stateColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func labelsPanel(snapshot: NetworkInspectSnapshot) -> some View {
        ResourcePanel(
            title: "Labels",
            subtitle: "Applied network metadata."
        ) {
            ResourceMonospacedOutput(
                text: formatMetadata(snapshot.labels),
                placeholder: "None"
            )
            .frame(minHeight: 120)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var isBusy: Bool {
        isLoading || appModel.hasActiveActivity(for: .networks)
    }

    private var filteredRows: [NetworkRow] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = networks.map { NetworkRow(item: $0, attachedCount: networkUsages(for: $0.name).count) }
        if !search.isEmpty {
            rows = rows.filter { $0.searchBlob.contains(search) }
        }
        rows.sort(using: sortOrder)
        return rows
    }

    private var selectedNetworkName: String? {
        guard selectedNetworkNames.count == 1 else { return nil }
        return selectedNetworkNames.first
    }

    private var selectedNetworks: [NetworkListItem] {
        networks.filter { selectedNetworkNames.contains($0.name) }
    }

    private var selectedProtectedNetworks: [NetworkListItem] {
        selectedNetworks.filter(\.isBuiltin)
    }

    private var listPanelSubtitle: String {
        if isLoading && networks.isEmpty {
            return "Loading..."
        }

        let count = filteredRows.count
        let total = networks.count
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return count == 1 ? "1 network" : "\(count) networks"
        }
        return "\(count) of \(total)"
    }

    private var emptyStateTitle: String {
        searchText.isEmpty ? "No Networks" : "No Matching Networks"
    }

    private var emptyStateDetail: String {
        searchText.isEmpty
            ? "Create a network or refresh the runtime state."
            : "Adjust the search text to broaden the results."
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

    private func reloadNetworks() {
        listTask?.cancel()
        let shouldShowLoading = networks.isEmpty
        if shouldShowLoading {
            isLoading = true
        }
        lastError = nil

        listTask = Task {
            do {
                async let listResult = containerCLIAdapter.listNetworks()
                async let relationshipScan = containerCLIAdapter.scanResourceRelationships()
                let result = try await listResult
                let scan = await relationshipScan

                await MainActor.run {
                    applyListResult(result, relationshipScan: scan)
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    if shouldShowLoading {
                        networks = []
                        relationshipScan = .empty
                        appModel.updateNetworks(from: [], relationships: [])
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
                        networks = []
                        relationshipScan = .empty
                        appModel.updateNetworks(from: [], relationships: [])
                        decodeWarnings = []
                        rawFallbackOutput = nil
                    }
                    lastError = .commandLaunchFailed(
                        command: "container network list --format json",
                        reason: error.localizedDescription
                    )
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            }
        }
    }

    private func applyListResult(
        _ result: NonCriticalDecodeResult<[NetworkListItem]>,
        relationshipScan scan: ResourceRelationshipScan
    ) {
        relationshipScan = scan
        switch result {
        case .parsed(let value, let diagnostics):
            networks = value
            appModel.cachedNetworkItems = value
            decodeWarnings = diagnostics.warnings + scan.warnings
            rawFallbackOutput = nil
            appModel.updateNetworks(from: value, relationships: scan.hints)
        case .raw(let output, let diagnostics):
            decodeWarnings = diagnostics.warnings + scan.warnings
            rawFallbackOutput = output
        }

        let validNames = Set(networks.map(\.name))
        selectedNetworkNames = selectedNetworkNames.intersection(validNames)
        if selectedNetworkName == nil {
            inspectSnapshot = nil
            inspectError = nil
        }
    }

    private func loadInspect(name: String) {
        inspectTask?.cancel()
        inspectSnapshot = nil
        inspectError = nil
        let requestedName = name

        inspectTask = Task {
            do {
                let snapshot = try await containerCLIAdapter.inspectNetwork(name: requestedName)
                await MainActor.run {
                    guard selectedNetworkName == requestedName else { return }
                    inspectSnapshot = snapshot
                    inspectTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    guard selectedNetworkName == requestedName else { return }
                    inspectSnapshot = nil
                    inspectError = error.localizedDescription
                    inspectTask = nil
                }
            } catch {
                await MainActor.run {
                    guard selectedNetworkName == requestedName else { return }
                    inspectSnapshot = nil
                    inspectError = error.localizedDescription
                    inspectTask = nil
                }
            }
        }
    }

    private var latestSectionActivity: ActivityRecord? {
        appModel.latestActivity(for: .networks)
    }

    private var activeSectionActivity: ActivityRecord? {
        guard let latestSectionActivity, latestSectionActivity.status.isActive else {
            return nil
        }
        return latestSectionActivity
    }

    private var showsFooter: Bool {
        activeSectionActivity != nil || !decodeWarnings.isEmpty || lastError != nil
    }

    private func enqueueNetworkAction(
        title: String,
        summary: String,
        commandDescription: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        lastError = nil
        confirmationAction = nil
        let completionSummary = summary

        _ = appModel.enqueueActivity(
            title: title,
            section: .networks,
            kind: .network,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await operation()
                await refreshNetworkSummary()
                return ActivityOperationOutcome(summary: completionSummary)
            } catch let error as AppError {
                await refreshNetworkSummary()
                throw error
            } catch {
                await refreshNetworkSummary()
                throw AppError.commandLaunchFailed(command: commandDescription, reason: error.localizedDescription)
            }
        }
    }

    private func refreshNetworkSummary() async {
        async let listResult = try? containerCLIAdapter.listNetworks()
        async let relationshipScan = containerCLIAdapter.scanResourceRelationships()
        let result = await listResult
        let scan = await relationshipScan

        if let result {
            if case .parsed(let value, _) = result {
                appModel.cachedNetworkItems = value
            }
            appModel.updateNetworkSummary(from: result, relationships: scan.hints)
        }
        appModel.bumpRefreshRevision(for: .networks)
    }

    private func cancelRunningTask() {
        if isLoading {
            listTask?.cancel()
            isLoading = false
            listTask = nil
        } else {
            appModel.cancelLatestActiveActivity(in: .networks)
        }
    }

    @ViewBuilder
    private func activityFooter(_ activity: ActivityRecord) -> some View {
        switch activity.status {
        case .queued:
            Text("Queued: \(activity.title)")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView("Running \(activity.title)...")
        case .succeeded:
            if let summary = activity.summary {
                Text(summary)
                    .foregroundStyle(.secondary)
            }
        case .failed, .canceled:
            Text(activity.errorMessage ?? activity.summary ?? "\(activity.title) did not complete.")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func buildCreateNetworkCommand(_ request: NetworkCreateRequest) -> String {
        var components = ["container", "network", "create", request.name]
        if let ipv4Subnet = request.ipv4Subnet, !ipv4Subnet.isEmpty {
            components.append(contentsOf: ["--subnet", ipv4Subnet])
        }
        if let ipv6Subnet = request.ipv6Subnet, !ipv6Subnet.isEmpty {
            components.append(contentsOf: ["--subnet-v6", ipv6Subnet])
        }
        if request.isInternal {
            components.append("--internal")
        }
        for (key, value) in request.labels.sorted(by: { $0.key < $1.key }) {
            components.append(contentsOf: ["--label", "\(key)=\(value)"])
        }
        return components.joined(separator: " ")
    }

    private func networkUsages(for name: String) -> [NetworkUsageRow] {
        relationshipScan.hints
            .filter { $0.networks.contains(name) }
            .map {
                NetworkUsageRow(
                    containerID: $0.containerID,
                    containerName: $0.containerName,
                    containerState: $0.containerState
                )
            }
            .sorted { $0.containerName.localizedStandardCompare($1.containerName) == .orderedAscending }
    }

    private func pluginDescription(for snapshot: NetworkInspectSnapshot) -> String {
        let description = [snapshot.plugin, snapshot.pluginVariant]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        return description.isEmpty ? "Unknown" : description
    }

    private func confirmationMessage(for action: NetworkConfirmationAction) -> String {
        switch action {
        case .delete(let names):
            if names.contains("default") {
                return "Built-in networks should not be deleted."
            }
            return
                "This removes the selected network definition. Containers still referencing it may fail to start until their configuration is updated."
        }
    }

    private func formatMetadata(_ values: [String: String]) -> String {
        guard !values.isEmpty else { return "None" }
        return
            values
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return Self.dateFormatter.string(from: date)
    }

    private func formatMode(_ mode: String?) -> String {
        guard let mode else { return "Unknown" }
        return mode.uppercased() == "NAT" ? "NAT" : mode.capitalized
    }

    private func copyJSON(_ rawJSON: String?) {
        guard let rawJSON else { return }
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawJSON, forType: .string)
        #endif
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum NetworkConfirmationAction: Equatable {
    case delete(names: [String])
}

private struct NetworkRow: Identifiable {
    let item: NetworkListItem
    let attachedCount: Int

    var id: String { item.id }
    var name: String { item.name }
    var stateDisplay: String { item.state?.capitalized ?? "Unknown" }
    var stateSortKey: String { item.state ?? "" }
    var modeDisplay: String {
        guard let mode = item.mode else { return "Unknown" }
        return mode.uppercased() == "NAT" ? "NAT" : mode.capitalized
    }
    var modeSortKey: String { item.mode ?? "" }
    var ipv4SubnetDisplay: String { item.ipv4Subnet ?? "Unknown" }
    var ipv4SubnetSortKey: String { item.ipv4Subnet ?? "" }
    var pluginDisplay: String {
        let description = [item.plugin, item.pluginVariant]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        return description.isEmpty ? (item.mode ?? "Unknown") : description
    }
    var isProtected: Bool { item.isBuiltin }
    var stateColor: Color {
        switch item.state?.lowercased() {
        case "running":
            .green
        case "stopped":
            .secondary
        default:
            .primary
        }
    }
    var searchBlob: String {
        let labels = item.labels
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let parts = [
            item.name,
            item.state ?? "",
            item.mode ?? "",
            item.ipv4Subnet ?? "",
            item.ipv6Subnet ?? "",
            item.ipv4Gateway ?? "",
            item.plugin ?? "",
            item.pluginVariant ?? "",
            labels,
        ]
        return parts.joined(separator: " ").lowercased()
    }
}

private struct NetworkUsageRow: Identifiable {
    let containerID: String
    let containerName: String
    let containerState: String

    var id: String { containerID }
    var stateColor: Color {
        let normalized = containerState.lowercased()
        if normalized.contains("running") {
            return .green
        }
        if normalized.contains("stopped") || normalized.contains("exited") {
            return .secondary
        }
        return .primary
    }
}

private struct NetworkCreateRequest {
    let name: String
    let ipv4Subnet: String?
    let ipv6Subnet: String?
    let labels: [String: String]
    let isInternal: Bool
}

private enum HostDNSAction {
    case list
    case create
    case delete

    var statusText: String {
        switch self {
        case .list:
            return "Listing DNS entries..."
        case .create:
            return "Creating DNS entry..."
        case .delete:
            return "Deleting DNS entry..."
        }
    }
}

private struct HostDNSManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var dnsEntry = ""
    @State private var localhostIPv4 = ""
    @State private var listedEntries: [String] = []
    @State private var lastCommand = ""
    @State private var dnsOutput = ""
    @State private var actionInFlight: HostDNSAction?
    @State private var dnsTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Host DNS")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("List, create, and delete DNS entries. Use --localhost only when needed.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("DNS entry (for create/delete)", text: $dnsEntry)
                    .font(.system(.body, design: .monospaced))

                TextField("Localhost IPv4 (optional)", text: $localhostIPv4)
                    .font(.system(.body, design: .monospaced))

                if let localhostIPv4ValidationError {
                    Text(localhostIPv4ValidationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Button("List") {
                        listSystemDNS()
                    }
                    .disabled(actionInFlight != nil)

                    Button("Create") {
                        createSystemDNS()
                    }
                    .disabled(!canMutateDNSEntries)

                    Button("Delete", role: .destructive) {
                        deleteSystemDNS()
                    }
                    .disabled(!canMutateDNSEntries)

                    if let actionInFlight {
                        ProgressView(actionInFlight.statusText)
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Entries")
                        .foregroundStyle(.secondary)
                    if listedEntries.isEmpty {
                        Text("Run List to load DNS entries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(listedEntries, id: \.self) { entry in
                                    Button {
                                        dnsEntry = entry
                                    } label: {
                                        Text(entry)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(minHeight: 96, maxHeight: 140)
                        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .foregroundStyle(.secondary)
                    Text(lastCommand.isEmpty ? "No command run yet." : lastCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Output")
                        .foregroundStyle(.secondary)
                    ResourceMonospacedOutput(
                        text: dnsOutput,
                        placeholder: "Run a DNS action to view output."
                    )
                    .frame(minHeight: 220)
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560, height: 700)
        .task {
            if dnsOutput.isEmpty {
                listSystemDNS()
            }
        }
        .onDisappear {
            dnsTask?.cancel()
            dnsTask = nil
        }
    }

    private var trimmedDNSEntry: String {
        dnsEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDNSLocalhostIPv4: String {
        localhostIPv4.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localhostIPv4ValidationError: String? {
        guard !trimmedDNSLocalhostIPv4.isEmpty else {
            return nil
        }
        guard Self.isValidIPv4(trimmedDNSLocalhostIPv4) else {
            return "Localhost IPv4 must be a valid IPv4 address."
        }
        return nil
    }

    private var canMutateDNSEntries: Bool {
        !trimmedDNSEntry.isEmpty && localhostIPv4ValidationError == nil && actionInFlight == nil
    }

    private func listSystemDNS() {
        runDNSAction(
            action: .list,
            commandDescription: "container system dns list",
            successPrefix: nil
        ) {
            try await containerCLIAdapter.listSystemDNS()
        }
    }

    private func createSystemDNS() {
        guard !trimmedDNSEntry.isEmpty else {
            dnsOutput = "DNS entry is required."
            return
        }
        guard localhostIPv4ValidationError == nil else {
            dnsOutput = localhostIPv4ValidationError ?? "Localhost IPv4 must be a valid IPv4 address."
            return
        }

        let entry = trimmedDNSEntry
        let localhostIPv4 = trimmedDNSLocalhostIPv4.isEmpty ? nil : trimmedDNSLocalhostIPv4

        runDNSAction(
            action: .create,
            commandDescription: createCommandDescription(entry: entry, localhostIPv4: localhostIPv4),
            successPrefix: "Created DNS entry: \(entry)"
        ) {
            try await containerCLIAdapter.createSystemDNS(entry: entry, localhostIPv4: localhostIPv4)
            return try await containerCLIAdapter.listSystemDNS()
        }
    }

    private func deleteSystemDNS() {
        guard !trimmedDNSEntry.isEmpty else {
            dnsOutput = "DNS entry is required."
            return
        }
        guard localhostIPv4ValidationError == nil else {
            dnsOutput = localhostIPv4ValidationError ?? "Localhost IPv4 must be a valid IPv4 address."
            return
        }

        let entry = trimmedDNSEntry
        let localhostIPv4 = trimmedDNSLocalhostIPv4.isEmpty ? nil : trimmedDNSLocalhostIPv4

        runDNSAction(
            action: .delete,
            commandDescription: deleteCommandDescription(entry: entry, localhostIPv4: localhostIPv4),
            successPrefix: "Deleted DNS entry: \(entry)"
        ) {
            try await containerCLIAdapter.deleteSystemDNS(entry: entry, localhostIPv4: localhostIPv4)
            return try await containerCLIAdapter.listSystemDNS()
        }
    }

    private func runDNSAction(
        action: HostDNSAction,
        commandDescription: String,
        successPrefix: String?,
        operation: @escaping @Sendable () async throws -> String
    ) {
        dnsTask?.cancel()
        actionInFlight = action
        lastCommand = commandDescription

        dnsTask = Task {
            do {
                let output = try await operation()
                await MainActor.run {
                    applySuccessfulOutput(output, successPrefix: successPrefix)
                    actionInFlight = nil
                    dnsTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    // Preserve raw CLI errors (including stderr) exactly as emitted.
                    dnsOutput = error.localizedDescription
                    actionInFlight = nil
                    dnsTask = nil
                }
            } catch {
                await MainActor.run {
                    dnsOutput = error.localizedDescription
                    actionInFlight = nil
                    dnsTask = nil
                }
            }
        }
    }

    private func applySuccessfulOutput(_ output: String, successPrefix: String?) {
        listedEntries = Self.parseDNSEntries(from: output)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOutput = trimmedOutput.isEmpty ? "No DNS entries were returned." : output

        if let successPrefix {
            dnsOutput = "\(successPrefix)\n\n\(normalizedOutput)"
        } else {
            dnsOutput = normalizedOutput
        }
    }

    private func createCommandDescription(entry: String, localhostIPv4: String?) -> String {
        var components = ["container", "system", "dns", "create"]
        if let localhostIPv4 {
            components.append(contentsOf: ["--localhost", localhostIPv4])
        }
        components.append(entry)
        return components.joined(separator: " ")
    }

    private func deleteCommandDescription(entry: String, localhostIPv4: String?) -> String {
        var components = ["container", "system", "dns", "delete"]
        if let localhostIPv4 {
            components.append(contentsOf: ["--localhost", localhostIPv4])
        }
        components.append(entry)
        return components.joined(separator: " ")
    }

    private static func parseDNSEntries(from output: String) -> [String] {
        var seen = Set<String>()
        return
            output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        value.range(
            of: #"^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct NetworkCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (NetworkCreateRequest) -> Void

    @State private var name = ""
    @State private var ipv4Subnet = ""
    @State private var ipv6Subnet = ""
    @State private var labelsText = ""
    @State private var isInternal = false
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Network")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $name)
                Toggle("Restrict to host-only network", isOn: $isInternal)
                TextField("IPv4 subnet (optional)", text: $ipv4Subnet)
                    .font(.system(.body, design: .monospaced))
                TextField("IPv6 subnet (optional)", text: $ipv6Subnet)
                    .font(.system(.body, design: .monospaced))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Labels")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $labelsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 88)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                    Text("One `key=value` entry per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let validationError {
                Text(validationError)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Create") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidNetworkName(trimmedName) else {
            validationError = "Network names must start and end with an alphanumeric character and may include hyphens."
            return
        }

        do {
            let request = NetworkCreateRequest(
                name: trimmedName,
                ipv4Subnet: Self.normalizedOptionalText(ipv4Subnet),
                ipv6Subnet: Self.normalizedOptionalText(ipv6Subnet),
                labels: try Self.parseKeyValueText(labelsText),
                isInternal: isInternal
            )
            onCreate(request)
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }

    private static func normalizedOptionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseKeyValueText(_ text: String) throws -> [String: String] {
        var output: [String: String] = [:]
        let entries = text.split(whereSeparator: \.isNewline)
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw NetworkCreateError.invalidKeyValue(trimmed)
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                throw NetworkCreateError.invalidKeyValue(trimmed)
            }
            output[key] = value
        }
        return output
    }

    private static func isValidNetworkName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#, options: .regularExpression) != nil
    }
}

private enum NetworkCreateError: LocalizedError {
    case invalidKeyValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidKeyValue(let entry):
            "Invalid label entry: \(entry)"
        }
    }
}
