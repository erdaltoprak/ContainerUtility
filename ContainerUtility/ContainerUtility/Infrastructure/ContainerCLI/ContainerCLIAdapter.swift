import Foundation

struct ContainerSystemVersion: Decodable, Sendable {
    struct Server: Decodable, Sendable {
        let version: String
        let buildType: String
        let commit: String
        let appName: String
    }

    let version: String
    let buildType: String
    let commit: String
    let appName: String
    let server: Server?
}

struct ContainerFeatureSupport: Sendable {
    let supportsVersionJSON: Bool
    let supportsContainerListJSON: Bool
    let supportsImageListJSON: Bool
}

enum ContainerCompatibilityState: Sendable {
    case supported
    case unsupported(reason: String)
    case unavailable(reason: String)
}

struct ContainerCompatibilityReport: Sendable {
    let state: ContainerCompatibilityState
    let currentVersion: String?
    let policy: ContainerVersionPolicy
    let features: ContainerFeatureSupport
}

struct ContainerVersionPolicy: Sendable {
    let minimumSupported: SemanticVersion
    let maximumSupportedMajor: Int

    static let current = ContainerVersionPolicy(
        minimumSupported: SemanticVersion(major: 0, minor: 9, patch: 0),
        maximumSupportedMajor: 0
    )

    var supportedRangeDescription: String {
        "\(minimumSupported) ... < \(maximumSupportedMajor + 1).0.0"
    }
}

struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    static func parse(from raw: String) -> SemanticVersion? {
        let pattern = #/(\d+)\.(\d+)\.(\d+)/#
        guard let match = raw.firstMatch(of: pattern) else { return nil }
        guard
            let major = Int(match.output.1),
            let minor = Int(match.output.2),
            let patch = Int(match.output.3)
        else {
            return nil
        }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
}

struct ContainerListItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let state: String
    let image: String?
    let status: String?
}

struct ImageListItem: Identifiable, Hashable, Sendable {
    let id: String
    let reference: String
    let size: String?
    let created: String?
}

struct NetworkListItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let state: String?
    let mode: String?
    let ipv4Subnet: String?
    let ipv6Subnet: String?
    let ipv4Gateway: String?
    let plugin: String?
    let pluginVariant: String?
    let creationDate: Date?
    let labels: [String: String]
    let isBuiltin: Bool
}

struct VolumeListItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let driver: String?
    let format: String?
    let source: String?
    let sizeInBytes: Int64?
    let createdAt: Date?
    let labels: [String: String]
    let options: [String: String]
}

struct ImageInspectSnapshot: Sendable {
    let reference: String
    let rawJSON: String
    let digest: String?
    let mediaType: String?
    let sizeBytes: Int64?
    let variantCount: Int
    let created: String?
    let architecture: String?
    let operatingSystem: String?
}

struct NetworkInspectSnapshot: Sendable {
    let name: String
    let rawJSON: String
    let state: String?
    let mode: String?
    let ipv4Subnet: String?
    let ipv6Subnet: String?
    let ipv4Gateway: String?
    let plugin: String?
    let pluginVariant: String?
    let createdAt: Date?
    let labels: [String: String]
    let isBuiltin: Bool
}

struct VolumeInspectSnapshot: Sendable {
    let name: String
    let rawJSON: String
    let driver: String?
    let format: String?
    let source: String?
    let sizeInBytes: Int64?
    let createdAt: Date?
    let labels: [String: String]
    let options: [String: String]
}

struct ContainerCreateRequest: Sendable {
    let imageReference: String
    let name: String?
    let commandArguments: [String]
    let environment: [String: String]
    let publishedPorts: [String]
    let volumeMounts: [String]
    let network: String?
    let workingDirectory: String?
    let cpuCount: Int?
    let memory: String?
    let initializeContainer: Bool
    let initImageReference: String?
    let readOnlyRootFilesystem: Bool
    let removeWhenStopped: Bool
    let platform: String?
    let architecture: String?
    let operatingSystem: String?
    let virtualization: String?
    let useRosetta: Bool
    let enableDefaultSSHForwarding: Bool
    let sshAgents: [String]
    let environmentFiles: [String]
    let user: String?
    let uid: String?
    let gid: String?
    let mounts: [String]

    init(
        imageReference: String,
        name: String?,
        commandArguments: [String],
        environment: [String: String],
        publishedPorts: [String],
        volumeMounts: [String],
        network: String?,
        workingDirectory: String?,
        cpuCount: Int?,
        memory: String?,
        initializeContainer: Bool = false,
        initImageReference: String? = nil,
        readOnlyRootFilesystem: Bool = false,
        removeWhenStopped: Bool = false,
        platform: String? = nil,
        architecture: String? = nil,
        operatingSystem: String? = nil,
        virtualization: String? = nil,
        useRosetta: Bool = false,
        enableDefaultSSHForwarding: Bool = false,
        sshAgents: [String] = [],
        environmentFiles: [String] = [],
        user: String? = nil,
        uid: String? = nil,
        gid: String? = nil,
        mounts: [String] = []
    ) {
        self.imageReference = imageReference
        self.name = name
        self.commandArguments = commandArguments
        self.environment = environment
        self.publishedPorts = publishedPorts
        self.volumeMounts = volumeMounts
        self.network = network
        self.workingDirectory = workingDirectory
        self.cpuCount = cpuCount
        self.memory = memory
        self.initializeContainer = initializeContainer
        self.initImageReference = initImageReference
        self.readOnlyRootFilesystem = readOnlyRootFilesystem
        self.removeWhenStopped = removeWhenStopped
        self.platform = platform
        self.architecture = architecture
        self.operatingSystem = operatingSystem
        self.virtualization = virtualization
        self.useRosetta = useRosetta
        self.enableDefaultSSHForwarding = enableDefaultSSHForwarding
        self.sshAgents = sshAgents
        self.environmentFiles = environmentFiles
        self.user = user
        self.uid = uid
        self.gid = gid
        self.mounts = mounts
    }
}

struct ImagePushRequest: Sendable {
    let reference: String
    let scheme: String?
    let progress: String?
    let platform: String?
    let architecture: String?
    let operatingSystem: String?

    init(
        reference: String,
        scheme: String? = nil,
        progress: String? = nil,
        platform: String? = nil,
        architecture: String? = nil,
        operatingSystem: String? = nil
    ) {
        self.reference = reference
        self.scheme = scheme
        self.progress = progress
        self.platform = platform
        self.architecture = architecture
        self.operatingSystem = operatingSystem
    }
}

struct ContainerVolumeMount: Hashable, Sendable {
    let name: String
    let destination: String
}

struct ContainerInspectSnapshot: Sendable {
    let containerID: String
    let rawJSON: String
    let imageReference: String?
    let hostname: String?
    let networkAddress: String?
    let command: String?
    let cpuCount: Int?
    let memoryBytes: Int64?
    let configuredNetworkNames: [String]
    let attachedVolumes: [ContainerVolumeMount]
}

struct ContainerStatsSample: Sendable {
    let containerID: String
    let cpuUsageUsec: Int64?
    let memoryUsageBytes: Int64?
    let memoryLimitBytes: Int64?
    let networkRxBytes: Int64?
    let networkTxBytes: Int64?
    let blockReadBytes: Int64?
    let blockWriteBytes: Int64?
    let processCount: Int?
    let capturedAt: Date
}

struct DecodeDiagnostics: Sendable {
    var droppedRecords: Int = 0
    var warnings: [String] = []

    static let clean = DecodeDiagnostics()
}

enum NonCriticalDecodeResult<T: Sendable>: Sendable {
    case parsed(value: T, diagnostics: DecodeDiagnostics)
    case raw(output: String, diagnostics: DecodeDiagnostics)
}

struct ResourceRelationshipHint: Identifiable, Hashable, Sendable {
    let containerID: String
    let containerName: String
    let containerState: String
    let networks: [String]
    let volumeMounts: [ContainerVolumeMount]

    var id: String { containerID }
}

struct ResourceRelationshipScan: Sendable {
    let hints: [ResourceRelationshipHint]
    let warnings: [String]

    static let empty = ResourceRelationshipScan(hints: [], warnings: [])
}

enum EngineRuntimeState: String, Sendable {
    case running
    case stopped
    case unknown
}

struct StartupPreflightCheck: Identifiable, Sendable {
    enum Severity: Sendable {
        case pass
        case warning
        case failure
    }

