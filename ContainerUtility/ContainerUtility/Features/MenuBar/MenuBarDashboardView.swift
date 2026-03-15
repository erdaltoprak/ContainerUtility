import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private let refreshController: AppRefreshController

    init(refreshController: AppRefreshController) {
        self.refreshController = refreshController
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metricsGrid
            runtimeSection
            actionSection
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .task {
            refreshController.startIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ContainerUtility")
                    .font(.headline)
            }

            Spacer(minLength: 0)

            Button(action: refreshController.refreshNow) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
    }

    private var metricsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                sectionTile(
                    target: .containers,
                    title: "Containers",
                    value: "\(appModel.containers.count)",
                    detail: "\(runningContainerCount) running",
                    symbol: "shippingbox",
                    tint: .blue
                )

                sectionTile(
                    target: .images,
                    title: "Images",
                    value: "\(appModel.images.count)",
                    detail: "Local images",
                    symbol: "photo.stack",
                    tint: .indigo
                )
            }

            GridRow {
                sectionTile(
                    target: .networks,
                    title: "Networks",
                    value: "\(appModel.networks.count)",
                    detail: "\(attachedNetworkCount) attached",
                    symbol: "network",
                    tint: .cyan
                )

                sectionTile(
                    target: .volumes,
                    title: "Volumes",
                    value: "\(appModel.volumes.count)",
                    detail: "\(referencedVolumeCount) used",
                    symbol: "internaldrive",
                    tint: .mint
                )
            }
        }
    }

    private var runtimeSection: some View {
        Button {
            showMainWindow(selecting: .system)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Runtime", systemImage: "desktopcomputer")
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 0)

                    statusPill(title: engineStateDisplay, color: engineStateColor)
                }

                runtimeRow(label: "Preflight", value: preflightDisplay)
                runtimeRow(label: "Updated", value: systemHealthUpdatedDisplay)
                runtimeRow(label: "Operations", value: operationsDisplay)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show System")
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Show ContainerUtility", systemImage: "macwindow") {
                showMainWindow()
            }

            Button("Settings", systemImage: "gearshape") {
                showSettings()
            }

            Divider()

            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
    }

    private var runningContainerCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var attachedNetworkCount: Int {
        appModel.networks.filter { $0.attachedContainerCount > 0 }.count
    }

    private var referencedVolumeCount: Int {
        appModel.volumes.filter { $0.attachedContainerCount > 0 }.count
    }

    private var runningOperationCount: Int {
        appModel.activities.filter { $0.status == .running }.count
    }

    private var failedOperationCount: Int {
        appModel.activities.filter { $0.status == .failed }.count
    }

    private var engineStateDisplay: String {
        switch appModel.latestSystemHealthSnapshot?.engineState {
        case .running:
            "Running"
        case .stopped:
            "Stopped"
        case .unknown, .none:
            "Unknown"
        }
    }

    private var engineStateColor: Color {
        switch appModel.latestSystemHealthSnapshot?.engineState {
        case .running:
            .green
        case .stopped:
            .orange
        case .unknown, .none:
            .secondary
        }
    }

    private var preflightDisplay: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "Not checked yet"
        }

        let passCount = snapshot.preflightChecks.filter { $0.severity == .pass }.count
        let warningCount = snapshot.preflightChecks.filter { $0.severity == .warning }.count
        let failCount = snapshot.preflightChecks.filter { $0.severity == .failure }.count
        return "\(passCount) pass · \(warningCount) warning · \(failCount) fail"
    }

    private var systemHealthUpdatedDisplay: String {
        guard let timestamp = appModel.latestSystemHealthUpdatedAt else {
            return "No snapshot"
        }
        return timestamp.formatted(date: .omitted, time: .shortened)
    }

    private var operationsDisplay: String {
        "\(runningOperationCount) running · \(failedOperationCount) failed"
    }

    private func runtimeRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func sectionTile(
        target: SidebarSection,
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        Button {
            showMainWindow(selecting: target)
        } label: {
            MenuBarMetricTile(
                title: title,
                value: value,
                detail: detail,
                symbol: symbol,
                tint: tint
            )
        }
        .buttonStyle(.plain)
        .help("Show \(target.title)")
    }

    private func showMainWindow(selecting section: SidebarSection? = nil) {
        if let section {
            appModel.selectedSidebarSection = section
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AppSceneID.mainWindow)
    }

    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}

private struct MenuBarMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
