import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var bundleOptions = DiagnosticsBundleOptions()
    @State private var localErrorMessage: String?
    @State private var showInspector = true
    @State private var inspectorOutputTab: InspectorOutputTab = .summary

    var body: some View {
        HSplitView {
            mainPane
                .frame(minWidth: 500, idealWidth: 680)
                .background(.background)

            if showInspector {
                inspectorPane
                    .frame(minWidth: 340, idealWidth: 430, maxWidth: 560)
                    .background(.background)
            }
        }
        .toolbar {
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
        .navigationTitle("")
    }

    private var mainPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                exportActionsPanel
                bundleScopePanel
                aboutPanel
            }
            .padding(12)
        }
    }

    private var exportActionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Export Diagnostics")
                    .font(.headline)

                Spacer()

                if let updatedAt = appModel.latestDiagnosticsUpdatedAt {
                    Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Create a redacted support bundle or copy a troubleshooting summary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    exportSupportBundle()
                } label: {
                    Label("Export Bundle", systemImage: "shippingbox")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
                .help("Create a zip bundle with selected diagnostics data")

                Button {
                    copyRedactedSummary()
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }
                .disabled(isBusy)

                if appModel.latestDiagnosticsBundlePath != nil {
                    Button {
                        revealLastExport()
                    } label: {
                        Label("Reveal Last Export", systemImage: "folder")
                    }
                    .disabled(isBusy)
                }

                if isBusy {
                    Button("Cancel") {
                        appModel.cancelLatestActiveActivity(in: .diagnostics)
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }

            statusRow
        }
        .padding(12)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusRow: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Collecting diagnostics…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let localErrorMessage {
            Label(localErrorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let latestActivity {
            activityStatusView(latestActivity)
        }
    }

    private var bundleScopePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bundle Scope")
                    .font(.headline)

                Spacer()

                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle(
                    "All Inspects",
                    isOn: Binding(
                        get: { allInspectsSelected },
                        set: { newValue in
                            bundleOptions.includeContainerInspects = newValue
                            bundleOptions.includeImageInspects = newValue
                            bundleOptions.includeNetworkInspects = newValue
                            bundleOptions.includeVolumeInspects = newValue
                        }
                    )
                )
                .controlSize(.small)
                .toggleStyle(.switch)

                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Toggle("System version", isOn: $bundleOptions.includeSystemVersion)
                        .controlSize(.small)
                    Toggle("System status", isOn: $bundleOptions.includeSystemStatus)
                        .controlSize(.small)
                }

                GridRow {
                    Toggle("Disk usage", isOn: $bundleOptions.includeDiskUsage)
                        .controlSize(.small)
                    Toggle("System logs", isOn: $bundleOptions.includeSystemLogs)
                        .controlSize(.small)
                }

                GridRow {
                    Toggle("Recent operations", isOn: $bundleOptions.includeRecentOperations)
                        .controlSize(.small)
                }

                GridRow {
                    Toggle("Container inspects", isOn: $bundleOptions.includeContainerInspects)
                        .controlSize(.small)
                    Toggle("Image inspects", isOn: $bundleOptions.includeImageInspects)
                        .controlSize(.small)
                }

                GridRow {
                    Toggle("Network inspects", isOn: $bundleOptions.includeNetworkInspects)
                        .controlSize(.small)
                    Toggle("Volume inspects", isOn: $bundleOptions.includeVolumeInspects)
                        .controlSize(.small)
                }
            }

            if bundleOptions.includeSystemLogs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Logs Window")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Picker("Window", selection: $bundleOptions.logWindow) {
                        ForEach(DiagnosticsLogWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How To Share Safely")
                .font(.headline)

            Text(
                "The exported bundle and copied summary are redacted for troubleshooting. Review contents before sharing externally."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("1. Select the data scope.")
                Text("2. Export a zip bundle or copy a summary.")
                Text("3. Attach the archive when reporting an issue.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var inspectorPane: some View {
        Group {
            if hasInspectorContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        resultOverviewSection

                        if let bundlePath = appModel.latestDiagnosticsBundlePath {
                            bundlePathSection(path: bundlePath)
                        }

                        inspectorOutputSection
                    }
                    .padding(12)
                }
            } else {
                ResourceInspectorStateView(
                    descriptor: ResourceInspectorStateDescriptor(
                        title: "No Diagnostics Output Yet",
                        message: "Run Export Bundle or Copy Summary to generate troubleshooting output.",
                        systemImage: "stethoscope"
                    )
                )
            }
        }
    }

    private var resultOverviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Latest Result")
                .font(.headline)

            if let updatedAt = appModel.latestDiagnosticsUpdatedAt {
                LabeledContent("Updated") {
                    Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let latestActivity {
                LabeledContent("Status") {
                    Text(statusText(for: latestActivity.status))
                        .foregroundStyle(statusColor(for: latestActivity.status))
                }

                if let summary = latestActivity.summary, !summary.isEmpty {
                    LabeledContent("Summary") {
                        Text(summary)
                    }
                }
            }
        }
    }

    private func bundlePathSection(path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Export")
                .font(.headline)

            Text(path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Reveal in Finder") {
                revealLastExport()
            }
            .controlSize(.small)
        }
    }

    private var inspectorOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostics Output")
                    .font(.headline)

                Spacer()

                if !inspectorOutputText.isEmpty {
                    Button {
                        copyText(inspectorOutputText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            Picker("Output", selection: $inspectorOutputTab) {
                ForEach(InspectorOutputTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Text(inspectorOutputText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var inspectorOutputText: String {
        switch inspectorOutputTab {
        case .summary:
            return appModel.latestDiagnosticsSummary
                ?? "Generate a diagnostics bundle or copy a summary to see output here."
        case .collectionLog:
            if let latestActivity {
                return latestActivity.outputLog.isEmpty
                    ? "No collection log output captured."
                    : latestActivity.outputLog
            }
            return "No collection log output captured."
        }
    }

    private func activityStatusView(_ activity: ActivityRecord) -> some View {
        HStack(spacing: 8) {
            switch activity.status {
            case .queued:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Queued: \(activity.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .running:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Running \(activity.title)...")
                    .font(.caption)

            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(activity.summary ?? "\(activity.title) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .failed, .canceled:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(activity.errorMessage ?? activity.summary ?? "\(activity.title) failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var latestActivity: ActivityRecord? {
        appModel.latestActivity(for: .diagnostics)
    }

    private var allInspectsSelected: Bool {
        bundleOptions.includeContainerInspects && bundleOptions.includeImageInspects
            && bundleOptions.includeNetworkInspects && bundleOptions.includeVolumeInspects
    }

    private var isBusy: Bool {
        appModel.hasActiveActivity(for: .diagnostics)
    }

    private var hasInspectorContent: Bool {
        appModel.latestDiagnosticsSummary != nil
            || appModel.latestDiagnosticsBundlePath != nil
            || latestActivity != nil
    }

    private var selectionSummary: String {
        let inspectGroups = [
            bundleOptions.includeContainerInspects,
            bundleOptions.includeImageInspects,
            bundleOptions.includeNetworkInspects,
            bundleOptions.includeVolumeInspects,
        ]
        .filter { $0 }.count

        let coreCount = [
            bundleOptions.includeSystemVersion,
            bundleOptions.includeSystemStatus,
            bundleOptions.includeDiskUsage,
            bundleOptions.includeSystemLogs,
            bundleOptions.includeRecentOperations,
        ]
        .filter { $0 }.count

        let coreLabel = coreCount == 1 ? "core item" : "core items"
        let inspectLabel = inspectGroups == 1 ? "inspect group" : "inspect groups"
        return "\(coreCount) \(coreLabel) • \(inspectGroups) \(inspectLabel)"
    }

    private func statusText(for status: ActivityOperationStatus) -> String {
        switch status {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .canceled:
            "Canceled"
        }
    }

    private func statusColor(for status: ActivityOperationStatus) -> Color {
        switch status {
        case .queued:
            .secondary
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        case .canceled:
            .orange
        }
    }

    private func exportSupportBundle() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = defaultArchiveName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        localErrorMessage = nil
        let options = bundleOptions

        _ = appModel.enqueueActivity(
            title: "Export support bundle",
            section: .diagnostics,
            kind: .diagnostics,
            commandDescription: "diagnostics export \(url.lastPathComponent)"
        ) { activityID in
            let operationSnapshot = await MainActor.run {
                appModel.makeDiagnosticsOperationSnapshot()
            }
            let collection = await DiagnosticsSupportBundleBuilder.collect(
                options: options,
                adapter: containerCLIAdapter,
                operationSnapshot: operationSnapshot
            ) { message in
                await MainActor.run {
                    appModel.appendActivityOutput(id: activityID, chunk: "\(message)\n")
                }
            }

            let exportTask = Task(priority: .utility) {
                try Task.checkCancellation()
                return try DiagnosticsSupportBundleBuilder.exportBundle(collection: collection, to: url)
            }
            let exportResult = try await withTaskCancellationHandler {
                try await exportTask.value
            } onCancel: {
                exportTask.cancel()
            }
            await MainActor.run {
                appModel.recordDiagnosticsBundleExport(
                    path: exportResult.archiveURL.path,
                    summary: exportResult.summary
                )
            }

            let warningSuffix = exportResult.warningCount > 0 ? " with \(exportResult.warningCount) warning(s)." : "."
            return ActivityOperationOutcome(
                summary: "Exported support bundle to \(url.lastPathComponent)\(warningSuffix)"
            )
        }
    }

    private func copyRedactedSummary() {
        localErrorMessage = nil
        let options = bundleOptions

        _ = appModel.enqueueActivity(
            title: "Copy redacted summary",
            section: .diagnostics,
            kind: .diagnostics,
            commandDescription: "diagnostics summary copy"
        ) { activityID in
            let operationSnapshot = await MainActor.run {
                appModel.makeDiagnosticsOperationSnapshot()
            }
            let collection = await DiagnosticsSupportBundleBuilder.collect(
                options: options,
                adapter: containerCLIAdapter,
                operationSnapshot: operationSnapshot
            ) { message in
                await MainActor.run {
                    appModel.appendActivityOutput(id: activityID, chunk: "\(message)\n")
                }
            }

            let summaryTask = Task(priority: .utility) {
                if Task.isCancelled { return "" }
                return DiagnosticsSupportBundleBuilder.makeRedactedSummary(from: collection)
            }
            let summary = await withTaskCancellationHandler {
                await summaryTask.value
            } onCancel: {
                summaryTask.cancel()
            }
            try Task.checkCancellation()
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary, forType: .string)
                appModel.recordDiagnosticsSummary(summary)
            }

            let warningSuffix = collection.warnings.isEmpty ? "." : " with \(collection.warnings.count) warning(s)."
            return ActivityOperationOutcome(summary: "Copied redacted troubleshooting summary\(warningSuffix)")
        }
    }

    private func revealLastExport() {
        guard let lastPath = appModel.latestDiagnosticsBundlePath else { return }
        let url = URL(fileURLWithPath: lastPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            localErrorMessage = "The last exported support bundle could not be found on disk."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyText(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var defaultArchiveName: String {
        let stamp = Date.now.formatted(.dateTime.year().month().day().hour().minute().second())
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "containerutility-support-\(stamp).zip"
    }
}

private enum InspectorOutputTab: String, CaseIterable, Identifiable {
    case summary
    case collectionLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            "Summary"
        case .collectionLog:
            "Collection Log"
        }
    }
}
