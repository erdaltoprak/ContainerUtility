import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(.showSidebarBadgesKey) private var showSidebarBadges = true

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            List(SidebarSection.allCases, selection: $appModel.selectedSidebarSection) { section in
                sidebarRow(for: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: Layout.sidebarMinWidth,
                ideal: Layout.sidebarIdealWidth,
                max: Layout.sidebarMaxWidth
            )
            .navigationTitle("ContainerUtility")
        } detail: {
            sectionContent(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedSection.title)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sidebarRow(for section: SidebarSection) -> some View {
        if section == .system {
            Label(section.title, systemImage: section.systemImage)
                .badge(systemSidebarBadge)
                .accessibilityLabel("\(section.title), \(systemSidebarStatusLabel)")
        } else if showSidebarBadges {
            if section == .registries {
                Label(section.title, systemImage: section.systemImage)
                    .badge(Text("\(appModel.registrySessionCount)"))
            } else {
                Label(section.title, systemImage: section.systemImage)
                    .badge(appModel.badgeCount(for: section))
            }
        } else {
            Label(section.title, systemImage: section.systemImage)
        }
    }

    private var systemSidebarBadge: Text {
        Text("\u{25CF}")
            .foregroundStyle(systemSidebarStatusColor)
            .bold()
    }

    private var systemSidebarStatusColor: Color {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return .secondary
        }

        switch snapshot.compatibilityReport.state {
        case .unsupported, .unavailable:
            return .red
        case .supported:
            switch snapshot.engineState {
            case .running:
                return .green
            case .stopped:
                return .orange
            case .unknown:
                return .secondary
            }
        }
    }

    private var systemSidebarStatusLabel: String {
        if appModel.hasActiveActivity(for: .system) {
            return "Updating"
        }

        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "Unknown"
        }

        switch snapshot.compatibilityReport.state {
        case .unsupported:
            return "Unsupported"
        case .unavailable:
            return "Unavailable"
        case .supported:
            switch snapshot.engineState {
            case .running:
                return "Running"
            case .stopped:
                return "Stopped"
            case .unknown:
                return "Unknown"
            }
        }
    }

    @ViewBuilder
    private func sectionContent(for section: SidebarSection) -> some View {
        switch section {
        case .home:
            HomeView()
        case .system:
            SystemOverviewView()
        case .containers:
            ContainersView()
        case .images:
            ImagesView()
        case .networks:
            NetworksView()
        case .registries:
            RegistriesView()
        case .volumes:
            VolumesView()
        case .activity:
            ActivityCenterView()
        case .diagnostics:
            DiagnosticsView()
        }
    }

    private var selectedSection: SidebarSection {
        appModel.selectedSidebarSection ?? .home
    }
}

private enum Layout {
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 300
}

