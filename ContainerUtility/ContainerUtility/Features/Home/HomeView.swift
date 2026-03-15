import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - (Layout.contentPadding * 2), 0)

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    header
                    dashboard(for: layoutMode(for: contentWidth))
                }
                .padding(Layout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Settings (⌘,)")
            }
        }
    }

    @ViewBuilder
    private func dashboard(for mode: HomeDashboardLayoutMode) -> some View {
        switch mode {
        case .wide:
            wideBentoGrid
        case .medium:
            mediumBentoGrid
        case .compact:
            compactBentoStack
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summaryLineOne)
                .font(.title3.weight(.medium))
        }
    }

    private var wideBentoGrid: some View {
        VStack(spacing: Layout.gridSpacing) {
            HStack(alignment: .top, spacing: Layout.gridSpacing) {
                metricTile(
                    title: "Containers",
                    value: String(appModel.containers.count),
                    detail: "\(runningContainerCount) running · \(stoppedContainerCount) stopped",
                    color: .blue,
                    symbol: "shippingbox"
                )

                metricTile(
                    title: "Images",
                    value: String(appModel.images.count),
                    detail: appModel.images.isEmpty ? "No local images yet" : "Local image references",
                    color: .indigo,
                    symbol: "photo.stack"
                )

                metricTile(
                    title: "Networks",
                    value: String(appModel.networks.count),
                    detail: "\(attachedNetworkCount) attached to containers",
                    color: .cyan,
                    symbol: "network"
                )

                metricTile(
                    title: "Volumes",
                    value: String(appModel.volumes.count),
                    detail: "\(referencedVolumeCount) referenced",
                    color: .mint,
                    symbol: "internaldrive"
                )
            }

            HStack(alignment: .top, spacing: Layout.gridSpacing) {
                operationsTile
                runtimeTile
            }

            activityTile
        }
    }

    private var mediumBentoGrid: some View {
        VStack(spacing: Layout.gridSpacing) {
            HStack(alignment: .top, spacing: Layout.gridSpacing) {
                metricTile(
                    title: "Containers",
                    value: String(appModel.containers.count),
                    detail: "\(runningContainerCount) running · \(stoppedContainerCount) stopped",
                    color: .blue,
                    symbol: "shippingbox"
                )

                metricTile(
                    title: "Images",
                    value: String(appModel.images.count),
                    detail: appModel.images.isEmpty ? "No local images yet" : "Local image references",
                    color: .indigo,
                    symbol: "photo.stack"
                )
            }

            HStack(alignment: .top, spacing: Layout.gridSpacing) {
                metricTile(
                    title: "Networks",
                    value: String(appModel.networks.count),
                    detail: "\(attachedNetworkCount) attached to containers",
                    color: .cyan,
                    symbol: "network"
                )

                metricTile(
                    title: "Volumes",
                    value: String(appModel.volumes.count),
                    detail: "\(referencedVolumeCount) referenced",
                    color: .mint,
                    symbol: "internaldrive"
                )
            }

            HStack(alignment: .top, spacing: Layout.gridSpacing) {
                operationsTile
                runtimeTile
            }

            activityTile
        }
    }

    private var compactBentoStack: some View {
        VStack(spacing: Layout.gridSpacing) {
            metricTile(
                title: "Containers",
                value: String(appModel.containers.count),
                detail: "\(runningContainerCount) running · \(stoppedContainerCount) stopped",
                color: .blue,
                symbol: "shippingbox"
            )
            metricTile(
                title: "Images",
                value: String(appModel.images.count),
                detail: appModel.images.isEmpty ? "No local images yet" : "Local image references",
                color: .indigo,
                symbol: "photo.stack"
            )
            metricTile(
                title: "Networks",
                value: String(appModel.networks.count),
                detail: "\(attachedNetworkCount) attached to containers",
                color: .cyan,
                symbol: "network"
            )
            metricTile(
                title: "Volumes",
                value: String(appModel.volumes.count),
                detail: "\(referencedVolumeCount) referenced",
                color: .mint,
                symbol: "internaldrive"
            )
            operationsTile
            runtimeTile
            activityTile
        }
    }

    private var operationsTile: some View {
        bentoTile(title: "Operations", subtitle: "Queue and session outcomes", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                HomeFactRow(
                    label: "Running Now",
                    value: String(runningOperationCount),
                    tint: .primary,
                    systemImage: "play.fill",
                    iconTint: .secondary
                )
                HomeFactRow(
                    label: "Queued",
                    value: String(queuedOperationCount),
                    tint: .primary,
                    systemImage: "clock",
                    iconTint: .secondary
                )
                HomeFactRow(
                    label: "Failed",
                    value: String(failedOperationCount),
                    tint: .primary,
                    systemImage: "exclamationmark.triangle.fill",
                    iconTint: .secondary
                )
            }
        }
    }

    private var runtimeTile: some View {
        bentoTile(title: "Runtime Snapshot", subtitle: "Latest known system health", symbol: "desktopcomputer") {
            VStack(alignment: .leading, spacing: 8) {
                HomeFactRow(label: "Engine", value: engineStateDisplay, tint: engineStateColor)
                HomeFactRow(label: "Preflight", value: preflightDisplay, tint: .secondary)
                HomeFactRow(label: "Last Updated", value: systemHealthUpdatedDisplay, tint: .secondary)
            }
        }
    }

    private var activityTile: some View {
        bentoTile(title: "Recent Activity", subtitle: "Most recent commands", symbol: "bolt.horizontal.circle") {
            if recentActivities.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Activity", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("Commands you run from the app will appear here.")
                }
                .frame(maxWidth: .infinity, minHeight: 128)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentActivities) { activity in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(statusColor(activity.status))
                                .frame(width: 6, height: 6)
                            Text(activity.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(statusLabel(activity.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            }
        }
    }

    private func metricTile(
        title: String,
        value: String,
        detail: String,
        color: Color,
        symbol: String
    ) -> some View {
        bentoTile(title: title, subtitle: detail, symbol: symbol) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bentoTile<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: symbol)
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

    private var summaryLineOne: String {
        "You have \(appModel.containers.count) containers, \(appModel.images.count) images, \(appModel.networks.count) networks, and \(appModel.volumes.count) volumes managed."
    }

    private func layoutMode(for width: CGFloat) -> HomeDashboardLayoutMode {
        switch width {
        case Layout.wideMinContentWidth...:
            .wide
        case Layout.mediumMinContentWidth...:
            .medium
        default:
            .compact
        }
    }

    private var runningOperationCount: Int {
        appModel.activities.filter { $0.status == .running }.count
    }

    private var queuedOperationCount: Int {
        appModel.activities.filter { $0.status == .queued }.count
    }

    private var failedOperationCount: Int {
        appModel.activities.filter { $0.status == .failed }.count
    }

    private var runningContainerCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var stoppedContainerCount: Int {
        max(appModel.containers.count - runningContainerCount, 0)
    }

    private var attachedNetworkCount: Int {
        appModel.networks.filter { $0.attachedContainerCount > 0 }.count
    }

    private var referencedVolumeCount: Int {
        appModel.volumes.filter { $0.attachedContainerCount > 0 }.count
    }

    private var recentActivities: [ActivityRecord] {
        Array(appModel.activities.prefix(4))
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

    private var preflightDisplay: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "Not checked yet"
        }

        let passCount = snapshot.preflightChecks.filter { $0.severity == .pass }.count
        let warningCount = snapshot.preflightChecks.filter { $0.severity == .warning }.count
        let failCount = snapshot.preflightChecks.filter { $0.severity == .failure }.count
        return "\(passCount) pass · \(warningCount) warning · \(failCount) fail"
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

    private var systemHealthUpdatedDisplay: String {
        guard let timestamp = appModel.latestSystemHealthUpdatedAt else {
            return "No snapshot"
        }
        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    private func statusLabel(_ status: ActivityOperationStatus) -> String {
        switch status {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .succeeded:
            "Done"
        case .failed:
            "Failed"
        case .canceled:
            "Canceled"
        }
    }

    private func statusColor(_ status: ActivityOperationStatus) -> Color {
        switch status {
        case .queued:
            .secondary
        case .running:
            .orange
        case .succeeded:
            .green
        case .failed:
            .red
        case .canceled:
            .secondary
        }
    }
}

private enum HomeDashboardLayoutMode {
    case compact
    case medium
    case wide
}

private enum Layout {
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let gridSpacing: CGFloat = 12
    static let mediumMinContentWidth: CGFloat = 560
    static let wideMinContentWidth: CGFloat = 960
}

private struct HomeFactRow: View {
    let label: String
    let value: String
    let tint: Color
    var systemImage: String?
    var iconTint: Color?

    var body: some View {
        HStack {
            if let systemImage {
                Label {
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(iconTint ?? tint)
                }
            } else {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
}
