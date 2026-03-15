import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selectedSidebarSection: SidebarSection?
    var containers: [ContainerSummary]
    var images: [ImageSummary]
    var networks: [NetworkSummary]
    var volumes: [VolumeSummary]
    var registrySessionCount: Int
    var activities: [ActivityRecord]
    var latestDiagnosticsBundlePath: String?
    var latestDiagnosticsSummary: String?
    var latestDiagnosticsUpdatedAt: Date?
    var latestSystemHealthSnapshot: SystemHealthSnapshot?
    var latestSystemHealthUpdatedAt: Date?
    var cachedContainerItems: [ContainerListItem]
    var cachedImageItems: [ImageListItem]
    var cachedNetworkItems: [NetworkListItem]
    var cachedVolumeItems: [VolumeListItem]

    var systemRefreshRevision = 0
    var containersRefreshRevision = 0
    var imagesRefreshRevision = 0
    var networksRefreshRevision = 0
    var volumesRefreshRevision = 0
    var activityRefreshRevision = 0
    var diagnosticsRefreshRevision = 0

    @ObservationIgnored private var registeredActivityActions: [UUID: RegisteredActivityAction] = [:]
    @ObservationIgnored private var pendingActivityIDs: [UUID] = []
    @ObservationIgnored private var runningActivityID: UUID?
    @ObservationIgnored private var runningActivityTask: Task<Void, Never>?

    init(
        selectedSidebarSection: SidebarSection? = .home,
        containers: [ContainerSummary] = [],
        images: [ImageSummary] = [],
        networks: [NetworkSummary] = [],
        volumes: [VolumeSummary] = [],
        registrySessionCount: Int = 0,
        activities: [ActivityRecord] = [],
        cachedContainerItems: [ContainerListItem] = [],
        cachedImageItems: [ImageListItem] = [],
        cachedNetworkItems: [NetworkListItem] = [],
        cachedVolumeItems: [VolumeListItem] = []
    ) {
        self.selectedSidebarSection = selectedSidebarSection
        self.containers = containers
        self.images = images
        self.networks = networks
        self.volumes = volumes
        self.registrySessionCount = registrySessionCount
        self.activities = activities
        self.cachedContainerItems = cachedContainerItems
        self.cachedImageItems = cachedImageItems
        self.cachedNetworkItems = cachedNetworkItems
        self.cachedVolumeItems = cachedVolumeItems
    }

    func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .home:
            0
        case .system:
            0
        case .containers:
            containers.count
        case .images:
            images.count
        case .registries:
            registrySessionCount
        case .networks:
            networks.count
        case .volumes:
            volumes.count
        case .activity:
            activities.filter { $0.status.isActive }.count
        case .diagnostics:
            activities.filter { $0.section == .diagnostics && $0.status.isActive }.count
        }
    }

    func updateContainers(from items: [ContainerListItem]) {
        var existingByName: [String: ContainerSummary] = [:]
        for item in containers {
            existingByName[item.name] = item
        }
        containers = items.map { item in
            let existing = existingByName[item.name]
            return ContainerSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                imageName: item.image ?? "Unknown image",
                state: ContainerState(cliState: item.state),
                createdAt: existing?.createdAt ?? .now
            )
        }
    }

    func updateContainerSummary(from result: NonCriticalDecodeResult<[ContainerListItem]>) {
        switch result {
        case .parsed(let value, _):
            updateContainers(from: value)
        case .raw:
            break
        }
    }

    func updateImages(from items: [ImageListItem]) {
        var existingByReference: [String: ImageSummary] = [:]
        for item in images {
            existingByReference[item.reference] = item
        }
        images = items.map { item in
            let existing = existingByReference[item.reference]
            return ImageSummary(
                id: existing?.id ?? UUID(),
                reference: item.reference,
                sizeBytes: existing?.sizeBytes ?? 0
            )
        }
    }

    func updateImageSummary(from result: NonCriticalDecodeResult<[ImageListItem]>) {
        switch result {
        case .parsed(let value, _):
            updateImages(from: value)
        case .raw:
            break
        }
    }

    func updateNetworks(from items: [NetworkListItem], relationships: [ResourceRelationshipHint] = []) {
        var existingByName: [String: NetworkSummary] = [:]
        for item in networks {
            existingByName[item.name] = item
        }
        var attachedContainerIDs: [String: Set<String>] = [:]
        for hint in relationships {
            for networkName in hint.networks {
                attachedContainerIDs[networkName, default: []].insert(hint.containerID)
            }
        }

        networks = items.map { item in
            let existing = existingByName[item.name]
            return NetworkSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                driver: item.plugin ?? item.mode ?? "Unknown",
                attachedContainerCount: attachedContainerIDs[item.name, default: []].count
            )
        }
    }

    func updateNetworkSummary(
        from result: NonCriticalDecodeResult<[NetworkListItem]>,
        relationships: [ResourceRelationshipHint]
    ) {
        switch result {
        case .parsed(let value, _):
            updateNetworks(from: value, relationships: relationships)
        case .raw:
            break
        }
    }

    func updateVolumes(from items: [VolumeListItem], relationships: [ResourceRelationshipHint] = []) {
        var existingByName: [String: VolumeSummary] = [:]
        for item in volumes {
            existingByName[item.name] = item
        }
        var attachedContainerIDs: [String: Set<String>] = [:]
        for hint in relationships {
            for volume in hint.volumeMounts {
                attachedContainerIDs[volume.name, default: []].insert(hint.containerID)
            }
        }

        volumes = items.map { item in
            let existing = existingByName[item.name]
            return VolumeSummary(
                id: existing?.id ?? UUID(),
                name: item.name,
                mountpoint: item.source ?? existing?.mountpoint ?? "",
                attachedContainerCount: attachedContainerIDs[item.name, default: []].count
            )
        }
    }

    func updateVolumeSummary(
        from result: NonCriticalDecodeResult<[VolumeListItem]>,
        relationships: [ResourceRelationshipHint]
    ) {
        switch result {
        case .parsed(let value, _):
            updateVolumes(from: value, relationships: relationships)
        case .raw:
            break
        }
    }

    func enqueueActivity(
        title: String,
        section: SidebarSection,
        kind: ActivityOperationKind,
        commandDescription: String,
        isRetryable: Bool = true,
        retrySourceID: UUID? = nil,
        execute: @escaping @Sendable (_ activityID: UUID) async throws -> ActivityOperationOutcome
    ) -> UUID {
        let id = UUID()
        let record = ActivityRecord(
            id: id,
            retrySourceID: retrySourceID,
            title: title,
            commandDescription: commandDescription,
            section: section,
            kind: kind,
            isRetryable: isRetryable
        )
        activities.insert(record, at: 0)
        registeredActivityActions[id] = RegisteredActivityAction(
            title: title,
            section: section,
            kind: kind,
            commandDescription: commandDescription,
            isRetryable: isRetryable,
            execute: execute
        )
        pendingActivityIDs.append(id)
        bumpRefreshRevision(for: .activity)
        scheduleNextActivityIfNeeded()
        return id
    }

    func appendActivityOutput(id: UUID, chunk: String, maxCharacters: Int = 120_000) {
        guard let index = activityIndex(for: id), !chunk.isEmpty else { return }
        activities[index].outputLog.append(chunk)
        if activities[index].outputLog.count > maxCharacters {
            activities[index].outputLog = String(activities[index].outputLog.suffix(maxCharacters))
        }
    }

    func retryActivity(_ id: UUID) {
        guard canRetryActivity(id) else { return }
        guard let existing = activities.first(where: { $0.id == id }) else { return }
        guard let registration = registeredActivityActions[id] else { return }

        _ = enqueueActivity(
            title: "Retry \(existing.title)",
            section: registration.section,
            kind: registration.kind,
            commandDescription: registration.commandDescription,
            isRetryable: registration.isRetryable,
            retrySourceID: id,
            execute: registration.execute
        )
    }

    func canRetryActivity(_ id: UUID) -> Bool {
        guard let activity = activities.first(where: { $0.id == id }) else { return false }
        return activity.canRetry && registeredActivityActions[id] != nil
    }

    func cancelActivity(id: UUID) {
        if runningActivityID == id {
            runningActivityTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard self.runningActivityID == id else { return }
                self.appendActivityOutput(id: id, chunk: "\nOperation cancelled.\n")
                self.finishActivity(
                    id: id,
                    status: .canceled,
                    summary: nil,
                    errorMessage: "Operation cancelled."
                )
                self.activityDidExit(id: id)
            }
            return
        }

        guard let queueIndex = pendingActivityIDs.firstIndex(of: id) else { return }
        pendingActivityIDs.remove(at: queueIndex)
        finishActivity(
            id: id,
            status: .canceled,
            summary: "Canceled before execution.",
            errorMessage: nil
        )
    }

    func cancelLatestActiveActivity(in section: SidebarSection) {
        guard let activity = activities.first(where: { $0.section == section && $0.status.isActive }) else { return }
        cancelActivity(id: activity.id)
    }

    func clearCompletedActivities() {
        let removableIDs = Set(activities.filter { !$0.status.isActive }.map(\.id))
        activities.removeAll { removableIDs.contains($0.id) }
        for id in removableIDs {
            registeredActivityActions.removeValue(forKey: id)
        }
        bumpRefreshRevision(for: .activity)
    }

    func hasActiveActivity(for section: SidebarSection) -> Bool {
        activities.contains { $0.section == section && $0.status.isActive }
    }

    func activeActivityCount(for section: SidebarSection) -> Int {
        activities.filter { $0.section == section && $0.status.isActive }.count
    }

    func latestActivity(for section: SidebarSection) -> ActivityRecord? {
        activities.first { $0.section == section }
    }

    func makeDiagnosticsOperationSnapshot(
        maxActivities: Int = 40
    ) -> DiagnosticsOperationSnapshot {
        DiagnosticsOperationSnapshot(
            activities: Array(activities.prefix(maxActivities))
        )
    }

    func recordDiagnosticsSummary(_ summary: String) {
        latestDiagnosticsSummary = summary
        latestDiagnosticsUpdatedAt = .now
        bumpRefreshRevision(for: .diagnostics)
    }

    func recordDiagnosticsBundleExport(path: String, summary: String) {
        latestDiagnosticsBundlePath = path
        latestDiagnosticsSummary = summary
        latestDiagnosticsUpdatedAt = .now
        bumpRefreshRevision(for: .diagnostics)
    }

    func refreshRevision(for section: SidebarSection) -> Int {
        switch section {
        case .home:
            systemRefreshRevision
        case .system:
            systemRefreshRevision
        case .containers:
            containersRefreshRevision
        case .images:
            imagesRefreshRevision
        case .registries:
            imagesRefreshRevision
        case .networks:
            networksRefreshRevision
        case .volumes:
            volumesRefreshRevision
        case .activity:
            activityRefreshRevision
        case .diagnostics:
            diagnosticsRefreshRevision
        }
    }

    func bumpRefreshRevision(for section: SidebarSection) {
        switch section {
        case .home:
            systemRefreshRevision += 1
        case .system:
            systemRefreshRevision += 1
        case .containers:
            containersRefreshRevision += 1
        case .images:
            imagesRefreshRevision += 1
        case .registries:
            imagesRefreshRevision += 1
        case .networks:
            networksRefreshRevision += 1
        case .volumes:
            volumesRefreshRevision += 1
        case .activity:
            activityRefreshRevision += 1
        case .diagnostics:
            diagnosticsRefreshRevision += 1
        }
    }

    func summary(for section: SidebarSection) -> [String] {
        switch section {
        case .home:
            return [
                "Containers: \(containers.count)",
                "Images: \(images.count)",
                "Networks: \(networks.count)",
                "Volumes: \(volumes.count)",
            ]
        case .system:
            return [
                "App shell initialized with sidebar/main/detail layout.",
                "Global command runner supports cancellation and timeout.",
                "Unified command errors are standardized as AppError.",
            ]
        case .containers:
            return ["Total containers: \(containers.count)"]
        case .images:
            return ["Total images: \(images.count)"]
        case .registries:
            return [
                "Registry sessions logged in: \(registrySessionCount)",
                "Active registry operations: \(activities.filter { $0.section == .registries && $0.status.isActive }.count)",
                "Completed registry operations this session: \(activities.filter { $0.section == .registries && !$0.status.isActive }.count)",
            ]
        case .networks:
            return [
                "Total networks: \(networks.count)",
                "Networks with container attachments: \(networks.filter { $0.attachedContainerCount > 0 }.count)",
            ]
        case .volumes:
            return [
                "Total volumes: \(volumes.count)",
                "Volumes referenced by containers: \(volumes.filter { $0.attachedContainerCount > 0 }.count)",
            ]
        case .activity:
            return [
                "Queued or running operations: \(activities.filter { $0.status.isActive }.count)",
                "Failed operations this session: \(activities.filter { $0.status == .failed }.count)",
                "Completed operations this session: \(activities.filter { !$0.status.isActive }.count)",
            ]
        case .diagnostics:
            var rows = [
                "Active diagnostics jobs: \(activities.filter { $0.section == .diagnostics && $0.status.isActive }.count)"
            ]
            if let latestDiagnosticsBundlePath {
                rows.append("Last support bundle: \((latestDiagnosticsBundlePath as NSString).lastPathComponent)")
            } else {
                rows.append("Last support bundle: none exported")
            }
            if let latestDiagnosticsUpdatedAt {
                rows.append(
                    "Last diagnostics update: \(latestDiagnosticsUpdatedAt.formatted(date: .abbreviated, time: .shortened))"
                )
            }
            return rows
        }
    }

    private func scheduleNextActivityIfNeeded() {
        guard runningActivityTask == nil else { return }
        guard !pendingActivityIDs.isEmpty else { return }

        var nextID: UUID?
        var registration: RegisteredActivityAction?

        while !pendingActivityIDs.isEmpty, registration == nil {
            let candidate = pendingActivityIDs.removeFirst()
            if let action = registeredActivityActions[candidate] {
                nextID = candidate
                registration = action
            }
        }

        guard let nextID, let registration else { return }

        runningActivityID = nextID
        markActivityRunning(id: nextID)

        runningActivityTask = Task { [registration] in
            do {
                let outcome = try await registration.execute(nextID)
                guard self.runningActivityID == nextID else { return }
                self.finishActivity(
                    id: nextID,
                    status: .succeeded,
                    summary: outcome.summary,
                    errorMessage: nil
                )
            } catch let error as AppError {
                guard self.runningActivityID == nextID else { return }
                let status: ActivityOperationStatus
                switch error {
                case .commandCancelled:
                    status = .canceled
                default:
                    status = .failed
                }
                self.appendActivityOutput(id: nextID, chunk: "\n\(error.localizedDescription)\n")
                self.finishActivity(
                    id: nextID,
                    status: status,
                    summary: nil,
                    errorMessage: error.localizedDescription
                )
            } catch is CancellationError {
                guard self.runningActivityID == nextID else { return }
                self.appendActivityOutput(id: nextID, chunk: "\nOperation cancelled.\n")
                self.finishActivity(
                    id: nextID,
                    status: .canceled,
                    summary: nil,
                    errorMessage: "Operation cancelled."
                )
            } catch {
                guard self.runningActivityID == nextID else { return }
                self.appendActivityOutput(id: nextID, chunk: "\n\(error.localizedDescription)\n")
                self.finishActivity(
                    id: nextID,
                    status: .failed,
                    summary: nil,
                    errorMessage: error.localizedDescription
                )
            }

            if self.runningActivityID == nextID {
                self.activityDidExit(id: nextID)
            }
        }
    }

    private func markActivityRunning(id: UUID) {
        guard let index = activityIndex(for: id) else { return }
        activities[index].status = .running
        activities[index].startedAt = .now
        activities[index].finishedAt = nil
        activities[index].summary = nil
        activities[index].errorMessage = nil
        bumpRefreshRevision(for: .activity)
    }

    private func finishActivity(
        id: UUID,
        status: ActivityOperationStatus,
        summary: String?,
        errorMessage: String?
    ) {
        guard let index = activityIndex(for: id) else { return }
        activities[index].status = status
        activities[index].finishedAt = .now
        activities[index].summary = summary
        activities[index].errorMessage = errorMessage
        if status == .succeeded {
            activities[index].errorMessage = nil
        }
        bumpRefreshRevision(for: .activity)
    }

    private func activityDidExit(id: UUID) {
        runningActivityID = nil
        runningActivityTask = nil

        if let activity = activities.first(where: { $0.id == id }), !activity.canRetry {
            registeredActivityActions.removeValue(forKey: id)
        }

        scheduleNextActivityIfNeeded()
    }

    private func activityIndex(for id: UUID) -> Int? {
        activities.firstIndex(where: { $0.id == id })
    }
}

private struct RegisteredActivityAction {
    let title: String
    let section: SidebarSection
    let kind: ActivityOperationKind
    let commandDescription: String
    let isRetryable: Bool
    let execute: @Sendable (_ activityID: UUID) async throws -> ActivityOperationOutcome
}
