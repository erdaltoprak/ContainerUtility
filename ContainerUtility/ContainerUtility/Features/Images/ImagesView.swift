import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImagesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<ImageRow>] = [KeyPathComparator(\.reference, order: .forward)]
    @State private var selectedImageReferences = Set<String>()
    @State private var images: [ImageListItem] = []
    @State private var pullReference = ""
    @State private var workflowTagSourceReference = ""
    @State private var workflowTagTargetReference = ""
    @State private var workflowPushReference = ""
    @State private var workflowPushManualReference = ""
    @State private var workflowPushScheme = ""
    @State private var workflowPushProgress = "none"
    @State private var workflowPushPlatform = ""
    @State private var workflowPushArchitecture = ""
    @State private var workflowPushOperatingSystem = ""
    @State private var isShowingPushOptionalSettings = false
    @State private var inspectSnapshot: ImageInspectSnapshot?
    @State private var inspectError: String?
    @State private var isLoading = false
    @State private var lastError: AppError?
    @State private var confirmationAction: ImageConfirmationAction?
    @State private var listTask: Task<Void, Never>?
    @State private var inspectTask: Task<Void, Never>?
    @State private var showInspector = true
    @State private var hasCompletedInitialLoad = false
    @State private var isPresentingWorkflowSheet = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                listHeaderBar

                Divider()

                if filteredRows.isEmpty {
                    emptyStateOverlay
                } else {
                    imageListPane
                }

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
                workflowButton(iconOnly: true)
                actionButtons(iconOnly: true)
                refreshButton(iconOnly: true)
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
                .help("Toggle Inspector (⌘I)")
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            presenting: confirmationAction
        ) { action in
            switch action {
            case .delete(let references, let count):
                Button("Delete \(count == 1 ? "Image" : "Images")", role: .destructive) {
                    deleteImages(references: references, count: count)
                }
            case .pruneUnused:
                Button("Prune Unused Images", role: .destructive) {
                    enqueueImageAction(
                        title: "Prune unused images",
                        summary: "Pruned unused images.",
                        commandDescription: "container image prune --all"
                    ) {
                        try await containerCLIAdapter.pruneImages(removeAllUnused: true)
                    }
                }
            }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
        .sheet(isPresented: $isPresentingWorkflowSheet) {
            workflowSheet
        }
        .task {
            if images.isEmpty, !appModel.cachedImageItems.isEmpty {
                images = appModel.cachedImageItems
                hasCompletedInitialLoad = true
            }
            reloadImages()
        }
        .onChange(of: appModel.refreshRevision(for: .images)) { _, _ in
            guard !isLoading else { return }
            reloadImages()
        }
        .onChange(of: selectedImageReferences) { _, newValue in
            if newValue.count == 1, let reference = newValue.first {
                if workflowTagSourceTrimmed.isEmpty {
                    workflowTagSourceReference = reference
                }
                if workflowPushReferenceTrimmed.isEmpty {
                    workflowPushReference = reference
                }
                normalizeWorkflowSelections()
                if !showInspector {
                    showInspector = true
                }
                loadInspect(reference: reference)
            } else {
                inspectTask?.cancel()
                inspectSnapshot = nil
                inspectError = nil
            }
        }
        .onDisappear {
            listTask?.cancel()
            inspectTask?.cancel()
        }
        .navigationTitle("")
    }

    // MARK: - List Header

    private var listHeaderBar: some View {
        HStack {
            Text(listPanelSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !selectedImageReferences.isEmpty {
                Text("\(selectedImageReferences.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func workflowButton(iconOnly: Bool) -> some View {
        Button {
            prepareWorkflowFromCurrentSelection()
            isPresentingWorkflowSheet = true
        } label: {
            toolbarButtonLabel("Workflow", systemImage: "arrow.triangle.merge", iconOnly: iconOnly)
        }
        .disabled(isBusy)
        .help("Pull, tag, and push")
        .controlSize(iconOnly ? .regular : .small)
    }

    private var workflowSheet: some View {
        NavigationStack {
            Form {
                Section("Pull / Tag / Push") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pull")
                            .font(.headline)

                        HStack(spacing: 8) {
                            TextField("Image reference", text: $pullReference)
                                .textFieldStyle(.roundedBorder)
                            Button("Pull") {
                                performPull()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy || workflowPullReferenceTrimmed.isEmpty)
                        }

                        workflowCommandPreview(command: pullCommandDescription(for: workflowPullReferenceTrimmed))

                        Divider()

                        Text("Tag")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Picker("Source image", selection: $workflowTagSourceReference) {
                                if workflowTagSourceTrimmed.isEmpty {
                                    Text("Select local image").tag("")
                                }
                                if !workflowTagSourceTrimmed.isEmpty,
                                    !localImageReferences.contains(workflowTagSourceTrimmed)
                                {
                                    Text(workflowTagSourceTrimmed).tag(workflowTagSourceTrimmed)
                                }
                                ForEach(localImageReferences, id: \.self) { reference in
                                    Text(reference).tag(reference)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            TextField("Target reference", text: $workflowTagTargetReference)
                                .textFieldStyle(.roundedBorder)
                            Button("Tag") {
                                performTag()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy || workflowTagSourceTrimmed.isEmpty || workflowTagTargetTrimmed.isEmpty)
                        }

                        workflowCommandPreview(
                            command: tagCommandDescription(
                                sourceReference: workflowTagSourceTrimmed,
                                targetReference: workflowTagTargetTrimmed
                            )
                        )

                        Divider()

                        Text("Push")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Picker("Local reference", selection: $workflowPushReference) {
                                if workflowPushReferenceTrimmed.isEmpty {
                                    Text("Select local image").tag("")
                                }
                                if !workflowPushReferenceTrimmed.isEmpty,
                                    !localImageReferences.contains(workflowPushReferenceTrimmed)
                                {
                                    Text(workflowPushReferenceTrimmed).tag(workflowPushReferenceTrimmed)
                                }
                                ForEach(localImageReferences, id: \.self) { reference in
                                    Text(reference).tag(reference)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)

                            Button("Push") {
                                performPush()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isBusy || workflowPushReferenceForExecutionTrimmed.isEmpty)
                        }

                        DisclosureGroup("Optional", isExpanded: $isShowingPushOptionalSettings) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Manual push reference override", text: $workflowPushManualReference)
                                    .textFieldStyle(.roundedBorder)

                                HStack(spacing: 8) {
                                    TextField("Scheme", text: $workflowPushScheme)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Progress (default: none)", text: $workflowPushProgress)
                                        .textFieldStyle(.roundedBorder)
                                }

                                HStack(spacing: 8) {
                                    TextField("Platform", text: $workflowPushPlatform)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Architecture", text: $workflowPushArchitecture)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("OS", text: $workflowPushOperatingSystem)
                                        .textFieldStyle(.roundedBorder)
                                }

                                if !workflowPushPlatformTrimmed.isEmpty {
                                    Text("`--platform` takes precedence over architecture and OS when set.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        }

                        workflowCommandPreview(
                            command: pushCommandDescription(request: workflowPushRequest)
                        )
                        Text("Registry auth and session management moved to the Registries view.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Image Workflow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresentingWorkflowSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 640)
    }

    private func workflowCommandPreview(command: String) -> some View {
        Text(command)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
    }

    private func searchField(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: width)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionButtons(iconOnly: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                loadImageArchive()
            } label: {
                toolbarButtonLabel("Load", systemImage: "archivebox", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .controlSize(iconOnly ? .regular : .small)
            .help("Load image archive")

            Button {
                confirmationAction = .pruneUnused
            } label: {
                toolbarButtonLabel("Prune", systemImage: "scissors", iconOnly: iconOnly)
            }
            .disabled(isBusy || images.isEmpty)
            .controlSize(iconOnly ? .regular : .small)
            .help("Prune unused images")

            if !selectedImageReferences.isEmpty {
                Button {
                    saveSelectedImages()
                } label: {
                    toolbarButtonLabel("Save", systemImage: "square.and.arrow.down", iconOnly: iconOnly)
                }
                .disabled(isBusy)
                .controlSize(iconOnly ? .regular : .small)
                .help("Save selected images")

                Button(role: .destructive) {
                    confirmationAction = .delete(
                        references: Array(selectedImageReferences),
                        count: selectedImageReferences.count
                    )
                } label: {
                    toolbarButtonLabel("Delete", systemImage: "trash", iconOnly: iconOnly)
                }
                .disabled(isBusy)
                .controlSize(iconOnly ? .regular : .small)
                .help("Delete selected images (⌘Delete)")
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }

    private func refreshButton(iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                reloadImages()
            } label: {
                toolbarButtonLabel("Refresh", systemImage: "arrow.clockwise", iconOnly: iconOnly)
            }
            .disabled(isBusy)
            .help("Refresh image list")
            .controlSize(iconOnly ? .regular : .small)
            .keyboardShortcut("r", modifiers: .command)

            if isBusy {
                Button {
                    cancelRunningTask()
                } label: {
                    toolbarButtonLabel("Cancel", systemImage: "xmark", iconOnly: true)
                }
                .help("Cancel running operation")
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

    private var imageListPane: some View {
        imageTable
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }

    private var footerBar: some View {
        ResourceListFeedbackBar(
            activity: activeSectionActivity,
            warningMessages: [],
            errorMessage: lastError?.localizedDescription
        )
    }

    private var inspectorPane: some View {
        ResourceInspectorPane(showsHeader: false) {
            if let reference = selectedImageReference {
                HStack(spacing: 8) {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        loadInspect(reference: reference)
                    }
                    .labelStyle(.iconOnly)

                    Button("Copy JSON", systemImage: "doc.on.doc") {
                        copyInspectJSON()
                    }
                    .disabled(inspectSnapshot == nil)
                    .labelStyle(.iconOnly)
                }
            }
        } content: {
            Group {
                if selectedImageReference != nil {
                    imageInspectorContent
                } else {
                    emptyInspectorView
                }
            }
        }
    }

    private var emptyInspectorView: some View {
        ResourceInspectorStateView(
            descriptor: ResourceInspectorStateDescriptor(
                title: "No Image Selected",
                message: "Select an image from the list to view its details and metadata.",
                systemImage: "photo.stack"
            )
        )
    }

    private var emptyStateOverlay: some View {
        ResourceEmptyStateSurface(backgroundOpacity: 0.08) {
            Group {
                if !hasCompletedInitialLoad || isLoading {
                    ProgressView("Loading images...")
                        .frame(maxWidth: .infinity)
                } else if searchText.isEmpty, let lastError {
                    ResourceInspectorStateView(
                        descriptor: resourceListFailureDescriptor(
                            resourceName: "images",
                            error: lastError.localizedDescription,
                            systemHealth: appModel.latestSystemHealthSnapshot
                        )
                    )
                } else {
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: "photo.stack")
                    } description: {
                        Text(emptyStateDetail)
                    }
                }
            }
        }
    }

    // MARK: - Table

    private var imageTable: some View {
        Table(of: ImageRow.self, selection: $selectedImageReferences, sortOrder: $sortOrder) {
            TableColumn("Reference", value: \.reference) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.reference)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.reference)
                    Text(row.shortID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .help(row.shortID)
                }
            }
            .width(min: 200, ideal: 280)

            TableColumn("Size", value: \.sizeDisplay) { row in
                Text(row.sizeDisplay)
            }
            .width(min: 80, ideal: 100)
        } rows: {
            ForEach(filteredRows) { row in
                TableRow(row)
                    .contextMenu {
                        imageContextMenu(for: row)
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func imageContextMenu(for row: ImageRow) -> some View {
        Button {
            pullReference = row.reference
            performPull()
        } label: {
            Label("Pull", systemImage: "arrow.down")
        }

        Button {
            workflowTagSourceReference = row.reference
            if workflowPushReferenceTrimmed.isEmpty {
                workflowPushReference = row.reference
            }
            isPresentingWorkflowSheet = true
        } label: {
            Label("Tag / Push", systemImage: "arrow.triangle.merge")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.reference, forType: .string)
        } label: {
            Label("Copy Reference", systemImage: "doc.on.doc")
        }

        Button {
            if images.contains(where: { $0.reference == row.reference }) {
                selectedImageReferences = [row.reference]
                loadInspect(reference: row.reference)
            }
        } label: {
            Label("Inspect", systemImage: "eye")
        }

        Divider()

        Button(role: .destructive) {
            confirmationAction = .delete(references: [row.reference], count: 1)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var imageInspectorContent: some View {
        Group {
            if let inspectSnapshot {
                inspectorContent(snapshot: inspectSnapshot)
            } else if let inspectError {
                ResourceInspectorStateView(
                    descriptor: resourceInspectorFailureDescriptor(
                        resourceName: "image",
                        error: inspectError,
                        systemHealth: appModel.latestSystemHealthSnapshot
                    )
                )
            } else {
                ResourceInspectorLoadingView()
            }
        }
    }

    @ViewBuilder
    private func inspectorContent(snapshot: ImageInspectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary")
                    .font(.headline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Form {
                    inspectorLabeledContent("Reference", value: snapshot.reference)
                    inspectorLabeledContent("Digest", value: snapshot.digest ?? "Unknown")
                    inspectorLabeledContent("Media Type", value: snapshot.mediaType ?? "Unknown")
                    inspectorLabeledContent("Variants", value: String(snapshot.variantCount))
                    inspectorLabeledContent("Size", value: snapshot.sizeBytes.map(formatBytes) ?? "Unknown")
                    inspectorLabeledContent("Created", value: snapshot.created ?? "Unknown")
                    inspectorLabeledContent("Platform", value: platformDescription(for: snapshot))
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Raw JSON")
                        .font(.headline.weight(.medium))
                    Spacer()
                    Text("\(snapshot.rawJSON.count) chars")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ResourceMonospacedOutput(
                    text: snapshot.rawJSON,
                    placeholder: "Inspect output not loaded yet."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inspectorLabeledContent(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
        }
    }

    // MARK: - Helpers

    private var isBusy: Bool {
        isLoading || appModel.hasActiveActivity(for: .images)
    }

    private var filteredRows: [ImageRow] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = images.map(ImageRow.init)

        if !search.isEmpty {
            rows = rows.filter { $0.searchBlob.contains(search) }
        }

        rows.sort(using: sortOrder)
        return rows
    }

    private var selectedImageReference: String? {
        guard selectedImageReferences.count == 1 else { return nil }
        return selectedImageReferences.first
    }

    private var summaryText: String {
        "\(images.count) total"
    }

    private var activeSectionActivity: ActivityRecord? {
        guard let latestActivity = appModel.latestActivity(for: .images), latestActivity.status.isActive else {
            return nil
        }
        return latestActivity
    }

    private var listPanelSubtitle: String {
        if isLoading && images.isEmpty {
            return "Loading..."
        }

        let count = filteredRows.count
        let total = images.count
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(count) images"
        }
        return "\(count) of \(total)"
    }

    private var emptyStateTitle: String {
        if isLoading {
            return "Loading Images"
        } else if !searchText.isEmpty {
            return "No Matching Images"
        } else {
            return "No Images"
        }
    }

    private var emptyStateDetail: String {
        if !searchText.isEmpty {
            return "Adjust the search to broaden the results."
        }
        return "Pull or load an image archive to populate this view."
    }

    private var confirmationTitle: String {
        switch confirmationAction {
        case .delete(_, let count):
            "Delete \(count == 1 ? "Image" : "Images")"
        case .pruneUnused:
            "Prune Unused Images"
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

    private var showsFooter: Bool {
        activeSectionActivity != nil || lastError != nil
    }

    private var workflowPullReferenceTrimmed: String {
        pullReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowTagSourceTrimmed: String {
        workflowTagSourceReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowTagTargetTrimmed: String {
        workflowTagTargetReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushReferenceTrimmed: String {
        workflowPushReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushManualReferenceTrimmed: String {
        workflowPushManualReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushReferenceForExecutionTrimmed: String {
        if !workflowPushManualReferenceTrimmed.isEmpty {
            return workflowPushManualReferenceTrimmed
        }
        return workflowPushReferenceTrimmed
    }

    private var workflowPushSchemeTrimmed: String {
        workflowPushScheme.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushProgressTrimmed: String {
        workflowPushProgress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushPlatformTrimmed: String {
        workflowPushPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushArchitectureTrimmed: String {
        workflowPushArchitecture.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workflowPushOperatingSystemTrimmed: String {
        workflowPushOperatingSystem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localImageReferences: [String] {
        Array(Set(images.map(\.reference)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var workflowPushRequest: ImagePushRequest {
        ImagePushRequest(
            reference: workflowPushReferenceForExecutionTrimmed,
            scheme: workflowPushSchemeTrimmed.isEmpty ? nil : workflowPushSchemeTrimmed,
            progress: workflowPushProgressTrimmed.isEmpty ? nil : workflowPushProgressTrimmed,
            platform: workflowPushPlatformTrimmed.isEmpty ? nil : workflowPushPlatformTrimmed,
            architecture: workflowPushArchitectureTrimmed.isEmpty ? nil : workflowPushArchitectureTrimmed,
            operatingSystem: workflowPushOperatingSystemTrimmed.isEmpty ? nil : workflowPushOperatingSystemTrimmed
        )
    }

    private func prepareWorkflowFromCurrentSelection() {
        if workflowTagSourceTrimmed.isEmpty {
            if let selectedImageReference {
                workflowTagSourceReference = selectedImageReference
            } else if !workflowPullReferenceTrimmed.isEmpty {
                workflowTagSourceReference = workflowPullReferenceTrimmed
            } else if let firstReference = localImageReferences.first {
                workflowTagSourceReference = firstReference
            }
        }

        if workflowPushReferenceTrimmed.isEmpty {
            if !workflowTagTargetTrimmed.isEmpty {
                workflowPushReference = workflowTagTargetTrimmed
            } else if !workflowTagSourceTrimmed.isEmpty {
                workflowPushReference = workflowTagSourceTrimmed
            } else if let firstReference = localImageReferences.first {
                workflowPushReference = firstReference
            }
        }

        normalizeWorkflowSelections()
    }

    private func normalizeWorkflowSelections() {
        let references = localImageReferences
        guard !references.isEmpty else { return }

        if !workflowTagSourceTrimmed.isEmpty, !references.contains(workflowTagSourceTrimmed) {
            workflowTagSourceReference = selectedImageReference ?? references[0]
        } else if workflowTagSourceTrimmed.isEmpty {
            workflowTagSourceReference = selectedImageReference ?? references[0]
        }

        if !workflowPushReferenceTrimmed.isEmpty, !references.contains(workflowPushReferenceTrimmed) {
            if references.contains(workflowTagTargetTrimmed) {
                workflowPushReference = workflowTagTargetTrimmed
            } else if references.contains(workflowTagSourceTrimmed) {
                workflowPushReference = workflowTagSourceTrimmed
            } else {
                workflowPushReference = selectedImageReference ?? references[0]
            }
        } else if workflowPushReferenceTrimmed.isEmpty {
            if references.contains(workflowTagTargetTrimmed) {
                workflowPushReference = workflowTagTargetTrimmed
            } else if references.contains(workflowTagSourceTrimmed) {
                workflowPushReference = workflowTagSourceTrimmed
            } else {
                workflowPushReference = selectedImageReference ?? references[0]
            }
        }
    }

    private func pullCommandDescription(for reference: String) -> String {
        buildCommandDescription(arguments: ["image", "pull", "--progress", "none", "--", reference])
    }

    private func tagCommandDescription(sourceReference: String, targetReference: String) -> String {
        buildCommandDescription(arguments: ["image", "tag", sourceReference, targetReference])
    }

    private func pushCommandDescription(request: ImagePushRequest) -> String {
        var arguments = ["image", "push"]
        if let scheme = nonEmpty(request.scheme) {
            arguments.append(contentsOf: ["--scheme", scheme])
        }
        if let progress = nonEmpty(request.progress) {
            arguments.append(contentsOf: ["--progress", progress])
        }
        if let platform = nonEmpty(request.platform) {
            arguments.append(contentsOf: ["--platform", platform])
        } else {
            if let architecture = nonEmpty(request.architecture) {
                arguments.append(contentsOf: ["--arch", architecture])
            }
            if let operatingSystem = nonEmpty(request.operatingSystem) {
                arguments.append(contentsOf: ["--os", operatingSystem])
            }
        }
        arguments.append(request.reference)
        return buildCommandDescription(arguments: arguments)
    }

    private func deleteImageCommandDescription(references: [String]) -> String {
        buildCommandDescription(arguments: ["image", "delete", "--"] + references)
    }

    private func loadImagesCommandDescription(inputPath: String) -> String {
        buildCommandDescription(arguments: ["image", "load", "--input", inputPath])
    }

    private func saveImagesCommandDescription(references: [String], outputPath: String, platform: String?) -> String {
        var arguments = ["image", "save"]
        if let platform, !platform.isEmpty {
            arguments.append(contentsOf: ["--platform", platform])
        }
        arguments.append(contentsOf: ["--output", outputPath, "--"])
        arguments.append(contentsOf: references)
        return buildCommandDescription(arguments: arguments)
    }

    private func buildCommandDescription(arguments: [String]) -> String {
        (["container"] + arguments).map(shellQuote).joined(separator: " ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%_+=:,./-"))
        if value.rangeOfCharacter(from: allowed.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Actions

    private func performPull() {
        let reference = workflowPullReferenceTrimmed
        guard !reference.isEmpty else { return }

        enqueueImageAction(
            title: "Pull \(reference)",
            summary: "Pulled \(reference).",
            commandDescription: pullCommandDescription(for: reference)
        ) {
            try await containerCLIAdapter.pullImage(reference: reference)
        }

        workflowTagSourceReference = reference
        pullReference = ""
    }

    private func performTag() {
        let sourceReference = workflowTagSourceTrimmed
        let targetReference = workflowTagTargetTrimmed
        guard !sourceReference.isEmpty, !targetReference.isEmpty else { return }

        enqueueImageAction(
            title: "Tag \(sourceReference)",
            summary: "Tagged \(sourceReference) as \(targetReference).",
            commandDescription: tagCommandDescription(
                sourceReference: sourceReference,
                targetReference: targetReference
            )
        ) {
            try await containerCLIAdapter.tagImage(
                sourceReference: sourceReference,
                targetReference: targetReference
            )
        }

        workflowPushReference = targetReference
    }

    private func performPush() {
        let request = workflowPushRequest
        let reference = request.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }

        enqueueImageAction(
            title: "Push \(reference)",
            summary: "Pushed \(reference).",
            commandDescription: pushCommandDescription(request: request)
        ) {
            try await containerCLIAdapter.pushImage(request: request)
        }
    }

    private func deleteImages(references: [String], count: Int) {
        let sortedReferences = references.sorted()
        enqueueImageAction(
            title: "Delete \(count) image(s)",
            summary: "Deleted \(count) image(s).",
            commandDescription: deleteImageCommandDescription(references: sortedReferences)
        ) {
            try await containerCLIAdapter.deleteImages(references: sortedReferences)
        }
    }

    private func reloadImages() {
        listTask?.cancel()
        let shouldShowLoading = images.isEmpty
        if shouldShowLoading {
            isLoading = true
        }
        lastError = nil

        listTask = Task {
            do {
                let result = try await containerCLIAdapter.listImages()
                await MainActor.run {
                    applyListResult(result)
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    if shouldShowLoading {
                        images = []
                        appModel.updateImages(from: [])
                    }
                    lastError = error
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            } catch {
                await MainActor.run {
                    if shouldShowLoading {
                        images = []
                        appModel.updateImages(from: [])
                    }
                    lastError = .commandLaunchFailed(
                        command: "container image list --format json",
                        reason: error.localizedDescription
                    )
                    hasCompletedInitialLoad = true
                    isLoading = false
                    listTask = nil
                }
            }
        }
    }

    private func applyListResult(_ result: NonCriticalDecodeResult<[ImageListItem]>) {
        switch result {
        case .parsed(let value, _):
            images = value
            appModel.cachedImageItems = value
            appModel.updateImages(from: value)
            lastError = nil
        case .raw(let output, let diagnostics):
            images = []
            appModel.cachedImageItems = []
            appModel.updateImages(from: [])
            let details =
                diagnostics.warnings.isEmpty
                ? output.trimmingCharacters(in: .whitespacesAndNewlines)
                : diagnostics.warnings.joined(separator: "\n")
            let reason = details.isEmpty ? "Image list returned unsupported output." : details
            lastError = .commandLaunchFailed(command: "container image list --format json", reason: reason)
        }

        let valid = Set(images.map(\.reference))
        selectedImageReferences = selectedImageReferences.intersection(valid)
        normalizeWorkflowSelections()
    }

    private func loadInspect(reference: String) {
        inspectTask?.cancel()
        inspectSnapshot = nil
        inspectError = nil
        let requestedReference = reference

        inspectTask = Task {
            do {
                let snapshot = try await containerCLIAdapter.inspectImage(reference: requestedReference)
                await MainActor.run {
                    guard selectedImageReference == requestedReference else { return }
                    inspectSnapshot = snapshot
                    inspectTask = nil
                }
            } catch {
                await MainActor.run {
                    guard selectedImageReference == requestedReference else { return }
                    inspectSnapshot = nil
                    inspectError = error.localizedDescription
                    inspectTask = nil
                }
            }
        }
    }

    private func enqueueImageAction(
        title: String,
        summary: String,
        commandDescription: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        enqueueImageAction(title: title, commandDescription: commandDescription) { _ in
            try await operation()
            return ActivityOperationOutcome(summary: summary)
        }
    }

    private func enqueueImageAction(
        title: String,
        commandDescription: String,
        operation: @escaping @Sendable (_ activityID: UUID) async throws -> ActivityOperationOutcome
    ) {
        confirmationAction = nil
        lastError = nil

        _ = appModel.enqueueActivity(
            title: title,
            section: .images,
            kind: .image,
            commandDescription: commandDescription
        ) { activityID in
            do {
                let outcome = try await operation(activityID)
                await refreshImageSummary()
                return outcome
            } catch let error as AppError {
                await refreshImageSummary()
                throw error
            } catch {
                await refreshImageSummary()
                throw AppError.commandLaunchFailed(command: commandDescription, reason: error.localizedDescription)
            }
        }
    }

    private func refreshImageSummary() async {
        if let result = try? await containerCLIAdapter.listImages() {
            if case .parsed(let value, _) = result {
                appModel.cachedImageItems = value
            }
            appModel.updateImageSummary(from: result)
        }
        appModel.bumpRefreshRevision(for: .images)
    }

    private func loadImageArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.archive]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        enqueueImageAction(
            title: "Load image archive \(url.lastPathComponent)",
            summary: "Loaded image archive \(url.lastPathComponent).",
            commandDescription: loadImagesCommandDescription(inputPath: url.path)
        ) {
            try await containerCLIAdapter.loadImages(inputPath: url.path)
        }
    }

    private func saveSelectedImages() {
        let references = Array(selectedImageReferences).sorted()
        guard !references.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.archive]
        panel.nameFieldStringValue = "container-images.tar"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let platform: String?
        if let selected = selectedImageReference,
            let snapshot = inspectSnapshot,
            snapshot.reference == selected
        {
            platform = platformDescription(for: snapshot)
        } else {
            platform = nil
        }

        enqueueImageAction(
            title: "Save \(references.count) image(s)",
            summary: "Saved \(references.count) image(s) to \(url.lastPathComponent).",
            commandDescription: saveImagesCommandDescription(
                references: references,
                outputPath: url.path,
                platform: platform
            )
        ) {
            try await containerCLIAdapter.saveImages(
                references: references,
                outputPath: url.path,
                platform: platform
            )
        }
    }

    private func copyInspectJSON() {
        guard let json = inspectSnapshot?.rawJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func cancelRunningTask() {
        if isLoading {
            listTask?.cancel()
            isLoading = false
            listTask = nil
        } else {
            appModel.cancelLatestActiveActivity(in: .images)
        }
    }

    private func confirmationMessage(for action: ImageConfirmationAction) -> String {
        switch action {
        case .delete(_, let count):
            "This removes \(count == 1 ? "the selected image" : "the selected images")."
        case .pruneUnused:
            "This removes unused images via `container image prune --all`."
        }
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    private func platformDescription(for snapshot: ImageInspectSnapshot) -> String {
        let os = snapshot.operatingSystem ?? "unknown-os"
        let arch = snapshot.architecture ?? "unknown-arch"
        return "\(os)/\(arch)"
    }
}

private enum ImageConfirmationAction: Identifiable {
    case delete(references: [String], count: Int)
    case pruneUnused

    var id: String {
        switch self {
        case .delete(let references, _):
            "delete-\(references.joined(separator: "-"))"
        case .pruneUnused:
            "prune-unused"
        }
    }
}

private struct ImageRow: Identifiable, Hashable {
    let item: ImageListItem

    var id: String { item.reference }
    var reference: String { item.reference }
    var sizeDisplay: String { item.size ?? "Unknown" }
    var shortID: String { item.id }
    var searchBlob: String { "\(item.reference) \(item.id)".lowercased() }
}
