import SwiftUI

// MARK: - UtilityPageHeader

/// A lightweight page header with native macOS styling.
///
/// Provides a cleaner alternative to heavy GroupBox headers.
struct UtilityPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    private let accessory: Accessory
    var style: HeaderStyle = .default

    enum HeaderStyle {
        case `default`  // Standard layout with title/subtitle and accessory
        case compact  // Smaller padding, tighter layout
        case prominent  // Larger title, more visual weight
    }

    init(
        title: String,
        subtitle: String,
        style: HeaderStyle = .default,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.accessory = accessory()
    }

    init(title: String, subtitle: String, style: HeaderStyle = .default) where Accessory == EmptyView {
        self.init(title: title, subtitle: subtitle, style: style) {
            EmptyView()
        }
    }

    var body: some View {
        Group {
            switch style {
            case .default:
                defaultStyleBody
            case .compact:
                compactStyleBody
            case .prominent:
                prominentStyleBody
            }
        }
    }

    private var defaultStyleBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactStyleBody: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            accessory
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prominentStyleBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                accessory
            }

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - UtilitySectionCard

/// A flexible section card that can render in multiple styles.
///
/// Defaults to a lighter appearance than the original GroupBox design.
struct UtilitySectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    private let content: Content
    var style: CardStyle = .light

    enum CardStyle {
        case light  // Form/Section style (lightest, default)
        case divider  // VStack with subtle divider
        case grouped  // GroupBox style (original, for compatibility)
        case plain  // No container styling
    }

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        style: CardStyle = .light,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.style = style
        self.content = content()
    }

    var body: some View {
        Group {
            switch style {
            case .light:
                lightStyleBody
            case .divider:
                dividerStyleBody
            case .grouped:
                groupedStyleBody
            case .plain:
                plainStyleBody
            }
        }
    }

    private var lightStyleBody: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                content
            }
        } header: {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
        }
    }

    private var dividerStyleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.medium))
                Text(title)
                    .font(.headline.weight(.medium))

                Spacer()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    private var groupedStyleBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private var plainStyleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.medium))
                Text(title)
                    .font(.headline.weight(.medium))

                Spacer()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            content
        }
    }
}

// MARK: - UtilityMetricBadge

/// A metric display badge with native styling.
struct UtilityMetricBadge: View {
    let title: String
    let value: String
    var tint: Color = .accentColor
    var style: BadgeStyle = .filled

    enum BadgeStyle {
        case filled  // Filled background (original)
        case bordered  // Bordered with transparent background
        case minimal  // No background or border
    }

    var body: some View {
        Group {
            switch style {
            case .filled:
                filledStyleBody
            case .bordered:
                borderedStyleBody
            case .minimal:
                minimalStyleBody
            }
        }
    }

    private var filledStyleBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.18))
        )
    }

    private var borderedStyleBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.3))
        )
    }

    private var minimalStyleBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - New Utility Components

/// A horizontal toolbar-style section with icon, title, and actions.
struct UtilityToolbarSection<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    private let accessory: Accessory
    private let content: Content
    var showDivider: Bool = true

    init(
        title: String,
        systemImage: String,
        showDivider: Bool = true,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.showDivider = showDivider
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.medium))
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                accessory
                    .controlSize(.small)
            }

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

extension UtilityToolbarSection where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        showDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            showDivider: showDivider,
            accessory: { EmptyView() },
            content: content
        )
    }
}

/// A compact form row component for utility pages.
struct UtilityFormRow<Content: View>: View {
    let title: String
    private let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        LabeledContent(title) {
            content
        }
    }
}

/// A responsive grid layout for utility metric cards.
struct UtilityMetricsGrid<Content: View>: View {
    private let content: Content
    var columns: Int = 3
    var spacing: CGFloat = 12

    init(
        columns: Int = 3,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)

        LazyVGrid(columns: gridItems, spacing: spacing) {
            content
        }
    }
}

/// A simple divider-based section for grouping content without visual containers.
struct UtilityDividerSection<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
}
