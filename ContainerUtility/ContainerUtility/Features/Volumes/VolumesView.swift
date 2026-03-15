import AppKit
import SwiftUI

struct VolumesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<VolumeRow>] = [KeyPathComparator(\.name, order: .forward)]
    @State private var selectedVolumeNames = Set<String>()
    @State private var volumes: [VolumeListItem] = []
    @State private var relationshipScan = ResourceRelationshipScan.empty
    @State private var decodeWarnings: [String] = []
    @State private var rawFallbackOutput: String?
    @State private var inspectSnapshot: VolumeInspectSnapshot?
    @State private var inspectError: String?
    @State private var isLoading = false
    @State private var isPresentingCreateSheet = false
    @State private var lastError: AppError?
    @State private var confirmationAction: VolumeConfirmationAction?
    @State private var listTask: Task<Void, Never>?
    @State private var inspectTask: Task<Void, Never>?
    @State private var showInspector = true
    @State private var hasCompletedInitialLoad = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                listHeaderBar

                Divider()

                volumeListContent

                if showsFooter {
                    footerBar
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
            .background(.background)

            if showInspector {
                inspectorPane
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
            if isLoading && volumes.isEmpty {
                loadingOverlay
            }
        }
        .sheet(isPresented: $isPresentingCreateSheet) {
            VolumeCreateSheet { request in
                enqueueVolumeAction(
                    title: "Create volume \(request.name)",
                    summary: "Created volume \(request.name).",
                    commandDescription: buildCreateVolumeCommand(request)
                ) {
                    try await containerCLIAdapter.createVolume(
                        name: request.name,
                        size: request.size,
                        labels: request.labels,
                        options: request.options
                    )
                }
            }
        }
        .alert("Delete Volume?", isPresented: deleteConfirmationPresented) {
            if let names = deleteConfirmationNames {
                Button("Cancel", role: .cancel) {}
                Button("Delete \(names.count == 1 ? "Volume" : "Volumes")", role: .destructive) {
                    performDelete(names: names)
                }
            }
        } message: {
            if let names = deleteConfirmationNames {
                Text(confirmationMessage(for: .delete(names: names)))
            }
        }
        .confirmationDialog(
            pruneConfirmationTitle,
            isPresented: pruneConfirmationPresented,
            presenting: pruneConfirmationVolumes
        ) { unusedVolumes in
            Button("Prune", role: .destructive) {
                enqueueVolumeAction(
                    title: "Prune unused volumes",
                    summary: "Pruned \(unusedVolumes.count) unused volume(s).",
                    commandDescription: "container volume prune"
                ) {
                    try await containerCLIAdapter.pruneVolumes()
                }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        } message: { unusedVolumes in
            Text(confirmationMessage(for: .pruneUnused(unusedVolumes: unusedVolumes)))
        }
        .task {
            if volumes.isEmpty, !appModel.cachedVolumeItems.isEmpty {
                volumes = appModel.cachedVolumeItems
                hasCompletedInitialLoad = true
            }
            reloadVolumes()
        }
        .onChange(of: appModel.refreshRevision(for: .volumes)) { _, _ in
            guard !isLoading else { return }
            reloadVolumes()
        }
        .onChange(of: selectedVolumeName) { _, newValue in
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

    private var listHeaderBar: some View {
        HStack {
            Text(listPanelSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !selectedVolumes.isEmpty {
                Text("\(selectedVolumes.count) selected")
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
                reloadVolumes()
            } label: {
                toolbarButtonLabel("Refresh", systemImage: "arrow.clockwise", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .help("Refresh volume list (\u{2318}R)")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                isPresentingCreateSheet = true
            } label: {
                toolbarButtonLabel("Create", systemImage: "plus", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .help("Create a new volume")
            .keyboardShortcut("n", modifiers: .command)

            Button {
                confirmationAction = .delete(names: selectedVolumes.map(\.name))
            } label: {
                toolbarButtonLabel("Delete", systemImage: "trash", iconOnly: iconOnly)
            }
            .disabled(isBusy || selectedVolumes.isEmpty)
            .help("Delete selected volumes")
            .keyboardShortcut(.delete, modifiers: .command)

            Button {
                let unusedVolumes = volumes.filter { volumeUsages(for: $0.name).isEmpty }
                confirmationAction = .pruneUnused(unusedVolumes: unusedVolumes)
            } label: {
                toolbarButtonLabel("Prune", systemImage: "scissors", iconOnly: iconOnly)
            }
            .disabled(isBusy || volumes.isEmpty || volumes.allSatisfy { !volumeUsages(for: $0.name).isEmpty })
            .help("Prune unused volumes")
            .keyboardShortcut(.delete, modifiers: [.command, .shift])

            if isBusy {
                Button {
                    cancelRunningTask()
                } label: {
                    toolbarButtonLabel("Cancel", systemImage: "xmark", iconOnly: true)
                }
                .keyboardShortcut(.cancelAction)
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

    private var volumeListContent: some View {
        Group {
            if filteredRows.isEmpty && hasCompletedInitialLoad && !isLoading {
                emptyStateView
            } else {
                volumeTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPane: some View {
        ResourceInspectorPane(showsHeader: false) {
            if selectedVolumeName != nil {
                HStack(spacing: 8) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        if let selectedVolumeName {
                            loadInspect(name: selectedVolumeName)
                        }
                    }
                    .help("Reload inspect")
                    .labelStyle(.iconOnly)

                    Button("Copy JSON", systemImage: "doc.on.doc") {
                        copyJSON(inspectSnapshot?.rawJSON)
                    }
                    .help("Copy JSON")
                    .disabled(inspectSnapshot == nil)
                    .labelStyle(.iconOnly)
                }
            }
        } content: {
            if let selectedVolumeName {
                volumeDetailPane(name: selectedVolumeName)
            } else {
                emptyInspectorView
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ResourceEmptyStateSurface(backgroundOpacity: 0.08) {
            if searchText.isEmpty, let lastError {
                ResourceInspectorStateView(
                    descriptor: resourceListFailureDescriptor(
                        resourceName: "volumes",
                        error: lastError.localizedDescription,
                        systemHealth: appModel.latestSystemHealthSnapshot
                    )
                )
            } else {
                ContentUnavailableView {
                    Label(emptyStateTitle, systemImage: "internaldrive")
                } description: {
                    Text(emptyStateDetail)
                }
            }
        }
    }

    private var emptyInspectorView: some View {
        ResourceInspectorStateView(
            descriptor: ResourceInspectorStateDescriptor(
                title: "No Volume Selected",
                message: "Select a volume to inspect source details, relationships, and driver configuration.",
                systemImage: "internaldrive"
            )
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            Color(.windowBackgroundColor).opacity(0.85)

            VStack(spacing: 16) {
                ProgressView("Loading volumes...")
                    .controlSize(.large)
            }
            .padding(32)
            .background(.ultraThickMaterial)
            .cornerRadius(12)
        }
        .ignoresSafeArea()
    }

    private var volumeTable: some View {
        Table(of: VolumeRow.self, selection: $selectedVolumeNames, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 4) {
                    Text(row.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Source", value: \.sourceSortKey) { row in
                Text(row.sourceDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 160, ideal: 200)

            TableColumn("Driver", value: \.driverSortKey) { row in
                Text(row.driverDisplay)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Size", value: \.sizeSortKey) { row in
                Text(row.sizeDisplay)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Containers", value: \.attachedCount) { row in
                Text(String(row.attachedCount))
            }
            .width(min: 80, ideal: 100)
        } rows: {
            ForEach(filteredRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button {
                            selectedVolumeNames = [row.name]
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

                        Divider()

                        Button(role: .destructive) {
                            selectedVolumeNames = [row.name]
                            confirmationAction = .delete(names: [row.name])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func volumeDetailPane(name: String) -> some View {
        if let inspectSnapshot {
            loadedVolumeDetailPane(snapshot: inspectSnapshot, name: name)
        } else if let inspectError {
            ResourceInspectorStateView(
                descriptor: resourceInspectorFailureDescriptor(
                    resourceName: "volume",
                    error: inspectError,
                    systemHealth: appModel.latestSystemHealthSnapshot
                )
            )
        } else {
            ResourceInspectorLoadingView()
        }
    }

    private func loadedVolumeDetailPane(snapshot: VolumeInspectSnapshot, name: String) -> some View {
        let attachedContainers = volumeUsages(for: name)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ResourcePanel(
                    title: "Summary",
                    subtitle: "Driver, size, source, and creation metadata for the selected volume."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ResourceFactRow(title: "Name", value: snapshot.name)
                        ResourceFactRow(title: "Driver", value: snapshot.driver ?? "Unknown")
                        ResourceFactRow(title: "Format", value: snapshot.format ?? "Unknown")
                        ResourceFactRow(title: "Size", value: snapshot.sizeInBytes.map(formatBytes) ?? "Unknown")
                        ResourceFactRow(title: "Created", value: formatDate(snapshot.createdAt))
                        ResourceFactRow(title: "Source", value: snapshot.source ?? "Unknown")
                    }
                }

                relationshipPanel(attachedContainers: attachedContainers)
                labelsPanel(snapshot: snapshot)
                optionsPanel(snapshot: snapshot)

                ResourcePanel(
                    title: "Raw Inspect JSON",
                    subtitle: "Low-level volume metadata returned by the runtime."
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

    private func relationshipPanel(attachedContainers: [VolumeUsageRow]) -> some View {
        ResourcePanel(
            title: "Container Relationships",
            subtitle: "Derived from container mount configuration."
        ) {
            if attachedContainers.isEmpty {
                Text("No container relationship hints were found for this volume.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(attachedContainers) { usage in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(usage.containerName)
                                    .fontWeight(.medium)
                                Text(usage.destination)
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
    }

    private func labelsPanel(snapshot: VolumeInspectSnapshot) -> some View {
        ResourcePanel(
            title: "Labels",
            subtitle: "Applied volume metadata."
        ) {
            ResourceMonospacedOutput(
                text: formatMetadata(snapshot.labels),
                placeholder: "None"
            )
            .frame(minHeight: 120)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func optionsPanel(snapshot: VolumeInspectSnapshot) -> some View {
        ResourcePanel(
            title: "Driver Options",
            subtitle: "Driver-specific configuration for the selected volume."
        ) {
            ResourceMonospacedOutput(
                text: formatMetadata(snapshot.options),
                placeholder: "None"
            )
            .frame(minHeight: 120)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var footerBar: some View {
        ResourceListFeedbackBar(
            activity: activeSectionActivity,
            warningMessages: decodeWarnings,
            errorMessage: lastError?.localizedDescription
        )
    }

    private var isBusy: Bool {
        isLoading || appModel.hasActiveActivity(for: .volumes)
    }

    private var filteredRows: [VolumeRow] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = volumes.map { VolumeRow(item: $0, attachedCount: volumeUsages(for: $0.name).count) }
        if !search.isEmpty {
            rows = rows.filter { $0.searchBlob.contains(search) }
        }
        rows.sort(using: sortOrder)
        return rows
    }

    private var selectedVolumeName: String? {
        guard selectedVolumeNames.count == 1 else { return nil }
        return selectedVolumeNames.first
    }

    private var selectedVolumes: [VolumeListItem] {
        volumes.filter { selectedVolumeNames.contains($0.name) }
    }

    private var listPanelSubtitle: String {
        if isLoading && volumes.isEmpty {
            return "Loading..."
        }

        let count = filteredRows.count
        let total = volumes.count
        let referenced = volumes.filter { !volumeUsages(for: $0.name).isEmpty }.count
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(total) total, \(referenced) referenced by containers"
        }
        return "\(count) of \(total)"
    }

    private var emptyStateTitle: String {
        searchText.isEmpty ? "No Volumes" : "No Matching Volumes"
    }

    private var emptyStateDetail: String {
        searchText.isEmpty
            ? "Create a volume or refresh the runtime state."
            : "Adjust the search text to broaden the results."
    }

    private var confirmationTitle: String {
        switch confirmationAction {
        case .delete(let names):
            "Delete \(names.count == 1 ? "Volume" : "Volumes")"
        case .pruneUnused(let unusedVolumes):
            "Prune Unused Volumes (\(unusedVolumes.count))"
        case .none:
            ""
        }
    }

    private var deleteConfirmationNames: [String]? {
        guard case .delete(let names) = confirmationAction else { return nil }
        return names
    }

    private var pruneConfirmationVolumes: [VolumeListItem]? {
        guard case .pruneUnused(let unusedVolumes) = confirmationAction else { return nil }
        return unusedVolumes
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                if case .delete = confirmationAction {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, case .delete = confirmationAction {
                    confirmationAction = nil
                }
            }
        )
    }

    private var pruneConfirmationTitle: String {
        switch confirmationAction {
        case .pruneUnused(let unusedVolumes):
            "Prune Unused Volumes (\(unusedVolumes.count))"
        default:
            ""
        }
    }

    private var pruneConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                if case .pruneUnused = confirmationAction {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, case .pruneUnused = confirmationAction {
                    confirmationAction = nil
                }
            }
        )
    }

    private var showsFooter: Bool {
        activeSectionActivity != nil || !decodeWarnings.isEmpty || lastError != nil
    }

    private func reloadVolumes() {
        listTask?.cancel()
        let shouldShowLoading = volumes.isEmpty
        if shouldShowLoading {
            isLoading = true
        }
        lastError = nil

        listTask = Task {
            do {
                async let listResult = containerCLIAdapter.listVolumes()
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
                        volumes = []
                        relationshipScan = .empty
                        appModel.updateVolumes(from: [], relationships: [])
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
                        volumes = []
                        relationshipScan = .empty
                        appModel.updateVolumes(from: [], relationships: [])
                        decodeWarnings = []
                        rawFallbackOutput = nil
                    }
                    lastError = .commandLaunchFailed(
                        command: "container volume list --format json",
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
        _ result: NonCriticalDecodeResult<[VolumeListItem]>,
        relationshipScan scan: ResourceRelationshipScan
    ) {
        relationshipScan = scan
        switch result {
        case .parsed(let value, let diagnostics):
            volumes = value
            appModel.cachedVolumeItems = value
            decodeWarnings = diagnostics.warnings + scan.warnings
            rawFallbackOutput = nil
            appModel.updateVolumes(from: value, relationships: scan.hints)
        case .raw(let output, let diagnostics):
            decodeWarnings = diagnostics.warnings + scan.warnings
            rawFallbackOutput = output
        }

        let validNames = Set(volumes.map(\.name))
        selectedVolumeNames = selectedVolumeNames.intersection(validNames)
        if selectedVolumeName == nil {
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
                let snapshot = try await containerCLIAdapter.inspectVolume(name: requestedName)
                await MainActor.run {
                    guard selectedVolumeName == requestedName else { return }
                    inspectSnapshot = snapshot
                    inspectTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    guard selectedVolumeName == requestedName else { return }
                    inspectSnapshot = nil
                    inspectError = error.localizedDescription
                    inspectTask = nil
                }
            } catch {
                await MainActor.run {
                    guard selectedVolumeName == requestedName else { return }
                    inspectSnapshot = nil
                    inspectError = error.localizedDescription
                    inspectTask = nil
                }
            }
        }
    }

    private var latestSectionActivity: ActivityRecord? {
        appModel.latestActivity(for: .volumes)
    }

    private var activeSectionActivity: ActivityRecord? {
        guard let latestSectionActivity, latestSectionActivity.status.isActive else {
            return nil
        }
        return latestSectionActivity
    }

    private func enqueueVolumeAction(
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
            section: .volumes,
            kind: .volume,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await operation()
                await refreshVolumeSummary()
                return ActivityOperationOutcome(summary: completionSummary)
            } catch let error as AppError {
                await refreshVolumeSummary()
                throw error
            } catch {
                await refreshVolumeSummary()
                throw AppError.commandLaunchFailed(command: commandDescription, reason: error.localizedDescription)
            }
        }
    }

    private func refreshVolumeSummary() async {
        async let listResult = try? containerCLIAdapter.listVolumes()
        async let relationshipScan = containerCLIAdapter.scanResourceRelationships()
        let result = await listResult
        let scan = await relationshipScan

        if let result {
            if case .parsed(let value, _) = result {
                appModel.cachedVolumeItems = value
            }
            appModel.updateVolumeSummary(from: result, relationships: scan.hints)
        }
        appModel.bumpRefreshRevision(for: .volumes)
    }

    private func cancelRunningTask() {
        if isLoading {
            listTask?.cancel()
            isLoading = false
            listTask = nil
        } else {
            appModel.cancelLatestActiveActivity(in: .volumes)
        }
    }

    private func buildCreateVolumeCommand(_ request: VolumeCreateRequest) -> String {
        var components = ["container", "volume", "create", request.name]
        if let size = request.size, !size.isEmpty {
            components.append(contentsOf: ["-s", size])
        }
        for (key, value) in request.labels.sorted(by: { $0.key < $1.key }) {
            components.append(contentsOf: ["--label", "\(key)=\(value)"])
        }
        for (key, value) in request.options.sorted(by: { $0.key < $1.key }) {
            components.append(contentsOf: ["--opt", "\(key)=\(value)"])
        }
        return components.joined(separator: " ")
    }

    private func volumeUsages(for name: String) -> [VolumeUsageRow] {
        relationshipScan.hints
            .flatMap { hint in
                hint.volumeMounts
                    .filter { $0.name == name }
                    .map {
                        VolumeUsageRow(
                            containerID: hint.containerID,
                            containerName: hint.containerName,
                            containerState: hint.containerState,
                            destination: $0.destination.isEmpty ? "Unknown destination" : $0.destination
                        )
                    }
            }
            .sorted { $0.containerName.localizedStandardCompare($1.containerName) == .orderedAscending }
    }

    private func confirmationMessage(for action: VolumeConfirmationAction) -> String {
        switch action {
        case .delete:
            return
                "This removes the selected volume definition. Containers that still reference it may fail to start until their configuration is updated."
        case .pruneUnused(let unusedVolumes):
            if unusedVolumes.isEmpty {
                return "No unused volumes found."
            } else if unusedVolumes.count == 1 {
                return "This will delete the unused volume '\(unusedVolumes[0].name)'. This action cannot be undone."
            } else {
                let volumeNames = unusedVolumes.map { $0.name }.joined(separator: ", ")
                return
                    "This will delete \(unusedVolumes.count) unused volumes: \(volumeNames). This action cannot be undone."
            }
        }
    }

    private func performDelete(names: [String]) {
        enqueueVolumeAction(
            title: "Delete \(names.count) volume(s)",
            summary: "Deleted \(names.count) volume(s).",
            commandDescription: "container volume delete \(names.joined(separator: " "))"
        ) {
            try await containerCLIAdapter.deleteVolumes(names: names)
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

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    private func copyJSON(_ rawJSON: String?) {
        guard let rawJSON else { return }
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawJSON, forType: .string)
        #endif
    }

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum VolumeConfirmationAction: Equatable {
    case delete(names: [String])
    case pruneUnused(unusedVolumes: [VolumeListItem])
}

private struct VolumeRow: Identifiable {
    let item: VolumeListItem
    let attachedCount: Int

    var id: String { item.id }
    var name: String { item.name }
    var driverDisplay: String { item.driver ?? "Unknown" }
    var driverSortKey: String { item.driver ?? "" }
    var sizeDisplay: String {
        item.sizeInBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .binary) } ?? "Unknown"
    }
    var sizeSortKey: Int64 { item.sizeInBytes ?? 0 }
    var sourceDisplay: String { item.source ?? "No source path" }
    var sourceSortKey: String { item.source ?? "" }
    var searchBlob: String {
        [
            item.name,
            item.driver ?? "",
            item.format ?? "",
            item.source ?? "",
            item.labels.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            item.options.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

private struct VolumeUsageRow: Identifiable {
    let containerID: String
    let containerName: String
    let containerState: String
    let destination: String

    var id: String { "\(containerID):\(destination)" }
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

private struct VolumeCreateRequest {
    let name: String
    let size: String?
    let labels: [String: String]
    let options: [String: String]
}

private struct VolumeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (VolumeCreateRequest) -> Void

    @State private var name = ""
    @State private var size = ""
    @State private var labelsText = ""
    @State private var optionsText = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Volume")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $name)
                TextField("Size (optional)", text: $size)
                    .font(.system(.body, design: .monospaced))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Labels")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $labelsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 76)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                    Text("One `key=value` entry per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Driver Options")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $optionsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 76)
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
        .frame(width: 500)
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Volume name is required."
            return
        }

        do {
            let request = VolumeCreateRequest(
                name: trimmedName,
                size: Self.normalizedOptionalText(size),
                labels: try Self.parseKeyValueText(labelsText),
                options: try Self.parseKeyValueText(optionsText)
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
                throw VolumeCreateError.invalidKeyValue(trimmed)
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                throw VolumeCreateError.invalidKeyValue(trimmed)
            }
            output[key] = value
        }
        return output
    }
}

private enum VolumeCreateError: LocalizedError {
    case invalidKeyValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidKeyValue(let entry):
            "Invalid entry: \(entry)"
        }
    }
}
