import Foundation

struct ContainerSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var imageName: String
    var state: ContainerState
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        imageName: String,
        state: ContainerState,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.imageName = imageName
        self.state = state
        self.createdAt = createdAt
    }

    var displayName: String {
        "\(name) • \(state.rawValue.capitalized)"
    }
}

enum ContainerState: String, Codable, CaseIterable, Sendable {
    case created
    case running
    case paused
    case stopped
    case exited
    case unknown

    init(cliState: String) {
        let normalized = cliState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case let value where value.contains("running"):
            self = .running
        case let value where value.contains("paused"):
            self = .paused
        case let value where value.contains("created"):
            self = .created
        case let value where value.contains("stopped"),
            let value where value.contains("exited"):
            self = normalized.contains("exited") ? .exited : .stopped
        default:
            self = .unknown
        }
    }
}

struct ImageSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var reference: String
    var sizeBytes: Int64

    init(id: UUID = UUID(), reference: String, sizeBytes: Int64) {
        self.id = id
        self.reference = reference
        self.sizeBytes = sizeBytes
    }

    var displayName: String {
        reference
    }
}

struct NetworkSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var driver: String
    var attachedContainerCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        driver: String,
        attachedContainerCount: Int
    ) {
        self.id = id
        self.name = name
        self.driver = driver
        self.attachedContainerCount = attachedContainerCount
    }

    var displayName: String {
        "\(name) • \(attachedContainerCount) attached"
    }
}

struct VolumeSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var mountpoint: String
    var attachedContainerCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        mountpoint: String,
        attachedContainerCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.mountpoint = mountpoint
        self.attachedContainerCount = attachedContainerCount
    }

    var displayName: String {
        attachedContainerCount > 0 ? "\(name) • \(attachedContainerCount) attached" : name
    }
}

enum ActivityOperationStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case canceled

    var isActive: Bool {
        switch self {
        case .queued, .running:
            true
        case .succeeded, .failed, .canceled:
            false
        }
    }
}

enum ActivityOperationKind: String, Codable, CaseIterable, Sendable {
    case system
    case container
    case image
    case network
    case volume
    case diagnostics
}

struct ActivityOperationOutcome: Sendable {
    var summary: String?
}

struct ActivityRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let retrySourceID: UUID?
    let title: String
    let commandDescription: String
    let section: SidebarSection
    let kind: ActivityOperationKind
    let isRetryable: Bool
    var status: ActivityOperationStatus
    let queuedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var summary: String?
    var errorMessage: String?
    var outputLog: String

    init(
        id: UUID = UUID(),
        retrySourceID: UUID? = nil,
        title: String,
        commandDescription: String,
        section: SidebarSection,
        kind: ActivityOperationKind,
        isRetryable: Bool = true,
        status: ActivityOperationStatus = .queued,
        queuedAt: Date = .now,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        summary: String? = nil,
        errorMessage: String? = nil,
        outputLog: String = ""
    ) {
        self.id = id
        self.retrySourceID = retrySourceID
        self.title = title
        self.commandDescription = commandDescription
        self.section = section
        self.kind = kind
        self.isRetryable = isRetryable
        self.status = status
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.errorMessage = errorMessage
        self.outputLog = outputLog
    }

    var canRetry: Bool {
        isRetryable && (status == .failed || status == .canceled)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case system
    case containers
    case images
    case registries
    case networks
    case volumes
    case activity
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .system:
            "System"
        case .containers:
            "Containers"
        case .images:
            "Images"
        case .registries:
            "Registries"
        case .networks:
            "Networks"
        case .volumes:
            "Volumes"
        case .activity:
            "Activity"
        case .diagnostics:
            "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .system:
            "desktopcomputer"
        case .containers:
            "shippingbox"
        case .images:
            "photo.stack"
        case .registries:
            "externaldrive.badge.wifi"
        case .networks:
            "network"
        case .volumes:
            "internaldrive"
        case .activity:
            "clock.arrow.circlepath"
        case .diagnostics:
            "stethoscope"
        }
    }
}
