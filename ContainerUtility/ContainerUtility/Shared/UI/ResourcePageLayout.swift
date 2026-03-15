import SwiftUI

// MARK: - ResourcePageHeader

/// A native macOS page header with toolbar-style layout.
///
/// Provides a lighter visual weight than GroupBox-based designs.
struct ResourcePageHeader<Accessory: View>: View {
    let title: String
    let summary: String
    private let accessory: Accessory
    var style: HeaderStyle = .toolbar

    enum HeaderStyle {
        case toolbar  // Native toolbar appearance
        case formSection  // Form-style with background
        case plain  // No background, just text and accessory
    }

    init(
        title: String,
        summary: String,
        style: HeaderStyle = .toolbar,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.summary = summary
        self.style = style
        self.accessory = accessory()
    }

    var body: some View {
        Group {
            switch style {
            case .toolbar:
                toolbarStyleBody
            case .formSection:
                formSectionStyleBody
            case .plain:
                plainStyleBody
            }
        }
    }

    private var toolbarStyleBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            accessory
                .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator.opacity(0.5)),
            alignment: .bottom
        )
    }

    private var formSectionStyleBody: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                accessory
            }
            .padding(.vertical, 4)
        }
    }

    private var plainStyleBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            accessory
        }
    }
}

// MARK: - ResourcePanel

/// A flexible content panel that adapts its appearance based on the selected style.
///
/// Defaults to a lighter Form-based appearance instead of GroupBox.
struct ResourcePanel<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String?
    private let accessory: Accessory
    private let content: Content
    var style: PanelStyle = .form

    enum PanelStyle {
        case form  // Native Form/Section appearance (lightest)
        case divider  // VStack with subtle dividers
        case card  // Original GroupBox style (for compatibility)
        case plain  // No container, just content with optional header
    }

    init(
        title: String,
        subtitle: String? = nil,
        style: PanelStyle = .form,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        Group {
            switch style {
            case .form:
                formStyleBody
            case .divider:
                dividerStyleBody
            case .card:
                cardStyleBody
            case .plain:
                plainStyleBody
            }
        }
    }

    private var formStyleBody: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.medium))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                accessory
            }
        }
    }

    private var dividerStyleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                accessory
            }

            content
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator.opacity(0.4)),
            alignment: .bottom
        )
    }

    private var cardStyleBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    accessory
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var plainStyleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                accessory
            }

            content
        }
    }
}

// MARK: - Backward Compatibility Extensions

extension ResourcePageHeader where Accessory == EmptyView {
    init(
        title: String,
        summary: String,
        style: HeaderStyle = .toolbar
    ) {
        self.init(title: title, summary: summary, style: style) {
            EmptyView()
        }
    }
}

extension ResourcePanel where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        style: PanelStyle = .form,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            style: style,
            accessory: { EmptyView() },
            content: content
        )
    }
}

// MARK: - ResourceInspectorPane

struct ResourceInspectorPane<Accessory: View, Content: View>: View {
    let title: String
    let showsHeader: Bool
    private let accessory: Accessory
    private let content: Content

    init(
        title: String = "Inspector",
        showsHeader: Bool = true,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showsHeader = showsHeader
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.headline)

                    Spacer(minLength: 8)

                    accessory
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Spacer(minLength: 0)