    let id: String
    let title: String
    let detail: String
    let severity: Severity
}

enum ContainerInstallSource: Sendable {
    case officialPackage
    case homebrew
    case unknown

    var displayName: String {
        switch self {
        case .officialPackage:
            "Official signed package"
        case .homebrew:
            "Homebrew"
        case .unknown:
            "Unknown"
        }
    }
}

struct InstallApproach: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let recommended: Bool
    let steps: [String]
    let commands: [String]
}

struct InstallGuidance: Sendable {
    let summary: String
    let approaches: [InstallApproach]
}

struct ManagementGuidance: Sendable {
    let source: ContainerInstallSource
    let summary: String
    let steps: [String]
    let commands: [String]
}

struct SystemHealthSnapshot: Sendable {
    let compatibilityReport: ContainerCompatibilityReport
    let engineState: EngineRuntimeState
    let engineStatusDetail: String
    let cliVersionDisplay: String?
    let executablePath: String?
    let installSource: ContainerInstallSource?
    let preflightChecks: [StartupPreflightCheck]
    let installGuidance: InstallGuidance?
    let managementGuidance: ManagementGuidance?
}

struct ContainerCLIAdapter: Sendable {
    private let commandRunner: CommandRunner
    private let policy: ContainerVersionPolicy

    init(commandRunner: CommandRunner, policy: ContainerVersionPolicy = .current) {
        self.commandRunner = commandRunner
        self.policy = policy
    }

    func getCompatibilityReport() async -> ContainerCompatibilityReport {
        let executablePath = await resolveContainerExecutable()
        return await getCompatibilityReport(using: executablePath)
    }

    private func getCompatibilityReport(using executablePath: String?) async -> ContainerCompatibilityReport {
        do {
            let version = try await getSystemVersion(executablePath: executablePath)
            let features = evaluateFeatures(for: version)
            let state = evaluateCompatibility(for: version)
            return ContainerCompatibilityReport(
                state: state,
                currentVersion: version.version,
                policy: policy,
                features: features
            )
        } catch {
            return ContainerCompatibilityReport(
                state: .unavailable(reason: error.localizedDescription),
                currentVersion: nil,
                policy: policy,
                features: ContainerFeatureSupport(
                    supportsVersionJSON: false,
                    supportsContainerListJSON: false,
                    supportsImageListJSON: false
                )
            )
        }
    }

    func getSystemVersion() async throws -> ContainerSystemVersion {
        let executablePath = await resolveContainerExecutable()
        return try await getSystemVersion(executablePath: executablePath)
    }

    func fetchSystemVersionOutput(format: String = "json") async throws -> String {
        try await fetchSystemCommandOutput(arguments: ["system", "version", "--format", format])
    }

    func fetchSystemStatusOutput(format: String = "json") async throws -> String {
        try await fetchSystemCommandOutput(arguments: ["system", "status", "--format", format])
    }

    func fetchSystemDiskUsageOutput(format: String = "json") async throws -> String {
        try await fetchSystemCommandOutput(arguments: ["system", "df", "--format", format])
    }

