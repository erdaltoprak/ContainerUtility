import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContainerDetailWorkspaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    let container: ContainerListItem

    @State private var selectedTab = ContainerDetailTab.logs
    @State private var inspectSnapshot: ContainerInspectSnapshot?
    @State private var statsSample: ContainerStatsSample?
    @State private var logsText = ""
    @State private var logsSearchText = ""
    @State private var logTailLineCount = 200
    @State private var logStreamPaused = false
    @State private var statsStreamPaused = false
    @State private var execCommandText = "uname -a"
    @State private var execOutput = ""
    @State private var selectedExportDocument: TextExportDocument?
    @State private var isExportPresented = false
    @State private var isLoadingInspect = false
    @State private var isRunningExec = false
    @State private var inspectError: String?
    @State private var logsError: String?
    @State private var statsError: String?
    @State private var execError: String?
    @State private var lastLogsUpdateAt: Date?
    @State private var lastStatsUpdateAt: Date?
    @State private var logsTask: Task<Void, Never>?
    @State private var statsTask: Task<Void, Never>?
    @State private var inspectTask: Task<Void, Never>?
    @State private var execTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileExporter(
            isPresented: $isExportPresented,
            document: selectedExportDocument,
            contentType: .json,
            defaultFilename: "\(container.id)-inspect"
        ) { _ in
            selectedExportDocument = nil
        }
        .task(id: container.id) {
            reloadInspect()
            if selectedTab == .logs, !logStreamPaused {
                restartLogsStream()
            }
            if selectedTab == .stats, !statsStreamPaused, container.isRunning {
                restartStatsStream()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .logs {
                cancelLogsStream()
            }
            if newTab != .stats {
                cancelStatsStream()
            }

            switch newTab {
            case .logs:
                if !logStreamPaused {
                    restartLogsStream()
                }
            case .stats:
                if !statsStreamPaused, container.isRunning {
                    restartStatsStream()
                }
            case .inspect:
                if inspectSnapshot == nil {
                    reloadInspect()
                }
            case .exec:
                break
            }
        }
        .onChange(of: logTailLineCount) { _, _ in
            if selectedTab == .logs, !logStreamPaused {
                restartLogsStream()
            }
        }
        .background(hiddenShortcutButtons)
        .onDisappear {
            cancelAllTasks()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.headline)
                    Text(container.imageDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                ResourceTag(
                    title: container.stateDisplay,
                    color: container.isRunning ? .green : .secondary
                )
            }

            Picker("", selection: $selectedTab) {
                ForEach(ContainerDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                        .disabled(tab == .exec && !container.isRunning)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .onAppear {
            if !container.isRunning && selectedTab == .exec {
                selectedTab = .logs
            }
        }
        .onChange(of: container.isRunning) { _, isRunning in
            if !isRunning && selectedTab == .exec {
                selectedTab = .logs
            }
            if !isRunning {
                cancelStatsStream()
            } else if selectedTab == .stats, !statsStreamPaused {
                restartStatsStream()
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .logs:
            logsTab
        case .inspect:
            inspectTab
        case .stats:
            statsTab
        case .exec:
            execTab
        }
    }

    // MARK: - Logs Tab

    private var logsTab: some View {
        VStack(spacing: 0) {
            logsControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ResourceMonospacedOutput(
                text: filteredLogsText,
                placeholder: "No logs yet."
            )
        }
    }

    private var logsControlBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Stepper("Tail \(logTailLineCount)", value: $logTailLineCount, in: 20 ... 500, step: 20)
                    .frame(minWidth: 110)

                TextField("Search", text: $logsSearchText)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                HStack(spacing: 4) {
                    Button(
                        logStreamPaused ? "Resume Log Stream" : "Pause Log Stream",
                        systemImage: logStreamPaused ? "play.fill" : "pause.fill",
                        action: toggleLogsStream
                    )
                    .labelStyle(.iconOnly)
                    .help(logStreamPaused ? "Resume" : "Pause")

                    Button("Restart Log Stream", systemImage: "arrow.clockwise", action: restartLogsStream)
                        .labelStyle(.iconOnly)
                        .help("Restart")

                    Button("Stop Log Stream", systemImage: "xmark", action: stopLogsStreamManually)
                        .labelStyle(.iconOnly)
                        .help("Cancel")
                }
                .controlSize(.small)
            }

            streamStatusRow(
                status: logStreamStatus,
                lastUpdated: lastLogsUpdateAt,
                error: logsError
            )
        }
    }

    // MARK: - Inspect Tab

    private var inspectTab: some View {
        Group {
            if isLoadingInspect && inspectSnapshot == nil && inspectError == nil {
                ResourceInspectorLoadingView(title: "Loading inspect output\u{2026}")
            } else if let inspectError, inspectSnapshot == nil {
                ResourceInspectorStateView(
                    descriptor: resourceInspectorFailureDescriptor(
                        resourceName: "container",
                        error: inspectError,
                        systemHealth: appModel.latestSystemHealthSnapshot
                    )
                )
            } else {
                VStack(spacing: 0) {
                    inspectControlBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let inspectSnapshot {
                                inspectSummarySection(snapshot: inspectSnapshot)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Inspect JSON")
                                        .font(.headline.weight(.medium))
                                        .padding(.horizontal, 12)

                                    ResourceMonospacedOutput(
                                        text: inspectSnapshot.rawJSON,
                                        placeholder: "Inspect output not loaded yet."
                                    )
                                    .frame(minHeight: 200)
                                }
                            } else {
                                ContentUnavailableView(
                                    "Inspect Not Loaded",
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text(
                                        "Reload the selected container to inspect its current configuration."
                                    )
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var inspectControlBar: some View {
        HStack(spacing: 8) {
            Button("Reload Inspect", systemImage: "arrow.clockwise", action: reloadInspect)
                .labelStyle(.iconOnly)
                .help("Reload")

            Button("Copy Inspect JSON", systemImage: "doc.on.doc", action: copyInspectJSON)
                .labelStyle(.iconOnly)
                .disabled(inspectSnapshot == nil)
                .help("Copy JSON")

            Button("Export Inspect JSON", systemImage: "square.and.arrow.up", action: exportInspectJSON)
                .labelStyle(.iconOnly)
                .disabled(inspectSnapshot == nil)
                .help("Export JSON")

            Spacer()
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func inspectSummarySection(snapshot: ContainerInspectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.headline.weight(.medium))
                .padding(.horizontal, 12)

            Form {
                LabeledContent("Image", value: snapshot.imageReference ?? "Unknown")
                LabeledContent("Hostname", value: snapshot.hostname ?? "Unknown")
                LabeledContent("Address", value: snapshot.networkAddress ?? "Unknown")
                LabeledContent("Command", value: snapshot.command ?? "Unknown")
                LabeledContent("CPUs", value: snapshot.cpuCount.map(String.init) ?? "Unknown")
                LabeledContent("Memory", value: snapshot.memoryBytes.map(formatBytes) ?? "Unknown")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        VStack(spacing: 0) {
            statsControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let statsSample {
                        statsSection(sample: statsSample)
                    } else {
                        ContentUnavailableView("No stats sample yet", systemImage: "chart.xyaxis.line")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var statsControlBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Button(
                    statsStreamPaused ? "Resume Stats Stream" : "Pause Stats Stream",
                    systemImage: statsStreamPaused ? "play.fill" : "pause.fill",
                    action: toggleStatsStream
                )
                .labelStyle(.iconOnly)
                .help(statsStreamPaused ? "Resume" : "Pause")

                Button("Restart Stats Stream", systemImage: "arrow.clockwise", action: restartStatsStream)
                    .labelStyle(.iconOnly)
                    .help("Restart")

                Button("Stop Stats Stream", systemImage: "xmark", action: stopStatsStreamManually)
                    .labelStyle(.iconOnly)
                    .help("Cancel")

                Spacer()
            }
            .controlSize(.small)

            streamStatusRow(
                status: statsStreamStatus,
                lastUpdated: lastStatsUpdateAt,
                error: statsError
            )
        }
    }

    @ViewBuilder
    private func statsSection(sample: ContainerStatsSample) -> some View {
        Form {
            LabeledContent("CPU usage", value: sample.cpuUsageUsec.map { "\($0) \u{00B5}s" } ?? "Unknown")
            LabeledContent("Memory usage", value: sample.memoryUsageBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Memory limit", value: sample.memoryLimitBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Network RX", value: sample.networkRxBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Network TX", value: sample.networkTxBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Block read", value: sample.blockReadBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Block write", value: sample.blockWriteBytes.map(formatBytes) ?? "Unknown")
            LabeledContent("Processes", value: sample.processCount.map(String.init) ?? "Unknown")
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    // MARK: - Exec Tab

    private var execTab: some View {
        VStack(spacing: 0) {
            execControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ResourceMonospacedOutput(
                text: execOutput,
                placeholder: "Run a command to capture output."
            )
        }
    }

    private var execControlBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Command", text: $execCommandText)
                    .textFieldStyle(.roundedBorder)

                Button("Run Command", systemImage: "play.fill", action: runExec)
                    .labelStyle(.iconOnly)
                    .disabled(isRunningExec)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Run")

                Button("Copy Interactive Shell Command", systemImage: "doc.on.doc", action: copyInteractiveShellCommand)
                    .labelStyle(.iconOnly)
                    .help("Copy Cmd")

                Button("Copy Command Output", systemImage: "doc.on.clipboard", action: copyExecOutput)
                    .labelStyle(.iconOnly)
                    .disabled(execOutput.isEmpty)
                    .help("Copy Output")

                Spacer()
            }
            .controlSize(.small)

            if let execError {
                Text(execError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isRunningExec {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func streamStatusRow(
        status: StreamStatus,
        lastUpdated: Date?,
        error: String?
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(status.color)

            if let lastUpdated {
                Text(lastUpdated.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var logStreamStatus: StreamStatus {
        if logStreamPaused {
            return .paused("Updates paused")
        }
        if logsTask == nil {
            return .inactive("Polling stopped")
        }
        if container.isRunning {
            return .active("Watching live logs")
        }
        return .inactive("Showing saved logs")
    }

    private var statsStreamStatus: StreamStatus {
        if statsStreamPaused {
            return .paused("Updates paused")
        }
        if statsTask == nil {
            return .inactive("Polling stopped")
        }
        if container.isRunning {
            return .active("Polling stats")
        }
        return .inactive("Container stopped")
    }

    private var filteredLogsText: String {
        let source = logsText.isEmpty ? "No logs yet." : logsText
        let search = logsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return source }

        let filtered =
            source
            .split(whereSeparator: \.isNewline)
            .filter { $0.localizedCaseInsensitiveContains(search) }
            .joined(separator: "\n")

        return filtered.isEmpty ? "No log lines match '\(logsSearchText)'." : filtered
    }

    // MARK: - Actions

    private func reloadInspect() {
        inspectTask?.cancel()
        isLoadingInspect = true
        inspectError = nil

        inspectTask = Task {
            do {
                let snapshot = try await containerCLIAdapter.inspectContainer(id: container.id)
                await MainActor.run {
                    inspectSnapshot = snapshot
                    isLoadingInspect = false
                    inspectTask = nil
                }
            } catch {
                await MainActor.run {
                    inspectError = error.localizedDescription
                    isLoadingInspect = false
                    inspectTask = nil
                }
            }
        }
    }

    private func restartLogsStream() {
        cancelLogsStream()
        logStreamPaused = false
        logsError = nil

        logsTask = Task {
            while !Task.isCancelled {
                do {
                    let output = try await containerCLIAdapter.fetchContainerLogs(
                        id: container.id,
                        tail: logTailLineCount
                    )
                    await MainActor.run {
                        logsText = output
                        logsError = nil
                        lastLogsUpdateAt = .now
                    }
                } catch {
                    await MainActor.run {
                        logsError = error.localizedDescription
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    private func toggleLogsStream() {
        if logStreamPaused {
            restartLogsStream()
        } else {
            logStreamPaused = true
            cancelLogsStream()
        }
    }

    private func cancelLogsStream() {
        logsTask?.cancel()
        logsTask = nil
    }

    private func stopLogsStreamManually() {
        logStreamPaused = true
        cancelLogsStream()
    }

    private func restartStatsStream() {
        cancelStatsStream()
        statsStreamPaused = false
        statsError = nil

        statsTask = Task {
            while !Task.isCancelled {
                do {
                    let sample = try await containerCLIAdapter.fetchContainerStats(id: container.id)
                    await MainActor.run {
                        statsSample = sample
                        statsError = sample == nil ? "No stats sample returned." : nil
                        lastStatsUpdateAt = .now
                    }
                } catch {
                    await MainActor.run {
                        statsError = error.localizedDescription
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    private func toggleStatsStream() {
        if statsStreamPaused {
            restartStatsStream()
        } else {
            statsStreamPaused = true
            cancelStatsStream()
        }
    }

    private func cancelStatsStream() {
        statsTask?.cancel()
        statsTask = nil
    }

    private func stopStatsStreamManually() {
        statsStreamPaused = true
        cancelStatsStream()
    }

    private func runExec() {
        execTask?.cancel()
        execError = nil
        isRunningExec = true

        execTask = Task {
            do {
                let result = try await containerCLIAdapter.executeInContainer(
                    id: container.id,
                    commandText: execCommandText
                )
                let output = [result.stdout, result.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                await MainActor.run {
                    execOutput = output.isEmpty ? "(no output)" : output
                    isRunningExec = false
                    execTask = nil
                }
            } catch {
                await MainActor.run {
                    execError = error.localizedDescription
                    isRunningExec = false
                    execTask = nil
                }
            }
        }
    }

    private func copyInspectJSON() {
        guard let json = inspectSnapshot?.rawJSON else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    private func exportInspectJSON() {
        guard let json = inspectSnapshot?.rawJSON else { return }
        selectedExportDocument = TextExportDocument(text: json)
        isExportPresented = true
    }

    private func copyExecOutput() {
        guard !execOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(execOutput, forType: .string)
    }

    private func copyInteractiveShellCommand() {
        let command = "container exec -it \(container.id) /bin/sh"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func cancelAllTasks() {
        inspectTask?.cancel()
        logsTask?.cancel()
        statsTask?.cancel()
        execTask?.cancel()
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    private var hiddenShortcutButtons: some View {
        ZStack {
            Button("Logs") {
                selectedTab = .logs
            }
            .keyboardShortcut("1", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("Inspect") {
                selectedTab = .inspect
            }
            .keyboardShortcut("2", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("Stats") {
                selectedTab = .stats
            }
            .keyboardShortcut("3", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("Exec") {
                if container.isRunning {
                    selectedTab = .exec
                }
            }
            .keyboardShortcut("4", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .disabled(!container.isRunning)
        }
    }
}

private struct StreamStatus {
    let label: String
    let color: Color

    static func active(_ label: String) -> StreamStatus {
        StreamStatus(label: label, color: .green)
    }

    static func paused(_ label: String) -> StreamStatus {
        StreamStatus(label: label, color: .orange)
    }

    static func inactive(_ label: String) -> StreamStatus {
        StreamStatus(label: label, color: .secondary)
    }
}

private enum ContainerDetailTab: String, CaseIterable, Identifiable {
    case logs
    case inspect
    case stats
    case exec

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

private struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
