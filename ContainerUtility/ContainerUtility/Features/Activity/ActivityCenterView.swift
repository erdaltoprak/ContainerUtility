import AppKit
import SwiftUI

struct ActivityCenterView: View {
    @Environment(AppModel.self) private var appModel

    @State private var searchText = ""
    @State private var filterStatus: ActivityStatusFilter = .all
    @State private var sortOrder: [KeyPathComparator<ActivityRow>] = [KeyPathComparator(\.queuedAt, order: .reverse)]
    @State private var selectedActivityIDs = Set<UUID>()
    @State private var showInspector = true

    var body: some View {
        HSplitView {
            mainPane
                .frame(minWidth: 460, idealWidth: 620)
                .background(.background)

            if showInspector {
                inspectorPane
                    .frame(minWidth: 340, idealWidth: 430, maxWidth: 560)
                    .background(.background)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Picker("Status", selection: $filterStatus) {
                    ForEach(ActivityStatusFilter.allCases) { filter in
                        Text(filter.title)
                            .tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Button {
                    appModel.clearCompletedActivities()
                } label: {
                    Label("Clear Finished", systemImage: "xmark.bin")
                }
                .disabled(!hasCompletedActivities)
                .keyboardShortcut("k", modifiers: .command)
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
        .task {
            pruneSelection()
        }
        .onChange(of: filteredRows.map(\.id)) { _, _ in
            pruneSelection()
        }
        .onChange(of: selectedActivityIDs) { _, newValue in
            if newValue.count == 1 && !showInspector {
                showInspector = true
            }
        }
        .navigationTitle("")
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            listHeaderBar

            Divider()

            if filteredRows.isEmpty {
                emptyListState
            } else {
                activityTable
            }
        }
    }

    private var listHeaderBar: some View {
        HStack {
            Text(listPanelSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !selectedActivityIDs.isEmpty {
                Text("\(selectedActivityIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var activityTable: some View {
        Table(of: ActivityRow.self, selection: $selectedActivityIDs, sortOrder: $sortOrder) {
            TableColumn("Operation", value: \.title) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(row.commandPreview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Status", value: \.statusSortKey) { row in
                HStack(spacing: 4) {
                    Circle()
                        .fill(row.statusColor)
                        .frame(width: 8, height: 8)
                    Text(row.statusText)
                        .foregroundStyle(row.statusColor)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn("Section", value: \.sectionTitle) { row in
                Text(row.sectionTitle)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Queued", value: \.queuedAt) { row in
                Text(row.queuedDisplay)
                    .foregroundStyle(.secondary)
            }
            .width(min: 115, ideal: 145)

            TableColumn("Duration", value: \.durationSortKey) { row in
                Text(row.durationDisplay)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
        } rows: {
            ForEach(filteredRows) { row in
                TableRow(row)
                    .contextMenu {
                        if row.record.canRetry {
                            Button("Retry") {
                                appModel.retryActivity(row.id)
                            }
                        }
                        if row.record.status.isActive {
                            Button("Cancel") {
                                appModel.cancelActivity(id: row.id)
                            }
                        }
                        Button("Copy Command") {
                            copyToPasteboard(row.record.commandDescription)
                        }
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var emptyListState: some View {
        ContentUnavailableView {
            Label("No Operations", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Operations from diagnostics and runtime changes appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPane: some View {
        Group {
            if let activity = selectedActivity {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        inspectorSummarySection(activity: activity)
                        inspectorCommandSection(activity: activity)
                        inspectorOutputSection(activity: activity)
                    }
                    .padding(12)
                }
            } else {
                ResourceInspectorStateView(
                    descriptor: ResourceInspectorStateDescriptor(
                        title: "No Operation Selected",
                        message: "Select an operation to inspect details and output.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                )
            }
        }
    }

    private func inspectorSummarySection(activity: ActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: activity.status))
                        .frame(width: 8, height: 8)
                    Text(statusText(for: activity.status))
                        .foregroundStyle(statusColor(for: activity.status))
                }
            }

            LabeledContent("Section") {
                Text(activity.section.title)
            }

            LabeledContent("Queued") {
                Text(formatDate(activity.queuedAt))
            }

            LabeledContent("Started") {
                Text(formatDate(activity.startedAt))
            }

            LabeledContent("Finished") {
                Text(formatDate(activity.finishedAt))
            }

            if let summary = activity.summary, !summary.isEmpty {
                LabeledContent("Summary") {
                    Text(summary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let errorMessage = activity.errorMessage, !errorMessage.isEmpty {
                LabeledContent("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func inspectorCommandSection(activity: ActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Command")
                .font(.headline)

            Text(activity.commandDescription)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inspectorOutputSection(activity: ActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output")
                .font(.headline)

            if activity.outputLog.isEmpty {
                Text("No output captured for this operation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(activity.outputLog)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var activityRows: [ActivityRow] {
        appModel.activities.map(ActivityRow.init)
    }

    private var filteredRows: [ActivityRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var rows = activityRows.filter { row in
            switch filterStatus {
            case .all:
                true
            case .running:
                row.record.status == .running
            case .queued:
                row.record.status == .queued
            case .succeeded:
                row.record.status == .succeeded
            case .failed:
                row.record.status == .failed
            case .canceled:
                row.record.status == .canceled
            }
        }

        if !query.isEmpty {
            rows = rows.filter { $0.searchBlob.contains(query) }
        }

        rows.sort(using: sortOrder)
        return rows
    }

    private var selectedActivity: ActivityRecord? {
        guard selectedActivityIDs.count == 1, let selectedID = selectedActivityIDs.first else { return nil }
        return appModel.activities.first(where: { $0.id == selectedID })
    }

    private var hasCompletedActivities: Bool {
        appModel.activities.contains { !$0.status.isActive }
    }

    private var activeCount: Int {
        appModel.activities.filter { $0.status.isActive }.count
    }

    private var failedCount: Int {
        appModel.activities.filter { $0.status == .failed }.count
    }

    private var listPanelSubtitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filterStatus != .all {
            return "Showing \(filteredRows.count) of \(activityRows.count) operations."
        }
        return "\(activityRows.count) this session • \(activeCount) active • \(failedCount) failed"
    }

    private func pruneSelection() {
        let validIDs = Set(filteredRows.map(\.id))
        selectedActivityIDs = selectedActivityIDs.intersection(validIDs)
    }

    private var hasInspectorContent: Bool {
        selectedActivity != nil
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
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

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private enum ActivityStatusFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case queued
    case succeeded
    case failed
    case canceled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .running:
            "Running"
        case .queued:
            "Queued"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .canceled:
            "Canceled"
        }
    }
}

private struct ActivityRow: Identifiable, Hashable {
    let record: ActivityRecord

    var id: UUID { record.id }
    var title: String { record.title }
    var commandPreview: String { record.commandDescription }
    var sectionTitle: String { record.section.title }
    var queuedAt: Date { record.queuedAt }
    var queuedDisplay: String { record.queuedAt.formatted(date: .abbreviated, time: .shortened) }

    var statusSortKey: String {
        switch record.status {
        case .running:
            "0"
        case .queued:
            "1"
        case .failed:
            "2"
        case .canceled:
            "3"
        case .succeeded:
            "4"
        }
    }

    var statusText: String {
        switch record.status {
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

    var statusColor: Color {
        switch record.status {
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

    var durationSortKey: TimeInterval {
        let end = record.finishedAt ?? Date.now
        return end.timeIntervalSince(record.startedAt ?? record.queuedAt)
    }

    var durationDisplay: String {
        let duration = durationSortKey
        if duration < 1 {
            return "<1s"
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }

    var searchBlob: String {
        [
            record.title,
            record.commandDescription,
            record.section.title,
            record.summary ?? "",
            record.errorMessage ?? "",
            statusText,
        ]
        .joined(separator: " ")
        .lowercased()
    }
}
