import Foundation

@MainActor
final class AppRefreshController {
    private let appModel: AppModel
    private let containerCLIAdapter: ContainerCLIAdapter

    private var latestRelationshipHints: [ResourceRelationshipHint] = []
    private var sidebarSummarySyncTask: Task<Void, Never>?
    private var resourceRelationshipSyncTask: Task<Void, Never>?
    private var systemHealthSyncTask: Task<Void, Never>?
    private var manualRefreshTask: Task<Void, Never>?

    init(appModel: AppModel, containerCLIAdapter: ContainerCLIAdapter) {
        self.appModel = appModel
        self.containerCLIAdapter = containerCLIAdapter
    }

    func startIfNeeded() {
        startSidebarSummarySyncIfNeeded()
        startResourceRelationshipSyncIfNeeded()
        startSystemHealthSyncIfNeeded()
    }

    func refreshNow() {
        guard manualRefreshTask == nil else { return }

        manualRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSidebarSummaries()
            await self.refreshResourceRelationships()
            await self.refreshSystemHealthSnapshot()
            self.manualRefreshTask = nil
        }
    }

    private func startSidebarSummarySyncIfNeeded() {
        guard sidebarSummarySyncTask == nil else { return }

        sidebarSummarySyncTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSidebarSummaries()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: RefreshInterval.sidebarSummary)
                guard !Task.isCancelled else { return }
                await self.refreshSidebarSummaries()
            }
        }
    }

    private func startResourceRelationshipSyncIfNeeded() {
        guard resourceRelationshipSyncTask == nil else { return }

        resourceRelationshipSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshResourceRelationships()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: RefreshInterval.resourceRelationships)
                guard !Task.isCancelled else { return }
                await self.refreshResourceRelationships()
            }
        }
    }

    private func startSystemHealthSyncIfNeeded() {
        guard systemHealthSyncTask == nil else { return }

        systemHealthSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSystemHealthSnapshot()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: RefreshInterval.systemHealth)
                guard !Task.isCancelled else { return }
                await self.refreshSystemHealthSnapshot()
            }
        }
    }

    private func refreshSidebarSummaries() async {
        async let containersResult = try? containerCLIAdapter.listContainers()
        async let imagesResult = try? containerCLIAdapter.listImages()
        async let networksResult = try? containerCLIAdapter.listNetworks()
        async let volumesResult = try? containerCLIAdapter.listVolumes()
        async let registriesResult = try? containerCLIAdapter.listRegistries(format: "json", quiet: false)

        let (containers, images, networks, volumes, registries) = await (
            containersResult,
            imagesResult,
            networksResult,
            volumesResult,
            registriesResult
        )

        if let containers {
            if case .parsed(let value, _) = containers {
                appModel.cachedContainerItems = value
            }
            appModel.updateContainerSummary(from: containers)
        }

        if let images {
            if case .parsed(let value, _) = images {
                appModel.cachedImageItems = value
            }
            appModel.updateImageSummary(from: images)
        }

        if let networks {
            if case .parsed(let value, _) = networks {
                appModel.cachedNetworkItems = value
            }
            appModel.updateNetworkSummary(from: networks, relationships: latestRelationshipHints)
        }

        if let volumes {
            if case .parsed(let value, _) = volumes {
                appModel.cachedVolumeItems = value
            }
            appModel.updateVolumeSummary(from: volumes, relationships: latestRelationshipHints)
        }

        if let registries {
            appModel.registrySessionCount = registrySessionCount(from: registries)
        }
    }

    private func refreshResourceRelationships() async {
        let scan = await containerCLIAdapter.scanResourceRelationships()
        latestRelationshipHints = scan.hints

        guard !scan.hints.isEmpty else {
            if !appModel.cachedNetworkItems.isEmpty {
                appModel.updateNetworks(from: appModel.cachedNetworkItems)
            }
            if !appModel.cachedVolumeItems.isEmpty {
                appModel.updateVolumes(from: appModel.cachedVolumeItems)
            }
            return
        }

        if !appModel.cachedNetworkItems.isEmpty {
            appModel.updateNetworks(from: appModel.cachedNetworkItems, relationships: scan.hints)
        }

        if !appModel.cachedVolumeItems.isEmpty {
            appModel.updateVolumes(from: appModel.cachedVolumeItems, relationships: scan.hints)
        }
    }

    private func refreshSystemHealthSnapshot() async {
        let snapshot = await containerCLIAdapter.collectSystemHealthSnapshot()
        appModel.latestSystemHealthSnapshot = snapshot
        appModel.latestSystemHealthUpdatedAt = .now
    }

    private func registrySessionCount(from output: String) -> Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let data = trimmed.data(using: .utf8) else { return 0 }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return 0 }
        guard let array = object as? [[String: Any]] else { return 0 }
        return array.count
    }
}

private enum RefreshInterval {
    static let sidebarSummary: UInt64 = 5_000_000_000
    static let resourceRelationships: UInt64 = 30_000_000_000
    static let systemHealth: UInt64 = 30_000_000_000
}