private struct SystemOverviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.containerCLIAdapter) private var containerCLIAdapter

    @State private var isChecking = false
    @State private var snapshot: SystemHealthSnapshot?
    @State private var task: Task<Void, Never>?
    @State private var activeRefreshID = UUID()

    var body: some View {
        Group {
            if case .unsupported(let reason) = snapshot?.compatibilityReport.state {
                UnsupportedVersionView(
                    reason: reason,
                    currentVersion: snapshot?.compatibilityReport.currentVersion,
                    supportedRange: snapshot?.compatibilityReport.policy.supportedRangeDescription ?? "Unknown",
                    onRefresh: refreshHealth
                )
            } else if snapshot == nil {
                ProgressView("Loading system health\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dashboardContent
            }
        }
        .onAppear {
            if snapshot == nil, let cachedSnapshot = appModel.latestSystemHealthSnapshot {
                snapshot = cachedSnapshot
            }
        }
        .task {
            if snapshot == nil, let cachedSnapshot = appModel.latestSystemHealthSnapshot {
                snapshot = cachedSnapshot
            }
            refreshHealth()
        }
        .onChange(of: appModel.refreshRevision(for: .system)) { _, _ in
            guard !isChecking else { return }
            refreshHealth()
        }
        .onChange(of: appModel.latestSystemHealthUpdatedAt) { _, _ in
            guard let cachedSnapshot = appModel.latestSystemHealthSnapshot else { return }
            snapshot = cachedSnapshot
        }
        .onDisappear {
            cancelRefreshTask()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                systemToolbarButtons
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings (⌘,)")
            }
        }
    }

    // MARK: - Header

    private var headerSubtitle: String {
        guard let snapshot else {
            return "Review runtime health, verify compatibility, and manage the container engine."
        }
        let version = snapshot.cliVersionDisplay ?? "Unknown"
        return
            "\(runtimeStateText(snapshot.engineState)) runtime \u{2022} \(snapshot.preflightChecks.count) preflight checks \u{2022} \(version)"
    }

    // MARK: - Dashboard

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                runtimeCard
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)

                preflightCard

                if let guidance = snapshot?.installGuidance {
                    installGuidanceCard(guidance)
                }

                if let guidance = snapshot?.managementGuidance {
                    managementGuidanceCard(guidance)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runtimeCard: some View {
        cardContainer(
            title: "Runtime",
            subtitle: headerSubtitle,
            systemImage: "server.rack"
        ) {
            systemInfoRow("Runtime State") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(runtimeStateColor(snapshot?.engineState))
                        .frame(width: 8, height: 8)
                    Text(runtimeStateText(snapshot?.engineState))
                        .foregroundStyle(runtimeStateColor(snapshot?.engineState))
                }
            }
            systemInfoRow("Install Source") {
                Text(snapshot?.installSource?.displayName ?? "Not installed")
                    .foregroundStyle(snapshot?.installSource == nil ? .secondary : .primary)
            }
            systemInfoRow("CLI Version") {
                Text(snapshot?.cliVersionDisplay ?? "Unavailable")
                    .font(.system(.callout, design: .monospaced))
            }
            systemInfoRow("Executable Path") {
                Text(snapshot?.executablePath ?? "Not found")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(snapshot?.executablePath == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if let detail = snapshot?.engineStatusDetail, !detail.isEmpty {
                systemInfoRow("Status Detail") {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if isBusy {
                Divider()

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isChecking ? "Refreshing system health…" : "Applying runtime change…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let latest = appModel.latestActivity(for: .system), latest.status.isActive {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(latest.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var preflightCard: some View {
        cardContainer(
            title: "Startup Preflight",
            subtitle: "Checks that validate CLI compatibility and engine readiness.",
            systemImage: "checklist"
        ) {
            HStack(spacing: 8) {
                statusPill(title: "\(passCount) pass", color: .green)
                statusPill(title: "\(warningCount) warning", color: .orange)
                statusPill(title: "\(failureCount) fail", color: .red)
                Spacer()
            }

            if let snapshot {
                ForEach(snapshot.preflightChecks) { check in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: iconName(for: check.severity))
                            .foregroundStyle(iconColor(for: check.severity))
                            .font(.callout)
                            .frame(width: 18, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.callout.weight(.medium))
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Checks Not Loaded",
                    systemImage: "checklist",
                    description: Text("Run refresh to collect compatibility and engine health details.")
                )
            }
        }
    }

    private func installGuidanceCard(_ guidance: InstallGuidance) -> some View {
        cardContainer(
            title: "Install Guidance",
            subtitle: "Recommended installation and update paths.",
            systemImage: "square.and.arrow.down"
        ) {
            installGuidanceContent(guidance)
        }
    }

    private func managementGuidanceCard(_ guidance: ManagementGuidance) -> some View {
        cardContainer(
            title: "Detected Install Path",
            subtitle: "Commands relevant to your current installation source.",
            systemImage: "folder.badge.gearshape"
        ) {
            managementGuidanceContent(guidance)
        }
    }

    private func cardContainer<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func systemInfoRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
    }

    private var passCount: Int {
        snapshot?.preflightChecks.filter { $0.severity == .pass }.count ?? 0
    }

    private var warningCount: Int {
        snapshot?.preflightChecks.filter { $0.severity == .warning }.count ?? 0
    }

    private var failureCount: Int {
        snapshot?.preflightChecks.filter { $0.severity == .failure }.count ?? 0
    }

    @ViewBuilder
    private func installGuidanceContent(_ guidance: InstallGuidance) -> some View {
        Text(guidance.summary)
            .font(.callout)
            .foregroundStyle(.secondary)

        ForEach(guidance.approaches) { approach in
            VStack(alignment: .leading, spacing: 8) {
                Text(approach.recommended ? "\(approach.title) (Recommended)" : approach.title)
                    .font(.headline)
                Text(approach.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(Array(approach.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.callout)
                }

                ForEach(approach.commands, id: \.self) { command in
                    CommandSnippet(text: command)
                }
            }
        }
    }

    @ViewBuilder
    private func managementGuidanceContent(_ guidance: ManagementGuidance) -> some View {
        Text(guidance.summary)
            .font(.callout)
            .foregroundStyle(.secondary)

        ForEach(Array(guidance.steps.enumerated()), id: \.offset) { index, step in
            Text("\(index + 1). \(step)")
                .font(.callout)
        }

        ForEach(guidance.commands, id: \.self) { command in
            CommandSnippet(text: command)
        }
    }

    // MARK: - Helpers

    private var isBusy: Bool {
        isChecking || appModel.hasActiveActivity(for: .system)
    }

    private var systemToolbarButtons: some View {
        HStack(spacing: 6) {
            if snapshot?.engineState == .running {
                Button {
                    stopEngine()
                } label: {
                    toolbarButtonLabel("Stop Engine", systemImage: "stop.fill")
                }
                .disabled(isBusy || snapshot?.executablePath == nil)
                .help("Stop Engine")
            } else {
                Button {
                    startEngine()
                } label: {
                    toolbarButtonLabel("Start Engine", systemImage: "play.fill")
                }
                .disabled(isBusy || snapshot?.executablePath == nil)
                .help("Start Engine")
            }

            Button {
                refreshHealth()
            } label: {
                toolbarButtonLabel("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy)
            .help("Refresh System Health (\u{2318}R)")
            .keyboardShortcut("r", modifiers: .command)

            if isBusy {
                Button(role: .cancel) {
                    cancelRunningTask()
                } label: {
                    toolbarButtonLabel("Cancel", systemImage: "xmark")
                }
                .help("Cancel Current Operation")
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func toolbarButtonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
    }

    private func runtimeStateText(_ state: EngineRuntimeState?) -> String {
        switch state {
        case .running: "Running"
        case .stopped: "Stopped"
        case .unknown, .none: "Unknown"
        }
    }

    private func runtimeStateColor(_ state: EngineRuntimeState?) -> Color {
        switch state {
        case .running: .green
        case .stopped: .orange
        case .unknown, .none: .secondary
        }
    }

    private func iconName(for severity: StartupPreflightCheck.Severity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private func iconColor(for severity: StartupPreflightCheck.Severity) -> Color {
        switch severity {
        case .pass: .green
        case .warning: .orange
        case .failure: .red
        }
    }

    // MARK: - Actions

    private func refreshHealth() {
        task?.cancel()

        let refreshID = UUID()
        activeRefreshID = refreshID
        isChecking = true

        task = Task {
            let healthSnapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
            await MainActor.run {
                guard activeRefreshID == refreshID, !Task.isCancelled else { return }
                snapshot = healthSnapshot
                appModel.latestSystemHealthSnapshot = healthSnapshot
                appModel.latestSystemHealthUpdatedAt = .now
                isChecking = false
                task = nil
            }
        }
    }

    private func startEngine() {
        runEngineAction(isStarting: true) {
            try await containerCLIAdapter.startSystem()
        }
    }

    private func stopEngine() {
        runEngineAction(isStarting: false) {
            try await containerCLIAdapter.stopSystem()
        }
    }

    private func runEngineAction(
        isStarting: Bool,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let title = isStarting ? "Start engine" : "Stop engine"
        let summary = isStarting ? "Started engine." : "Stopped engine."
        let commandDescription = isStarting ? "container system start" : "container system stop"
        let completionSummary = summary

        _ = appModel.enqueueActivity(
            title: title,
            section: .system,
            kind: .system,
            commandDescription: commandDescription
        ) { _ in
            do {
                try await operation()
                await refreshSystemSummary()
                return ActivityOperationOutcome(summary: completionSummary)
            } catch let error as AppError {
                await refreshSystemSummary()
                throw error
            } catch {
                await refreshSystemSummary()
                throw AppError.commandLaunchFailed(command: commandDescription, reason: error.localizedDescription)
            }
        }
    }

    private func cancelRunningTask() {
        if isChecking {
            cancelRefreshTask()
        } else {
            appModel.cancelLatestActiveActivity(in: .system)
        }
    }

    private func cancelRefreshTask() {
        activeRefreshID = UUID()
        task?.cancel()
        isChecking = false
        task = nil
    }

    private func refreshSystemSummary() async {
        let updatedSnapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
        await MainActor.run {
            snapshot = updatedSnapshot
            appModel.latestSystemHealthSnapshot = updatedSnapshot
            appModel.latestSystemHealthUpdatedAt = .now
        }
        appModel.bumpRefreshRevision(for: .system)
    }
}
// MARK: - Supporting Views

/// Inline copyable command snippet used in guidance sections.
private struct CommandSnippet: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct UnsupportedVersionView: View {
    let reason: String
    let currentVersion: String?
    let supportedRange: String
    let onRefresh: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Unsupported Version", systemImage: "exclamationmark.shield")
        } description: {
            VStack(spacing: 8) {
                Text(reason)
                    .multilineTextAlignment(.center)
                Text("Supported range: \(supportedRange)")
                    .foregroundStyle(.secondary)
                if let currentVersion {
                    Text("Detected version: \(currentVersion)")
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Recheck") {
                onRefresh()
            }
        }
    }
}

#Preview {
    let runner = CommandRunner()
    ContentView()
        .environment(AppModel())
        .environment(\.commandRunner, runner)
        .environment(\.containerCLIAdapter, ContainerCLIAdapter(commandRunner: runner))
}