    func fetchSystemLogs(last: String) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["system", "logs", "--last", last],
            timeout: 20
        )
        let result = try await commandRunner.runAllowingFailure(command)
        if result.exitCode == 0 {
            return result.stdout
        }

        let message = condensedCommandMessage(result)
        throw AppError.commandFailed(command: result.command, exitCode: result.exitCode, stderr: message)
    }

    private func getSystemVersion(executablePath: String?) async throws -> ContainerSystemVersion {
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["system", "version", "--format", "json"],
            timeout: 10
        )
        let result = try await commandRunner.run(command)
        do {
            let decoder = JSONDecoder()
            let data = Data(result.stdout.utf8)
            if let object = try? decoder.decode(ContainerSystemVersion.self, from: data) {
                return object
            }
            if let array = try? decoder.decode([ContainerSystemVersion].self, from: data), let first = array.first {
                return first
            }
            throw AppError.commandLaunchFailed(
                command: result.command,
                reason: "Unsupported version payload shape."
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.commandLaunchFailed(
                command: result.command,
                reason: "Unable to decode JSON output: \(error.localizedDescription)"
            )
        }
    }

    private func fetchSystemCommandOutput(arguments: [String]) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        return result.stdout
    }

    func listContainers() async throws -> NonCriticalDecodeResult<[ContainerListItem]> {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["list", "--all", "--format", "json"],
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        return decodeContainerList(from: result.stdout)
    }

    func listImages() async throws -> NonCriticalDecodeResult<[ImageListItem]> {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["image", "list", "--format", "json"],
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        return decodeImageList(from: result.stdout)
    }

    func listNetworks() async throws -> NonCriticalDecodeResult<[NetworkListItem]> {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["network", "list", "--format", "json"],
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        return decodeNetworkList(from: result.stdout)
    }

    func listVolumes() async throws -> NonCriticalDecodeResult<[VolumeListItem]> {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["volume", "list", "--format", "json"],
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        return decodeVolumeList(from: result.stdout)
    }

    func pullImage(reference: String) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container image pull", reason: "Reference is empty.")
        }

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["image", "pull", "--progress", "none", "--", trimmed],
            timeout: 180
        )
        _ = try await commandRunner.run(command)
    }

    func tagImage(sourceReference: String, targetReference: String) async throws {
        let source = sourceReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else {
            throw AppError.commandLaunchFailed(
                command: "container image tag",
                reason: "Source and target references are required."
            )
        }

        let executablePath = await resolveContainerExecutable()
        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: ["image", "tag", source, target],
            timeout: 60
        )
    }

    func pushImage(reference: String) async throws {
        try await pushImage(
            request: ImagePushRequest(
                reference: reference,
                progress: "none"
            )
        )
    }

    func pushImage(request: ImagePushRequest) async throws {
        let executablePath = await resolveContainerExecutable()
        let reference = request.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container image push", reason: "Reference is empty.")
        }

        var arguments = ["image", "push"]
        if let scheme = trimmedNonEmpty(request.scheme) {
            arguments.append(contentsOf: ["--scheme", scheme])
        }
        if let progress = trimmedNonEmpty(request.progress) {
            arguments.append(contentsOf: ["--progress", progress])
        }
        appendPlatformSelectionArguments(
            to: &arguments,
            platform: request.platform,
            architecture: request.architecture,
            operatingSystem: request.operatingSystem
        )
        arguments.append(reference)

        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 180
        )
    }

    func loginRegistry(
        server: String,
        username: String? = nil,
        password: String? = nil,
        usePasswordStdin: Bool = false
    ) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container registry login", reason: "Registry server is empty.")
        }

        var arguments = ["registry", "login"]
        if let username = trimmedNonEmpty(username) {
            arguments.append(contentsOf: ["--username", username])
        }
        if usePasswordStdin {
            arguments.append("--password-stdin")
        }
        arguments.append(trimmedServer)

        if usePasswordStdin, let password = trimmedNonEmpty(password) {
            try await runRegistryLoginWithPasswordStdin(
                executablePath: executablePath,
                arguments: arguments,
                password: password
            )
            return
        }

        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 60
        )
    }

    func logoutRegistry(registry: String) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedRegistry = registry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRegistry.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container registry logout", reason: "Registry value is empty.")
        }

        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: ["registry", "logout", trimmedRegistry],
            timeout: 30
        )
    }

    func listRegistries(format: String? = nil, quiet: Bool = false) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        guard !(quiet && trimmedNonEmpty(format) != nil) else {
            throw AppError.commandLaunchFailed(
                command: "container registry list",
                reason: "Use either --format or --quiet, not both."
            )
        }

        var arguments = ["registry", "list"]
        if quiet {
            arguments.append("--quiet")
        } else if let format = trimmedNonEmpty(format) {
            arguments.append(contentsOf: ["--format", format])
        }

        let result = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
        return result.stdout
    }

    func listSystemDNS() async throws -> String {
        let executablePath = await resolveContainerExecutable()
        let result = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: ["system", "dns", "list"],
            timeout: 15
        )
        return result.stdout
    }

    func createSystemDNS(entry: String, localhostIPv4: String? = nil) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container system dns create", reason: "DNS entry is empty.")
        }

        var arguments = ["system", "dns", "create"]
        if let localhostIPv4 = trimmedNonEmpty(localhostIPv4) {
            arguments.append(contentsOf: ["--localhost", localhostIPv4])
        }
        arguments.append(trimmedEntry)

        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
    }

    func deleteSystemDNS(entry: String, localhostIPv4: String? = nil) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container system dns delete", reason: "DNS entry is empty.")
        }

        var arguments = ["system", "dns", "delete"]
        if let localhostIPv4 = trimmedNonEmpty(localhostIPv4) {
            arguments.append(contentsOf: ["--localhost", localhostIPv4])
        }
        arguments.append(trimmedEntry)

        _ = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
    }

    func deleteImages(references: [String]) async throws {
        let references = references.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !references.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["image", "delete", "--"] + references,
            timeout: 60
        )
        _ = try await commandRunner.run(command)
    }

    func pruneImages(removeAllUnused: Bool) async throws {
        let executablePath = await resolveContainerExecutable()
        var arguments = ["image", "prune"]
        if removeAllUnused {
            arguments.append("--all")
        }
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 60
        )
        _ = try await commandRunner.run(command)
    }

    func inspectImage(reference: String) async throws -> ImageInspectSnapshot {
        let executablePath = await resolveContainerExecutable()
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["image", "inspect", "--", trimmed],
            timeout: 20
        )
        let result = try await commandRunner.run(command)
        let prettyJSON = prettyPrintedJSON(from: result.stdout) ?? result.stdout

        guard
            let rows = parseJSONArrayRows(from: result.stdout),
            let first = rows.first
        else {
            return ImageInspectSnapshot(
                reference: trimmed,
                rawJSON: prettyJSON,
                digest: nil,
                mediaType: nil,
                sizeBytes: nil,
                variantCount: 0,
                created: nil,
                architecture: nil,
                operatingSystem: nil
            )
        }

        let lookup = normalizeKeys(first)
        let index = nestedDictionary(lookup, key: "index")
        let variants = lookup["variants"] as? [[String: Any]] ?? []
        let firstVariant = variants.first.map(normalizeKeys) ?? [:]
        let config = nestedDictionary(firstVariant, key: "config")
        let platform = nestedDictionary(firstVariant, key: "platform")

        return ImageInspectSnapshot(
            reference: valueString(lookup, keys: ["name"]) ?? trimmed,
            rawJSON: prettyJSON,
            digest: valueString(index, keys: ["digest"]),
            mediaType: valueString(index, keys: ["mediatype"]),
            sizeBytes: valueInt64(index, keys: ["size"]) ?? valueInt64(firstVariant, keys: ["size"]),
            variantCount: variants.count,
            created: valueString(config, keys: ["created"]),
            architecture: valueString(platform, keys: ["architecture"]) ?? valueString(config, keys: ["architecture"]),
            operatingSystem: valueString(platform, keys: ["os"]) ?? valueString(config, keys: ["os"])
        )
    }

    func saveImages(
        references: [String],
        outputPath: String,
        platform: String? = nil
    ) async throws {
        let references = references.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let outputPath = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !references.isEmpty else { return }
        guard !outputPath.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container image save", reason: "Output path is empty.")
        }
        let executablePath = await resolveContainerExecutable()
        let resolvedPlatform = platform ?? Self.preferredImageSavePlatform()
        var arguments = ["image", "save"]
        if let resolvedPlatform {
            arguments.append(contentsOf: ["--platform", resolvedPlatform])
        }
        arguments.append(contentsOf: ["--output", outputPath])
        arguments.append("--")
        arguments.append(contentsOf: references)

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 180
        )
        _ = try await commandRunner.run(command)
    }

    func loadImages(inputPath: String) async throws {
        let inputPath = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputPath.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container image load", reason: "Input path is empty.")
        }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["image", "load", "--input", inputPath],
            timeout: 180
        )
        _ = try await commandRunner.run(command)
    }

    func createNetwork(
        name: String,
        ipv4Subnet: String? = nil,
        ipv6Subnet: String? = nil,
        labels: [String: String] = [:],
        isInternal: Bool = false
    ) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container network create", reason: "Name is empty.")
        }

        var arguments = ["network", "create"]
        for label in stableKeyValueArguments(from: labels) {
            arguments.append(contentsOf: ["--label", label])
        }

        if isInternal {
            arguments.append("--internal")
        }

        if let ipv4Subnet, !ipv4Subnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--subnet", ipv4Subnet.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        if let ipv6Subnet, !ipv6Subnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--subnet-v6", ipv6Subnet.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        arguments.append("--")
        arguments.append(trimmedName)

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func deleteNetworks(names: [String]) async throws {
        let names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["network", "delete", "--"] + names,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func inspectNetwork(name: String) async throws -> NetworkInspectSnapshot {
        let executablePath = await resolveContainerExecutable()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["network", "inspect", "--", trimmed],
            timeout: 20
        )
        let result = try await commandRunner.run(command)
        let prettyJSON = prettyPrintedJSON(from: result.stdout) ?? result.stdout

        guard
            let rows = parseJSONArrayRows(from: result.stdout),
            let first = rows.first
        else {
            return NetworkInspectSnapshot(
                name: trimmed,
                rawJSON: prettyJSON,
                state: nil,
                mode: nil,
                ipv4Subnet: nil,
                ipv6Subnet: nil,
                ipv4Gateway: nil,
                plugin: nil,
                pluginVariant: nil,
                createdAt: nil,
                labels: [:],
                isBuiltin: false
            )
        }

        let lookup = normalizeKeys(first)
        let config = nestedDictionary(lookup, key: "config")
        let status = nestedDictionary(lookup, key: "status")
        let pluginInfo = nestedDictionary(config, key: "plugininfo")
        let labels = valueStringDictionary(config, key: "labels")
        let builtinRole = labels["com.apple.container.resource.role"]?.lowercased() == "builtin"

        return NetworkInspectSnapshot(
            name: valueString(lookup, keys: ["id", "name"]) ?? valueString(config, keys: ["id", "name"]) ?? trimmed,
            rawJSON: prettyJSON,
            state: valueString(lookup, keys: ["state"]),
            mode: valueString(config, keys: ["mode"]),
            ipv4Subnet: valueString(status, keys: ["ipv4subnet"]) ?? valueString(config, keys: ["ipv4subnet"]),
            ipv6Subnet: valueString(status, keys: ["ipv6subnet"]) ?? valueString(config, keys: ["ipv6subnet"]),
            ipv4Gateway: valueString(status, keys: ["ipv4gateway"]),
            plugin: valueString(pluginInfo, keys: ["plugin"]),
            pluginVariant: valueString(pluginInfo, keys: ["variant"]),
            createdAt: valueDate(config, keys: ["creationdate"]),
            labels: labels,
            isBuiltin: builtinRole
        )
    }

    func createVolume(
        name: String,
        size: String? = nil,
        labels: [String: String] = [:],
        options: [String: String] = [:]
    ) async throws {
        let executablePath = await resolveContainerExecutable()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container volume create", reason: "Name is empty.")
        }

        var arguments = ["volume", "create"]
        for label in stableKeyValueArguments(from: labels) {
            arguments.append(contentsOf: ["--label", label])
        }
        for option in stableKeyValueArguments(from: options) {
            arguments.append(contentsOf: ["--opt", option])
        }
        if let size, !size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["-s", size.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        arguments.append("--")
        arguments.append(trimmedName)

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func deleteVolumes(names: [String]) async throws {
        let names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["volume", "delete", "--"] + names,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func pruneVolumes() async throws {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["volume", "prune"],
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func inspectVolume(name: String) async throws -> VolumeInspectSnapshot {
        let executablePath = await resolveContainerExecutable()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["volume", "inspect", "--", trimmed],
            timeout: 20
        )
        let result = try await commandRunner.run(command)
        let prettyJSON = prettyPrintedJSON(from: result.stdout) ?? result.stdout

        guard
            let rows = parseJSONArrayRows(from: result.stdout),
            let first = rows.first
        else {
            return VolumeInspectSnapshot(
                name: trimmed,
                rawJSON: prettyJSON,
                driver: nil,
                format: nil,
                source: nil,
                sizeInBytes: nil,
                createdAt: nil,
                labels: [:],
                options: [:]
            )
        }

        let lookup = normalizeKeys(first)
        return VolumeInspectSnapshot(
            name: valueString(lookup, keys: ["name"]) ?? trimmed,
            rawJSON: prettyJSON,
            driver: valueString(lookup, keys: ["driver"]),
            format: valueString(lookup, keys: ["format"]),
            source: valueString(lookup, keys: ["source"]),
            sizeInBytes: valueInt64(lookup, keys: ["sizeinbytes"]),
            createdAt: valueDate(lookup, keys: ["createdat"]),
            labels: valueStringDictionary(lookup, key: "labels"),
            options: valueStringDictionary(lookup, key: "options")
        )
    }

    func createContainer(request: ContainerCreateRequest) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        let imageReference = request.imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imageReference.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container create", reason: "Image reference is empty.")
        }

        var arguments = ["create"]

        let trimmedName = request.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            arguments.append(contentsOf: ["--name", trimmedName])
        }

        if let cpuCount = request.cpuCount, cpuCount > 0 {
            arguments.append(contentsOf: ["--cpus", String(cpuCount)])
        }

        if let memory = request.memory?.trimmingCharacters(in: .whitespacesAndNewlines), !memory.isEmpty {
            arguments.append(contentsOf: ["--memory", memory])
        }

        appendContainerRuntimeFlagArguments(to: &arguments, request: request)

        if let network = request.network?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            arguments.append(contentsOf: ["--network", network])
        }

        if let workingDirectory = request.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
            !workingDirectory.isEmpty
        {
            arguments.append(contentsOf: ["--workdir", workingDirectory])
        }

        for variable in stableKeyValueArguments(from: request.environment) {
            arguments.append(contentsOf: ["--env", variable])
        }

        for environmentFile in request.environmentFiles.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--env-file", environmentFile])
        }

        for publish in request.publishedPorts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--publish", publish])
        }

        for volume in request.volumeMounts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--volume", volume])
        }

        for mount in request.mounts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--mount", mount])
        }

        if let user = trimmedNonEmpty(request.user) {
            arguments.append(contentsOf: ["--user", user])
        }

        if let uid = trimmedNonEmpty(request.uid) {
            arguments.append(contentsOf: ["--uid", uid])
        }

        if let gid = trimmedNonEmpty(request.gid) {
            arguments.append(contentsOf: ["--gid", gid])
        }

        appendSSHArguments(
            to: &arguments,
            enableDefaultSSHForwarding: request.enableDefaultSSHForwarding,
            sshAgents: request.sshAgents
        )

        arguments.append("--")
        arguments.append(imageReference)
        arguments.append(contentsOf: request.commandArguments)

        let result = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 120
        )
        let createdID = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return createdID ?? trimmedName
    }

    func runContainer(request: ContainerCreateRequest, detached: Bool = true) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        let imageReference = request.imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imageReference.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container run", reason: "Image reference is empty.")
        }

        var arguments = ["run"]
        if detached {
            arguments.append("--detach")
        }

        let trimmedName = request.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            arguments.append(contentsOf: ["--name", trimmedName])
        }

        if let cpuCount = request.cpuCount, cpuCount > 0 {
            arguments.append(contentsOf: ["--cpus", String(cpuCount)])
        }

        if let memory = request.memory?.trimmingCharacters(in: .whitespacesAndNewlines), !memory.isEmpty {
            arguments.append(contentsOf: ["--memory", memory])
        }

        appendContainerRuntimeFlagArguments(to: &arguments, request: request)

        if let network = request.network?.trimmingCharacters(in: .whitespacesAndNewlines), !network.isEmpty {
            arguments.append(contentsOf: ["--network", network])
        }

        if let workingDirectory = request.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
            !workingDirectory.isEmpty
        {
            arguments.append(contentsOf: ["--workdir", workingDirectory])
        }

        for variable in stableKeyValueArguments(from: request.environment) {
            arguments.append(contentsOf: ["--env", variable])
        }

        for environmentFile in request.environmentFiles.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--env-file", environmentFile])
        }

        for publish in request.publishedPorts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--publish", publish])
        }

        for volume in request.volumeMounts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--volume", volume])
        }

        for mount in request.mounts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty })
        {
            arguments.append(contentsOf: ["--mount", mount])
        }

        if let user = trimmedNonEmpty(request.user) {
            arguments.append(contentsOf: ["--user", user])
        }

        if let uid = trimmedNonEmpty(request.uid) {
            arguments.append(contentsOf: ["--uid", uid])
        }

        if let gid = trimmedNonEmpty(request.gid) {
            arguments.append(contentsOf: ["--gid", gid])
        }

        appendSSHArguments(
            to: &arguments,
            enableDefaultSSHForwarding: request.enableDefaultSSHForwarding,
            sshAgents: request.sshAgents
        )

        arguments.append("--")
        arguments.append(imageReference)
        arguments.append(contentsOf: request.commandArguments)

        let result = try await runContainerCommandAllowingRawFailure(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 120
        )
        let containerID = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return containerID ?? trimmedName
    }

    func startContainers(ids: [String]) async throws {
        let executablePath = await resolveContainerExecutable()
        for id in ids {
            let command = makeContainerCommand(
                executablePath: executablePath,
                arguments: ["start", "--", id],
                timeout: 30
            )
            _ = try await commandRunner.run(command)
        }
    }

    func stopContainers(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["stop", "--"] + ids,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func restartContainers(ids: [String]) async throws {
        for id in ids {
            try await stopContainers(ids: [id])
            try await startContainers(ids: [id])
        }
    }

    func killContainers(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["kill", "--"] + ids,
            timeout: 20
        )
        _ = try await commandRunner.run(command)
    }

    func deleteContainers(ids: [String], force: Bool = false) async throws {
        guard !ids.isEmpty else { return }
        let executablePath = await resolveContainerExecutable()
        var arguments = ["delete"]
        if force {
            arguments.append("--force")
        }
        arguments.append("--")
        arguments.append(contentsOf: ids)

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func pruneContainers() async throws {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["prune"],
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func inspectContainer(id: String) async throws -> ContainerInspectSnapshot {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["inspect", "--", id],
            timeout: 15
        )
        let result = try await commandRunner.run(command)
        let prettyJSON = prettyPrintedJSON(from: result.stdout) ?? result.stdout

        guard
            let rows = parseJSONArrayRows(from: result.stdout),
            let first = rows.first
        else {
            return ContainerInspectSnapshot(
                containerID: id,
                rawJSON: prettyJSON,
                imageReference: nil,
                hostname: nil,
                networkAddress: nil,
                command: nil,
                cpuCount: nil,
                memoryBytes: nil,
                configuredNetworkNames: [],
                attachedVolumes: []
            )
        }

        let lookup = normalizeKeys(first)
        let configuration = nestedDictionary(lookup, key: "configuration")
        let image = nestedDictionary(configuration, key: "image")
        let resources = nestedDictionary(configuration, key: "resources")
        let initProcess = nestedDictionary(configuration, key: "initprocess")
        let networks = lookup["networks"] as? [[String: Any]]
        let firstNetwork = networks?.first.map(normalizeKeys) ?? [:]
        let processCommand = commandText(from: initProcess)
        let configuredNetworks = valueDictionaryArray(configuration, key: "networks")
            .compactMap { valueString(normalizeKeys($0), keys: ["network", "name", "id"]) }
        let attachedVolumes: [ContainerVolumeMount] = valueDictionaryArray(configuration, key: "mounts")
            .compactMap { mount -> ContainerVolumeMount? in
                let normalizedMount = normalizeKeys(mount)
                let type = nestedDictionary(normalizedMount, key: "type")
                let volume = nestedDictionary(type, key: "volume")
                guard let name = valueString(volume, keys: ["name"]) else {
                    return nil
                }
                return ContainerVolumeMount(
                    name: name,
                    destination: valueString(normalizedMount, keys: ["destination", "target"]) ?? ""
                )
            }

        return ContainerInspectSnapshot(
            containerID: id,
            rawJSON: prettyJSON,
            imageReference: valueString(image, keys: ["reference"]),
            hostname: valueString(firstNetwork, keys: ["hostname"]),
            networkAddress: valueString(firstNetwork, keys: ["ipv4address", "ipv6address"]),
            command: processCommand,
            cpuCount: valueInt(resources, keys: ["cpus"]),
            memoryBytes: valueInt64(resources, keys: ["memoryinbytes"]),
            configuredNetworkNames: configuredNetworks,
            attachedVolumes: attachedVolumes
        )
    }

    func scanResourceRelationships() async -> ResourceRelationshipScan {
        var warnings: [String] = []

        let containersResult: NonCriticalDecodeResult<[ContainerListItem]>
        do {
            containersResult = try await listContainers()
        } catch {
            return ResourceRelationshipScan(
                hints: [],
                warnings: ["Relationship hints unavailable: \(error.localizedDescription)"]
            )
        }

        let containers: [ContainerListItem]
        switch containersResult {
        case .parsed(let value, let diagnostics):
            containers = value
            warnings.append(contentsOf: diagnostics.warnings)
        case .raw(_, let diagnostics):
            warnings.append(contentsOf: diagnostics.warnings)
            warnings.append("Relationship hints unavailable because container metadata could not be parsed.")
            return ResourceRelationshipScan(hints: [], warnings: warnings)
        }

        var hints: [ResourceRelationshipHint] = []
        for container in containers {
            do {
                let snapshot = try await inspectContainer(id: container.id)
                hints.append(
                    ResourceRelationshipHint(
                        containerID: container.id,
                        containerName: container.name,
                        containerState: container.state,
                        networks: snapshot.configuredNetworkNames,
                        volumeMounts: snapshot.attachedVolumes
                    )
                )
            } catch {
                warnings.append("Could not inspect container \(container.name). Relationship hints may be incomplete.")
            }
        }

        return ResourceRelationshipScan(hints: hints, warnings: warnings)
    }

    func fetchContainerLogs(id: String, tail: Int, boot: Bool = false) async throws -> String {
        let executablePath = await resolveContainerExecutable()
        var arguments = ["logs", "-n", String(max(1, min(tail, 500)))]
        if boot {
            arguments.insert("--boot", at: 1)
        }
        arguments.append("--")
        arguments.append(id)

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: 15
        )
        let result = try await commandRunner.runAllowingFailure(command)

        if result.exitCode == 0 {
            return result.stdout
        }

        let message = condensedCommandMessage(result)
        throw AppError.commandFailed(command: result.command, exitCode: result.exitCode, stderr: message)
    }

    func fetchContainerStats(id: String) async throws -> ContainerStatsSample? {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["stats", "--format", "json", "--no-stream", "--", id],
            timeout: 15
        )
        let result = try await commandRunner.run(command)

        guard
            let rows = parseJSONArrayRows(from: result.stdout),
            let first = rows.first
        else {
            return nil
        }

        let lookup = normalizeKeys(first)
        return ContainerStatsSample(
            containerID: valueString(lookup, keys: ["id"]) ?? id,
            cpuUsageUsec: valueInt64(lookup, keys: ["cpuusageusec"]),
            memoryUsageBytes: valueInt64(lookup, keys: ["memoryusagebytes"]),
            memoryLimitBytes: valueInt64(lookup, keys: ["memorylimitbytes"]),
            networkRxBytes: valueInt64(lookup, keys: ["networkrxbytes"]),
            networkTxBytes: valueInt64(lookup, keys: ["networktxbytes"]),
            blockReadBytes: valueInt64(lookup, keys: ["blockreadbytes"]),
            blockWriteBytes: valueInt64(lookup, keys: ["blockwritebytes"]),
            processCount: valueInt(lookup, keys: ["numprocesses"]),
            capturedAt: .now
        )
    }

    func executeInContainer(id: String, commandText: String) async throws -> CommandResult {
        let executablePath = await resolveContainerExecutable()
        let shellCommand = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shellCommand.isEmpty else {
            throw AppError.commandLaunchFailed(command: "container exec", reason: "Command is empty.")
        }

        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["exec", "--", id, "/bin/sh", "-lc", shellCommand],
            timeout: 20
        )
        return try await commandRunner.run(command)
    }

    func startSystem() async throws {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["system", "start", "--disable-kernel-install"],
            timeout: 45
        )
        _ = try await commandRunner.run(command)
    }

    func stopSystem() async throws {
        let executablePath = await resolveContainerExecutable()
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: ["system", "stop"],
            timeout: 30
        )
        _ = try await commandRunner.run(command)
    }

    func collectSystemHealthSnapshot() async -> SystemHealthSnapshot {
        let executablePath = await resolveContainerExecutable()
        let homebrewPath = await resolveCommandPath("brew")

        guard let executablePath else {
            let compatibilityReport = ContainerCompatibilityReport(
                state: .unavailable(reason: "container CLI is not installed or not on PATH."),
                currentVersion: nil,
                policy: policy,
                features: ContainerFeatureSupport(
                    supportsVersionJSON: false,
                    supportsContainerListJSON: false,
                    supportsImageListJSON: false
                )
            )

            let checks = [
                StartupPreflightCheck(
                    id: "binary",
                    title: "Binary presence",
                    detail: "`container` binary was not found on PATH.",
                    severity: .failure
                ),
                StartupPreflightCheck(
                    id: "sanity",
                    title: "Command sanity",
                    detail: "Skipped because binary is missing.",
                    severity: .warning
                ),
                StartupPreflightCheck(
                    id: "compatibility",
                    title: "Version compatibility",
                    detail: "Skipped because binary is missing.",
                    severity: .warning
                ),
                StartupPreflightCheck(
                    id: "engine",
                    title: "Engine reachability",
                    detail: "Skipped because binary is missing.",
                    severity: .warning
                ),
            ]

            return SystemHealthSnapshot(
                compatibilityReport: compatibilityReport,
                engineState: .unknown,
                engineStatusDetail: "Install the `container` CLI to continue.",
                cliVersionDisplay: nil,
                executablePath: nil,
                installSource: nil,
                preflightChecks: checks,
                installGuidance: makeInstallGuidance(homebrewPath: homebrewPath),
                managementGuidance: nil
            )
        }

        let installSource = await resolveInstallSource(for: executablePath, homebrewPath: homebrewPath)
        let compatibilityReport = await getCompatibilityReport(using: executablePath)
        let versionDisplay = compatibilityReport.currentVersion

        let statusResult: CommandResult?
        do {
            let command = makeContainerCommand(
                executablePath: executablePath,
                arguments: ["system", "status"],
                timeout: 10
            )
            statusResult = try await commandRunner.runAllowingFailure(command)
        } catch {
            statusResult = nil
        }

        let runtimeState = inferEngineState(from: statusResult)
        let statusDetail = engineStatusText(from: statusResult)

        let checks = buildChecks(
            executablePath: executablePath,
            compatibilityReport: compatibilityReport,
            statusResult: statusResult
        )

        return SystemHealthSnapshot(
            compatibilityReport: compatibilityReport,
            engineState: runtimeState,
            engineStatusDetail: statusDetail,
            cliVersionDisplay: versionDisplay,
            executablePath: executablePath,
            installSource: installSource,
            preflightChecks: checks,
            installGuidance: nil,
            managementGuidance: makeManagementGuidance(
                source: installSource,
                executablePath: executablePath
            )
        )
    }

    private func evaluateCompatibility(for version: ContainerSystemVersion) -> ContainerCompatibilityState {
        guard let semanticVersion = SemanticVersion.parse(from: version.version) else {
            return .unsupported(
                reason:
                    "Unable to parse CLI version '\(version.version)'. Supported range: \(policy.supportedRangeDescription)."
            )
        }

        if semanticVersion < policy.minimumSupported {
            return .unsupported(
                reason: "Installed version \(semanticVersion) is below minimum supported \(policy.minimumSupported)."
            )
        }

        if semanticVersion.major > policy.maximumSupportedMajor {
            return .unsupported(
                reason:
                    "Installed major version \(semanticVersion.major) is above supported major \(policy.maximumSupportedMajor)."
            )
        }

        return .supported
    }

    private func evaluateFeatures(for version: ContainerSystemVersion) -> ContainerFeatureSupport {
        guard let semanticVersion = SemanticVersion.parse(from: version.version) else {
            return ContainerFeatureSupport(
                supportsVersionJSON: false,
                supportsContainerListJSON: false,
                supportsImageListJSON: false
            )
        }

        let jsonOutputsSupported = semanticVersion >= SemanticVersion(major: 0, minor: 26, patch: 0)
        return ContainerFeatureSupport(
            supportsVersionJSON: jsonOutputsSupported,
            supportsContainerListJSON: jsonOutputsSupported,
            supportsImageListJSON: jsonOutputsSupported
        )
    }

    private func resolveCommandPath(_ commandName: String) async -> String? {
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        guard !commandName.isEmpty, commandName.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return nil
        }

        let environmentPATH = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let defaultPATH =
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/opt/local/bin:\(NSHomeDirectory())/.local/bin"
        let searchPATH = environmentPATH.isEmpty ? defaultPATH : "\(environmentPATH):\(defaultPATH)"

        let directories =
            searchPATH
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(commandName).path
            if isUsableExecutablePath(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func resolveContainerExecutable() async -> String? {
        if let discovered = await resolveCommandPath("container"), isUsableExecutablePath(discovered) {
            return discovered
        }

        let fallbackCandidates = [
            "/opt/homebrew/bin/container",
            "/usr/local/bin/container",
            "/usr/bin/container",
            "/opt/local/bin/container",
            "\(NSHomeDirectory())/.local/bin/container",
        ]

        for candidate in fallbackCandidates where isUsableExecutablePath(candidate) {
            return candidate
        }

        return nil
    }

    private func isUsableExecutablePath(_ path: String) -> Bool {
        path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path)
    }

    private func resolveInstallSource(
        for executablePath: String,
        homebrewPath: String?
    ) async -> ContainerInstallSource {
        let canonicalExecutablePath = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath()
            .path

        let homebrewInstalled = await isHomebrewFormulaInstalled(homebrewPath: homebrewPath)
        let officialPackageInstalled = await hasOfficialPackageReceipt()

        if homebrewInstalled {
            if executablePath.hasPrefix("/opt/homebrew/")
                || canonicalExecutablePath.contains("/Cellar/container/")
                || canonicalExecutablePath.contains("/Homebrew/Cellar/container/")
            {
                return .homebrew
            }
        }

        if officialPackageInstalled && normalizedPath(executablePath) == "/usr/local/bin/container" {
            return .officialPackage
        }

        if homebrewInstalled && !officialPackageInstalled {
            return .homebrew
        }

        if officialPackageInstalled && !homebrewInstalled {
            return .officialPackage
        }

        return .unknown
    }

    private func isHomebrewFormulaInstalled(homebrewPath: String?) async -> Bool {
        guard let brewExecutable = homebrewPath, isUsableExecutablePath(brewExecutable) else {
            return false
        }

        let command = CLICommand(
            executable: brewExecutable,
            arguments: ["list", "--versions", "container"],
            timeout: 5
        )

        do {
            let result = try await commandRunner.runAllowingFailure(command)
            return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    private func hasOfficialPackageReceipt() async -> Bool {
        let command = CLICommand(
            executable: "/usr/sbin/pkgutil",
            arguments: ["--pkg-info", "com.apple.container-installer"],
            timeout: 5
        )

        do {
            let result = try await commandRunner.runAllowingFailure(command)
            return result.exitCode == 0
        } catch {
            return false
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func makeContainerCommand(
        executablePath: String?,
        arguments: [String],
        timeout: TimeInterval
    ) -> CLICommand {
        let resolvedExecutable = executablePath ?? "/usr/bin/container"
        return CLICommand(
            executable: resolvedExecutable,
            arguments: arguments,
            timeout: timeout
        )
    }

    private func runContainerCommandAllowingRawFailure(
        executablePath: String?,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult {
        let command = makeContainerCommand(
            executablePath: executablePath,
            arguments: arguments,
            timeout: timeout
        )
        let result = try await commandRunner.runAllowingFailure(command)
        guard result.exitCode == 0 else {
            throw AppError.commandFailed(
                command: result.command,
                exitCode: result.exitCode,
                stderr: condensedCommandMessage(result)
            )
        }
        return result
    }

    private func runRegistryLoginWithPasswordStdin(
        executablePath: String?,
        arguments: [String],
        password: String
    ) async throws {
        let resolvedExecutable = executablePath ?? "/usr/bin/container"
        let executable = shellEscaped(resolvedExecutable)
        let escapedArguments = arguments.map(shellEscaped).joined(separator: " ")
        let script = "printf '%s' \"$CONTAINER_UTILITY_REGISTRY_PASSWORD\" | \(executable) \(escapedArguments)"

        let command = CLICommand(
            executable: "/bin/sh",
            arguments: ["-lc", script],
            environment: [
                "CONTAINER_UTILITY_REGISTRY_PASSWORD": password
            ],
            timeout: 60
        )
        let result = try await commandRunner.runAllowingFailure(command)
        guard result.exitCode == 0 else {
            throw AppError.commandFailed(
                command: result.command,
                exitCode: result.exitCode,
                stderr: condensedCommandMessage(result)
            )
        }
    }

    private func appendContainerRuntimeFlagArguments(
        to arguments: inout [String],
        request: ContainerCreateRequest
    ) {
        if request.initializeContainer {
            arguments.append("--init")
        }

        if let initImage = trimmedNonEmpty(request.initImageReference) {
            arguments.append(contentsOf: ["--init-image", initImage])
        }

        if request.readOnlyRootFilesystem {
            arguments.append("--read-only")
        }

        if request.removeWhenStopped {
            arguments.append("--rm")
        }

        appendPlatformSelectionArguments(
            to: &arguments,
            platform: request.platform,
            architecture: request.architecture,
            operatingSystem: request.operatingSystem
        )

        if let virtualization = trimmedNonEmpty(request.virtualization) {
            arguments.append(contentsOf: ["--virtualization", virtualization])
        }

        if request.useRosetta {
            arguments.append("--rosetta")
        }
    }

    private func appendPlatformSelectionArguments(
        to arguments: inout [String],
        platform: String?,
        architecture: String?,
        operatingSystem: String?
    ) {
        if let platform = trimmedNonEmpty(platform) {
            arguments.append(contentsOf: ["--platform", platform])
            return
        }

        if let architecture = trimmedNonEmpty(architecture) {
            arguments.append(contentsOf: ["--arch", architecture])
        }

        if let operatingSystem = trimmedNonEmpty(operatingSystem) {
            arguments.append(contentsOf: ["--os", operatingSystem])
        }
    }

    private func appendSSHArguments(
        to arguments: inout [String],
        enableDefaultSSHForwarding: Bool,
        sshAgents: [String]
    ) {
        if enableDefaultSSHForwarding {
            arguments.append("--ssh")
        }

        for sshAgent in sshAgents.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            arguments.append(contentsOf: ["--ssh", sshAgent])
        }
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func makeInstallGuidance(homebrewPath: String?) -> InstallGuidance {
        var approaches: [InstallApproach] = [
            InstallApproach(
                id: "official",
                title: "Official signed release (.pkg)",
                summary:
                    "Recommended path from the upstream `apple/container` README. Installs under `/usr/local` and includes vendor update/uninstall scripts.",
                recommended: true,
                steps: [
                    "Download the latest signed installer package from the GitHub releases page.",
                    "Install it in Finder or headlessly with `installer`.",
                    "Start the `container` services after install.",
                    "If the first container launch reports that no default arm64 kernel is configured, install the recommended kernel once and retry.",
                ],
                commands: [
                    "open https://github.com/apple/container/releases",
                    "sudo installer -pkg /path/to/container-<version>-installer-signed.pkg -target /",
                    "container system start",
                    "container system kernel set --recommended",
                ]
            )
        ]

        var homebrewSteps = [
            "Install the `container` formula with Homebrew.",
            "Start the `container` services after install.",
            "If the first container launch reports that no default arm64 kernel is configured, install the recommended kernel once and retry.",
        ]
        var homebrewCommands = [
            "brew install container",
            "container system start",
            "container system kernel set --recommended",
        ]

        if homebrewPath == nil {
            homebrewSteps.insert("Install Homebrew first if you want the formula-managed path.", at: 0)
            homebrewCommands.insert(
                "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                at: 0
            )
        }

        approaches.append(
            InstallApproach(
                id: "homebrew",
                title: "Homebrew formula",
                summary: homebrewPath.map {
                    "Alternative path detected on this Mac at \($0)."
                } ?? "Alternative path if you prefer formula-based install and upgrades.",
                recommended: false,
                steps: homebrewSteps,
                commands: homebrewCommands
            )
        )

        return InstallGuidance(
            summary:
                "The `container` CLI is not installed. You can install it either from the official signed release or via Homebrew.",
            approaches: approaches
        )
    }

    private func makeManagementGuidance(
        source: ContainerInstallSource,
        executablePath: String
    ) -> ManagementGuidance {
        switch source {
        case .officialPackage:
            return ManagementGuidance(
                source: source,
                summary:
                    "This install is managed by the official signed package. Use the vendor scripts under `/usr/local/bin` for bootstrap, upgrades, and uninstall.",
                steps: [
                    "Bootstrap the runtime after install with `container system start`.",
                    "If container launch reports a missing default kernel, run `container system kernel set --recommended` once.",
                    "Stop the engine before upgrading or downgrading.",
                    "Use the vendor update script for upgrades.",
                    "Use the vendor uninstall script to remove the CLI, keeping or deleting user data.",
                ],
                commands: [
                    "container system start",
                    "container system kernel set --recommended",
                    "container system stop",
                    "/usr/local/bin/update-container.sh",
                    "/usr/local/bin/uninstall-container.sh -k",
                    "/usr/local/bin/uninstall-container.sh -d",
                ]
            )
        case .homebrew:
            return ManagementGuidance(
                source: source,
                summary:
                    "This install is managed by Homebrew. Use brew to install, bootstrap, upgrade, or uninstall it.",
                steps: [
                    "Bootstrap the runtime after install with `container system start`.",
                    "If container launch reports a missing default kernel, run `container system kernel set --recommended` once.",
                    "Use Homebrew to upgrade the installed formula.",
                    "Use Homebrew to uninstall it if you want to remove the CLI.",
                    "Restart or refresh the app after package changes.",
                ],
                commands: [
                    "container system start",
                    "container system kernel set --recommended",
                    "brew upgrade container",
                    "brew uninstall container",
                ]
            )
        case .unknown:
            return ManagementGuidance(
                source: source,
                summary:
                    "The CLI is installed at \(executablePath), but the install source could not be classified confidently.",
                steps: [
                    "Bootstrap the runtime after install with `container system start`.",
                    "If container launch reports a missing default kernel, run `container system kernel set --recommended` once.",
                    "Use the executable path as the primary clue for how this copy was installed.",
                    "If you expected the official package, check the pkg receipt.",
                    "If you expected Homebrew, check the formula state.",
                ],
                commands: [
                    "container system start",
                    "container system kernel set --recommended",
                    "pkgutil --pkg-info com.apple.container-installer",
                    "brew list --versions container",
                ]
            )
        }
    }

    private func buildChecks(
        executablePath: String,
        compatibilityReport: ContainerCompatibilityReport,
        statusResult: CommandResult?
    ) -> [StartupPreflightCheck] {
        var checks: [StartupPreflightCheck] = []

        checks.append(
            StartupPreflightCheck(
                id: "binary",
                title: "Binary presence",
                detail: "`container` found at \(executablePath)",
                severity: .pass
            )
        )

        switch compatibilityReport.state {
        case .supported:
            checks.append(
                StartupPreflightCheck(
                    id: "sanity",
                    title: "Command sanity",
                    detail: "Basic CLI commands succeeded.",
                    severity: .pass
                )
            )
            checks.append(
                StartupPreflightCheck(
                    id: "compatibility",
                    title: "Version compatibility",
                    detail:
                        "Version is within supported policy \(compatibilityReport.policy.supportedRangeDescription).",
                    severity: .pass
                )
            )
        case .unsupported(let reason):
            checks.append(
                StartupPreflightCheck(
                    id: "sanity",
                    title: "Command sanity",
                    detail: "Basic CLI commands succeeded.",
                    severity: .pass
                )
            )
            checks.append(
                StartupPreflightCheck(
                    id: "compatibility",
                    title: "Version compatibility",
                    detail: reason,
                    severity: .failure
                )
            )
        case .unavailable(let reason):
            checks.append(
                StartupPreflightCheck(
                    id: "sanity",
                    title: "Command sanity",
                    detail: reason,
                    severity: .failure
                )
            )
            checks.append(
                StartupPreflightCheck(
                    id: "compatibility",
                    title: "Version compatibility",
                    detail: "Skipped because version information could not be collected.",
                    severity: .warning
                )
            )
        }

        if let statusResult {
            if statusResult.exitCode == 0 {
                checks.append(
                    StartupPreflightCheck(
                        id: "engine",
                        title: "Engine reachability",
                        detail: "Engine status command succeeded.",
                        severity: .pass
                    )
                )
            } else {
                checks.append(
                    StartupPreflightCheck(
                        id: "engine",
                        title: "Engine reachability",
                        detail: condensedStatusMessage(from: statusResult),
                        severity: .failure
                    )
                )
            }
        } else {
            checks.append(
                StartupPreflightCheck(
                    id: "engine",
                    title: "Engine reachability",
                    detail: "Unable to run `container system status`.",
                    severity: .warning
                )
            )
        }

        return checks
    }

    private func inferEngineState(from statusResult: CommandResult?) -> EngineRuntimeState {
        guard let statusResult else { return .unknown }
        if statusResult.exitCode == 0 {
            return .running
        }
        let message = condensedStatusMessage(from: statusResult).lowercased()
        if message.contains("not running") || message.contains("stopped") {
            return .stopped
        }
        return .unknown
    }

    private func engineStatusText(from statusResult: CommandResult?) -> String {
        guard let statusResult else {
            return "Unable to determine engine status."
        }
        if statusResult.exitCode == 0 {
            return "Engine status is reachable."
        }
        return condensedStatusMessage(from: statusResult)
    }

    private func condensedStatusMessage(from statusResult: CommandResult) -> String {
        let message = (statusResult.stderr.isEmpty ? statusResult.stdout : statusResult.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Command failed with exit code \(statusResult.exitCode)."
        }
        return message
    }

    private func condensedCommandMessage(_ result: CommandResult) -> String {
        let message = [result.stderr, result.stdout]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Command failed with exit code \(result.exitCode)."
        }
        return message
    }

    private func decodeContainerList(from output: String) -> NonCriticalDecodeResult<[ContainerListItem]> {
        guard let rows = parseJSONArrayRows(from: output) else {
            return .raw(
                output: output,
                diagnostics: DecodeDiagnostics(
                    droppedRecords: 0,
                    warnings: ["Container list JSON decoding failed; falling back to raw output."]
                )
            )
        }
        if rows.isEmpty {
            return .parsed(value: [], diagnostics: .clean)
        }

        var diagnostics = DecodeDiagnostics.clean
        var items: [ContainerListItem] = []

        for row in rows {
            let lookup = normalizeKeys(row)
            let configuration = nestedDictionary(lookup, key: "configuration")
            let image = nestedDictionary(configuration, key: "image")
            let networks = lookup["networks"] as? [[String: Any]]
            let firstNetwork = networks?.first.map(normalizeKeys)

            guard
                let id = valueString(lookup, keys: ["id", "containerid"])
                    ?? valueString(configuration, keys: ["id", "containerid"]),
                let state = valueString(lookup, keys: ["state", "status"])
            else {
                diagnostics.droppedRecords += 1
                continue
            }

            let name =
                valueString(lookup, keys: ["name", "names"])
                ?? valueString(firstNetwork ?? [:], keys: ["hostname"])
                ?? valueString(configuration, keys: ["id"])
                ?? id

            items.append(
                ContainerListItem(
                    id: id,
                    name: name,
                    state: state,
                    image: valueString(lookup, keys: ["image", "imagename"])
                        ?? valueString(image, keys: ["reference"]),
                    status: valueString(lookup, keys: ["status", "summary"])
                )
            )
        }

        if items.isEmpty {
            diagnostics.warnings.append("No decodable container rows were found; returning raw output.")
            return .raw(output: output, diagnostics: diagnostics)
        }

        if diagnostics.droppedRecords > 0 {
            diagnostics.warnings.append("Dropped \(diagnostics.droppedRecords) malformed container rows.")
        }
        return .parsed(value: items, diagnostics: diagnostics)
    }

    private func decodeImageList(from output: String) -> NonCriticalDecodeResult<[ImageListItem]> {
        guard let rows = parseJSONArrayRows(from: output) else {
            return .raw(
                output: output,
                diagnostics: DecodeDiagnostics(
                    droppedRecords: 0,
                    warnings: ["Image list JSON decoding failed; falling back to raw output."]
                )
            )
        }
        if rows.isEmpty {
            return .parsed(value: [], diagnostics: .clean)
        }

        var diagnostics = DecodeDiagnostics.clean
        var items: [ImageListItem] = []

        for row in rows {
            let lookup = normalizeKeys(row)
            let descriptor = nestedDictionary(lookup, key: "descriptor")

            guard
                let id = valueString(lookup, keys: ["id", "digest", "imageid"])
                    ?? valueString(descriptor, keys: ["digest"]),
                let reference = valueString(lookup, keys: ["name", "reference", "repository", "tag"])
            else {
                diagnostics.droppedRecords += 1
                continue
            }

            items.append(
                ImageListItem(
                    id: id,
                    reference: reference,
                    size: valueString(lookup, keys: ["fullsize", "size", "virtualsize"])
                        ?? valueInt64(descriptor, keys: ["size"]).map(String.init),
                    created: valueString(lookup, keys: ["created", "createdat"])
                )
            )
        }

        if items.isEmpty {
            diagnostics.warnings.append("No decodable image rows were found; returning raw output.")
            return .raw(output: output, diagnostics: diagnostics)
        }

        if diagnostics.droppedRecords > 0 {
            diagnostics.warnings.append("Dropped \(diagnostics.droppedRecords) malformed image rows.")
        }
        return .parsed(value: items, diagnostics: diagnostics)
    }

    private func decodeNetworkList(from output: String) -> NonCriticalDecodeResult<[NetworkListItem]> {
        guard let rows = parseJSONArrayRows(from: output) else {
            return .raw(
                output: output,
                diagnostics: DecodeDiagnostics(
                    droppedRecords: 0,
                    warnings: ["Network list JSON decoding failed; falling back to raw output."]
                )
            )
        }
        if rows.isEmpty {
            return .parsed(value: [], diagnostics: .clean)
        }

        var diagnostics = DecodeDiagnostics.clean
        var items: [NetworkListItem] = []

        for row in rows {
            let lookup = normalizeKeys(row)
            let config = nestedDictionary(lookup, key: "config")
            let status = nestedDictionary(lookup, key: "status")
            let pluginInfo = nestedDictionary(config, key: "plugininfo")
            let labels = valueStringDictionary(config, key: "labels")

            guard let name = valueString(lookup, keys: ["id", "name"]) ?? valueString(config, keys: ["id", "name"])
            else {
                diagnostics.droppedRecords += 1
                continue
            }

            items.append(
                NetworkListItem(
                    id: name,
                    name: name,
                    state: valueString(lookup, keys: ["state"]),
                    mode: valueString(config, keys: ["mode"]),
                    ipv4Subnet: valueString(status, keys: ["ipv4subnet"]) ?? valueString(config, keys: ["ipv4subnet"]),
                    ipv6Subnet: valueString(status, keys: ["ipv6subnet"]) ?? valueString(config, keys: ["ipv6subnet"]),
                    ipv4Gateway: valueString(status, keys: ["ipv4gateway"]),
                    plugin: valueString(pluginInfo, keys: ["plugin"]),
                    pluginVariant: valueString(pluginInfo, keys: ["variant"]),
                    creationDate: valueDate(config, keys: ["creationdate"]),
                    labels: labels,
                    isBuiltin: labels["com.apple.container.resource.role"]?.lowercased() == "builtin"
                )
            )
        }

        if items.isEmpty {
            diagnostics.warnings.append("No decodable network rows were found; returning raw output.")
            return .raw(output: output, diagnostics: diagnostics)
        }

        if diagnostics.droppedRecords > 0 {
            diagnostics.warnings.append("Dropped \(diagnostics.droppedRecords) malformed network rows.")
        }
        return .parsed(value: items, diagnostics: diagnostics)
    }

    private func decodeVolumeList(from output: String) -> NonCriticalDecodeResult<[VolumeListItem]> {
        guard let rows = parseJSONArrayRows(from: output) else {
            return .raw(
                output: output,
                diagnostics: DecodeDiagnostics(
                    droppedRecords: 0,
                    warnings: ["Volume list JSON decoding failed; falling back to raw output."]
                )
            )
        }
        if rows.isEmpty {
            return .parsed(value: [], diagnostics: .clean)
        }

        var diagnostics = DecodeDiagnostics.clean
        var items: [VolumeListItem] = []

        for row in rows {
            let lookup = normalizeKeys(row)
            guard let name = valueString(lookup, keys: ["name", "id"]) else {
                diagnostics.droppedRecords += 1
                continue
            }

            items.append(
                VolumeListItem(
                    id: name,
                    name: name,
                    driver: valueString(lookup, keys: ["driver"]),
                    format: valueString(lookup, keys: ["format"]),
                    source: valueString(lookup, keys: ["source"]),
                    sizeInBytes: valueInt64(lookup, keys: ["sizeinbytes"]),
                    createdAt: valueDate(lookup, keys: ["createdat"]),
                    labels: valueStringDictionary(lookup, key: "labels"),
                    options: valueStringDictionary(lookup, key: "options")
                )
            )
        }

        if items.isEmpty {
            diagnostics.warnings.append("No decodable volume rows were found; returning raw output.")
            return .raw(output: output, diagnostics: diagnostics)
        }

        if diagnostics.droppedRecords > 0 {
            diagnostics.warnings.append("Dropped \(diagnostics.droppedRecords) malformed volume rows.")
        }
        return .parsed(value: items, diagnostics: diagnostics)
    }

    private func parseJSONArrayRows(from output: String) -> [[String: Any]]? {
        let data = Data(output.utf8)
        guard let anyValue = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return anyValue as? [[String: Any]]
    }

    private func normalizeKeys(_ dictionary: [String: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
    }

    private func nestedDictionary(_ dictionary: [String: Any]?, key: String) -> [String: Any] {
        guard
            let dictionary,
            let nested = dictionary[key] as? [String: Any]
        else {
            return [:]
        }
        return normalizeKeys(nested)
    }

    private func prettyPrintedJSON(from output: String) -> String? {
        let data = Data(output.utf8)
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    private func commandText(from initProcess: [String: Any]) -> String? {
        let executable = valueString(initProcess, keys: ["executable"])
        let arguments = valueStringArray(initProcess, key: "arguments")
        let parts = ([executable].compactMap { $0 } + arguments)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    nonisolated private static func preferredImageSavePlatform() -> String? {
        #if arch(arm64)
            return "linux/arm64"
        #elseif arch(x86_64)
            return "linux/amd64"
        #else
            return nil
        #endif
    }

    private func valueString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] {
                if let text = value as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                } else if let number = value as? NSNumber {
                    return number.stringValue
                }
            }
        }
        return nil
    }

    private func valueInt64(_ dictionary: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = dictionary[key] {
                if let number = value as? NSNumber {
                    return number.int64Value
                }
                if let text = value as? String, let parsed = Int64(text) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func valueInt(_ dictionary: [String: Any], keys: [String]) -> Int? {
        valueInt64(dictionary, keys: keys).map(Int.init)
    }

    private func valueDate(_ dictionary: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let number = value as? NSNumber {
                return Date(timeIntervalSinceReferenceDate: number.doubleValue)
            }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let date = Self.iso8601FractionalSecondsFormatter.date(from: trimmed)
                    ?? Self.iso8601DateFormatter.date(from: trimmed)
                {
                    return date
                }
                if let interval = Double(trimmed) {
                    return Date(timeIntervalSinceReferenceDate: interval)
                }
            }
        }
        return nil
    }

    private func valueStringDictionary(_ dictionary: [String: Any], key: String) -> [String: String] {
        guard let value = dictionary[key] as? [String: Any] else { return [:] }
        var output: [String: String] = [:]
        for (entryKey, entryValue) in value {
            if let text = entryValue as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    output[entryKey] = trimmed
                }
            } else if let number = entryValue as? NSNumber {
                output[entryKey] = number.stringValue
            }
        }
        return output
    }

    private func valueDictionaryArray(_ dictionary: [String: Any], key: String) -> [[String: Any]] {
        guard let values = dictionary[key] as? [[String: Any]] else { return [] }
        return values
    }

    private func valueStringArray(_ dictionary: [String: Any], key: String) -> [String] {
        guard let values = dictionary[key] as? [Any] else { return [] }
        return values.compactMap { value in
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
    }

    private func stableKeyValueArguments(from dictionary: [String: String]) -> [String] {
        dictionary
            .map {
                (
                    $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                    $0.value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
            .sorted { lhs, rhs in lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending }
            .map { "\($0.0)=\($0.1)" }
    }

    private static let iso8601FractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601DateFormatter = ISO8601DateFormatter()
}

extension ContainerListItem {
    var imageDisplayName: String {
        image ?? "Unknown image"
    }

    var statusDisplay: String {
        let trimmedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedStatus.isEmpty ? state.capitalized : trimmedStatus
    }

    var stateDisplay: String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    var isRunning: Bool {
        let normalized = "\(state) \(status ?? "")".lowercased()
        return normalized.contains("running")
    }

    var matchesSearchText: String {
        [id, name, state, status ?? "", image ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}