                    accessory
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

extension ResourceInspectorPane where Accessory == EmptyView {
    init(
        title: String = "Inspector",
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, showsHeader: showsHeader, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Inspector States

struct ResourceInspectorStateDescriptor {
    let title: String
    let message: String
    let systemImage: String
    var details: String?
    var detailsTitle: String = "CLI Error Details"
}

struct ResourceInspectorStateView: View {
    let descriptor: ResourceInspectorStateDescriptor

    var body: some View {
        ContentUnavailableView {
            Label(descriptor.title, systemImage: descriptor.systemImage)
        } description: {
            VStack(spacing: 12) {
                Text(descriptor.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let details = normalizedDetails {
                    DisclosureGroup(descriptor.detailsTitle) {
                        ResourceMonospacedOutput(
                            text: details,
                            placeholder: "No additional detail available."
                        )
                        .frame(minHeight: 140, maxHeight: 220)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var normalizedDetails: String? {
        guard let details = descriptor.details?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return details.isEmpty ? nil : details
    }
}

struct ResourceInspectorLoadingView: View {
    let title: String

    init(title: String = "Loading details…") {
        self.title = title
    }

    var body: some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
    }
}

struct ResourceListFeedbackBar: View {
    let activity: ActivityRecord?
    let warningMessages: [String]
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let activity {
                activityView(activity)
            }

            if !warningMessages.isEmpty {
                Label(warningSummary, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(warningMessages.joined(separator: "\n\n"))
            }

            if let normalizedError {
                Label(normalizedError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(normalizedError)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var warningSummary: String {
        warningMessages.count == 1 ? "1 warning while loading" : "\(warningMessages.count) warnings while loading"
    }

    private var normalizedError: String? {
        guard let normalized = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    @ViewBuilder
    private func activityView(_ activity: ActivityRecord) -> some View {
        switch activity.status {
        case .queued:
            Label("Queued: \(activity.title)", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .running:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12, height: 12)
                Text(activity.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .succeeded, .failed, .canceled:
            EmptyView()
        }
    }
}

func resourceInspectorFailureDescriptor(
    resourceName: String,
    error: String,
    systemHealth: SystemHealthSnapshot?
) -> ResourceInspectorStateDescriptor {
    let normalizedError = error.trimmingCharacters(in: .whitespacesAndNewlines)

    if shouldPresentOfflineInspectorState(error: normalizedError, systemHealth: systemHealth) {
        if systemHealth?.executablePath == nil {
            return ResourceInspectorStateDescriptor(
                title: "Container CLI Unavailable",
                message: "Install the container CLI, then reload this \(resourceName) inspector.",
                systemImage: "wrench.and.screwdriver",
                details: normalizedError,
                detailsTitle: "Runtime Error Details"
            )
        }

        if systemHealth?.engineState == .stopped || normalizedError.localizedCaseInsensitiveContains("not running")
            || normalizedError.localizedCaseInsensitiveContains("stopped")
        {
            return ResourceInspectorStateDescriptor(
                title: "Engine Not Running",
                message: "Start the container engine from the System page, then reload this \(resourceName) inspector.",
                systemImage: "power.circle",
                details: normalizedError,
                detailsTitle: "Runtime Error Details"
            )
        }

        return ResourceInspectorStateDescriptor(
            title: "Runtime Unavailable",
            message:
                "The container runtime is currently unavailable, so ContainerUtility could not inspect this \(resourceName). Refresh the System page, then try again.",
            systemImage: "bolt.horizontal.circle",
            details: normalizedError,
            detailsTitle: "Runtime Error Details"
        )
    }

    return ResourceInspectorStateDescriptor(
        title: "Unable to Load Details",
        message:
            "ContainerUtility could not inspect this \(resourceName). Review the CLI error details if you need the underlying runtime response.",
        systemImage: "exclamationmark.triangle",
        details: normalizedError
    )
}

func resourceListFailureDescriptor(
    resourceName: String,
    error: String,
    systemHealth: SystemHealthSnapshot?
) -> ResourceInspectorStateDescriptor {
    let normalizedError = error.trimmingCharacters(in: .whitespacesAndNewlines)

    if shouldPresentOfflineInspectorState(error: normalizedError, systemHealth: systemHealth) {
        if systemHealth?.executablePath == nil {
            return ResourceInspectorStateDescriptor(
                title: "Container CLI Unavailable",
                message: "Install the container CLI, then reload the \(resourceName) list.",
                systemImage: "wrench.and.screwdriver",
                details: normalizedError,
                detailsTitle: "Runtime Error Details"
            )
        }

        if systemHealth?.engineState == .stopped || normalizedError.localizedCaseInsensitiveContains("not running")
            || normalizedError.localizedCaseInsensitiveContains("stopped")
        {
            return ResourceInspectorStateDescriptor(
                title: "Engine Not Running",
                message: "Start the container engine from the System page, then reload the \(resourceName) list.",
                systemImage: "power.circle",
                details: normalizedError,
                detailsTitle: "Runtime Error Details"
            )
        }

        return ResourceInspectorStateDescriptor(
            title: "Runtime Unavailable",
            message:
                "The container runtime is currently unavailable, so ContainerUtility could not load the \(resourceName) list. Refresh the System page, then try again.",
            systemImage: "bolt.horizontal.circle",
            details: normalizedError,
            detailsTitle: "Runtime Error Details"
        )
    }

    return ResourceInspectorStateDescriptor(
        title: "Unable to Load \(resourceName.capitalized)",
        message:
            "ContainerUtility could not load the \(resourceName) list. Review the CLI error details if you need the underlying runtime response.",
        systemImage: "exclamationmark.triangle",
        details: normalizedError
    )
}

private func shouldPresentOfflineInspectorState(
    error: String,
    systemHealth: SystemHealthSnapshot?
) -> Bool {
    if systemHealth?.executablePath == nil || systemHealth?.engineState == .stopped {
        return true
    }

    let normalized = error.lowercased()
    let offlineHints = [
        "not running",
        "stopped",
        "xpc",
        "connection invalid",
        "connection interrupted",
        "connection was invalidated",
        "service unavailable",
        "service is disabled",
        "failed to connect",
        "failed to dial",
        "bootstrap",
        "runtime unavailable",
        "engine unavailable",
    ]

    return offlineHints.contains { normalized.contains($0) }
}

// MARK: - ResourceEmptyStateSurface

struct ResourceEmptyStateSurface<Content: View>: View {
    private let maxWidth: CGFloat
    private let backgroundOpacity: Double
    private let content: Content

    init(
        maxWidth: CGFloat = 360,
        backgroundOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.backgroundOpacity = backgroundOpacity
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.clear

            content
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
                .background(.quaternary.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - ResourceWorkspaceSplit

/// A split view layout for resource workspaces with overlay support.
struct ResourceWorkspaceSplit<ListPane: View, DetailPane: View, OverlayContent: View>: View {
    let showsOverlay: Bool
    let listMinHeight: CGFloat
    let listIdealHeight: CGFloat
    let detailMinHeight: CGFloat
    private let listPane: ListPane
    private let detailPane: DetailPane
    private let overlayContent: OverlayContent

    init(
        showsOverlay: Bool,
        listMinHeight: CGFloat = 260,
        listIdealHeight: CGFloat = 320,
        detailMinHeight: CGFloat = 300,
        @ViewBuilder listPane: () -> ListPane,
        @ViewBuilder detailPane: () -> DetailPane,
        @ViewBuilder overlayContent: () -> OverlayContent
    ) {
        self.showsOverlay = showsOverlay
        self.listMinHeight = listMinHeight
        self.listIdealHeight = listIdealHeight
        self.detailMinHeight = detailMinHeight
        self.listPane = listPane()
        self.detailPane = detailPane()
        self.overlayContent = overlayContent()
    }

    var body: some View {
        ZStack {
            VSplitView {
                listPane
                    .frame(minHeight: listMinHeight, idealHeight: listIdealHeight)

                detailPane
                    .frame(minHeight: detailMinHeight, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsOverlay {
                overlayContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)
                    .background(.background.opacity(0.97))
            }
        }
    }
}

// MARK: - Supporting Views

struct ResourceMonospacedOutput: View {
    let text: String
    let placeholder: String

    init(text: String, placeholder: String) {
        self.text = text
        self.placeholder = placeholder
    }

    private var displayText: String {
        text.isEmpty ? placeholder : text
    }

    var body: some View {
        ScrollView {
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ResourceFactRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct ResourceTag: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - New Layout Components

/// A toolbar-style header for page layouts with action buttons.
struct ResourceToolbarHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    private let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            accessory
                .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.06))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator.opacity(0.4)),
            alignment: .bottom
        )
    }
}

extension ResourceToolbarHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

/// A flexible content section that can adapt to different container styles.
struct ResourceContentSection<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content
    var showDivider: Bool = true
    var spacing: CGFloat = 12

    init(
        showDivider: Bool = true,
        spacing: CGFloat = 12,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.showDivider = showDivider
        self.spacing = spacing
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            content
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .frame(height: showDivider ? 0.5 : 0)
                .foregroundStyle(.separator.opacity(0.4)),
            alignment: .bottom
        )
    }
}
