import Foundation

enum DiagnosticsSupportBundleBuilder {
    nonisolated static func collect(
        options: DiagnosticsBundleOptions,
        adapter: ContainerCLIAdapter,
        operationSnapshot: DiagnosticsOperationSnapshot,
        progress: (@Sendable (String) async -> Void)? = nil
    ) async -> DiagnosticsCollectionResult {
        let generatedAt = Date()
        var warnings: [String] = []

        func emit(_ message: String) async {
            if let progress {
                await progress(message)
            }
        }

        await emit("Collecting system health snapshot.")
        let healthSnapshot = await adapter.collectSystemHealthSnapshot()

        let systemVersionOutput = await fetchOptionalText(
            label: "system version",
            warnings: &warnings,
            isEnabled: options.includeSystemVersion
        ) {
            try await adapter.fetchSystemVersionOutput()
        }
        let systemStatusOutput = await fetchOptionalText(
            label: "system status",
            warnings: &warnings,
            isEnabled: options.includeSystemStatus
        ) {
            try await adapter.fetchSystemStatusOutput()
        }
        let systemDiskUsageOutput = await fetchOptionalText(
            label: "system disk usage",
            warnings: &warnings,
            isEnabled: options.includeDiskUsage
        ) {
            try await adapter.fetchSystemDiskUsageOutput()
        }
        let systemLogsOutput = await fetchOptionalText(
            label: "system logs (\(options.logWindow.rawValue))",
            warnings: &warnings,
            isEnabled: options.includeSystemLogs
        ) {
            try await adapter.fetchSystemLogs(last: options.logWindow.rawValue)
        }

        if options.includeSystemVersion, systemVersionOutput != nil {
            await emit("Collected system version output.")
        }
        if options.includeSystemStatus, systemStatusOutput != nil {
            await emit("Collected system status output.")
        }
        if options.includeDiskUsage, systemDiskUsageOutput != nil {
            await emit("Collected system disk usage output.")
        }
        if options.includeSystemLogs, systemLogsOutput != nil {
            await emit("Collected system logs.")
        }

        let containerInspects = await collectContainerInspects(
            enabled: options.includeContainerInspects,
            adapter: adapter,
            warnings: &warnings,
            progress: progress
        )
        let imageInspects = await collectImageInspects(
            enabled: options.includeImageInspects,
            adapter: adapter,
            warnings: &warnings,
            progress: progress
        )
        let networkInspects = await collectNetworkInspects(
            enabled: options.includeNetworkInspects,
            adapter: adapter,
            warnings: &warnings,
            progress: progress
        )
        let volumeInspects = await collectVolumeInspects(
            enabled: options.includeVolumeInspects,
            adapter: adapter,
            warnings: &warnings,
            progress: progress
        )

        return DiagnosticsCollectionResult(
            generatedAt: generatedAt,
            options: options,
            healthSnapshot: healthSnapshot,
            operationSnapshot: operationSnapshot,
            systemVersionOutput: options.includeSystemVersion ? systemVersionOutput : nil,
            systemStatusOutput: systemStatusOutput,
            systemDiskUsageOutput: systemDiskUsageOutput,
            systemLogsOutput: systemLogsOutput,
            containerInspects: containerInspects,
            imageInspects: imageInspects,
            networkInspects: networkInspects,
            volumeInspects: volumeInspects,
            warnings: warnings
        )
    }

    nonisolated static func exportBundle(
        collection: DiagnosticsCollectionResult,
        to destinationURL: URL
    ) throws -> DiagnosticsBundleExportResult {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "ContainerUtilitySupport-\(UUID().uuidString)",
            isDirectory: true
        )
        let bundleName = destinationURL.deletingPathExtension().lastPathComponent
        let bundleDirectory = tempRoot.appendingPathComponent(bundleName, isDirectory: true)
        let summary = makeRedactedSummary(from: collection)

        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempRoot) }

        var exportedFiles: [String] = []

        try writeString(
            summary,
            relativePath: "redacted-summary.txt",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )
        let healthSummary = buildHealthSummary(from: collection.healthSnapshot)
        try writeJSONObject(
            healthSummaryJSONObject(healthSummary),
            relativePath: "health-summary.json",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )

        if let systemVersionOutput = collection.systemVersionOutput {
            try writeString(
                systemVersionOutput,
                relativePath: "system/version.json",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }
        if let systemStatusOutput = collection.systemStatusOutput {
            try writeString(
                systemStatusOutput,
                relativePath: "system/status.json",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }
        if let systemDiskUsageOutput = collection.systemDiskUsageOutput {
            try writeString(
                systemDiskUsageOutput,
                relativePath: "system/disk-usage.json",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }
        if let systemLogsOutput = collection.systemLogsOutput {
            try writeString(
                systemLogsOutput,
                relativePath: "system/logs.txt",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }

        if collection.options.includeRecentOperations {
            try writeJSON(
                collection.operationSnapshot.activities,
                relativePath: "operations/recent-activities.json",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }

        try writeDocuments(
            collection.containerInspects,
            directory: "inspects/containers",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )
        try writeDocuments(
            collection.imageInspects,
            directory: "inspects/images",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )
        try writeDocuments(
            collection.networkInspects,
            directory: "inspects/networks",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )
        try writeDocuments(
            collection.volumeInspects,
            directory: "inspects/volumes",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )

        if !collection.warnings.isEmpty {
            try writeString(
                collection.warnings.joined(separator: "\n"),
                relativePath: "warnings.txt",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }

        let manifest = DiagnosticsSupportBundleManifest(
            generatedAt: collection.generatedAt,
            options: collection.options,
            warningCount: collection.warnings.count,
            warnings: collection.warnings,
            exportedFiles: exportedFiles.sorted(),
            healthSummary: healthSummary
        )
        try writeJSONObject(
            manifestJSONObject(manifest),
            relativePath: "manifest.json",
            in: bundleDirectory,
            exportedFiles: &exportedFiles
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try zipBundleDirectory(bundleDirectory, to: destinationURL, from: tempRoot)

        return DiagnosticsBundleExportResult(
            archiveURL: destinationURL,
            summary: summary,
            warningCount: collection.warnings.count
        )
    }

    nonisolated static func makeRedactedSummary(from collection: DiagnosticsCollectionResult) -> String {
        var lines: [String] = []
        let healthSummary = buildHealthSummary(from: collection.healthSnapshot)
        let failedActivities = collection.operationSnapshot.activities.filter {
            $0.status == .failed || $0.status == .canceled
        }

        lines.append("ContainerUtility Troubleshooting Summary")
        lines.append("Generated: \(collection.generatedAt.formatted(date: .abbreviated, time: .standard))")
        lines.append("Engine state: \(redact(healthSummary.engineState))")
        lines.append("Engine detail: \(redact(healthSummary.engineStatusDetail))")
        lines.append("Compatibility: \(redact(healthSummary.compatibilityState))")
        if let compatibilityReason = healthSummary.compatibilityReason, !compatibilityReason.isEmpty {
            lines.append("Compatibility detail: \(redact(compatibilityReason))")
        }
        if let version = healthSummary.cliVersionDisplay {
            lines.append("CLI version: \(redact(version))")
        }
        if let executablePath = healthSummary.executablePath {
            lines.append("Executable path: \(redact(executablePath))")
        }
        if let installSource = healthSummary.installSource {
            lines.append("Install source: \(redact(installSource))")
        }

        lines.append("Recent operations captured: \(collection.operationSnapshot.activities.count)")
        lines.append("Failed/canceled operations: \(failedActivities.count)")

        if let systemLogsOutput = collection.systemLogsOutput {
            let logLineCount = systemLogsOutput.split(whereSeparator: \.isNewline).count
            lines.append("System log lines captured: \(logLineCount)")
        }

        if !failedActivities.isEmpty {
            lines.append("Recent failed operations:")
            for activity in failedActivities.prefix(5) {
                let detail = activity.errorMessage ?? activity.summary ?? "No error detail recorded."
                lines.append("- \(redact(activity.title)): \(redact(detail))")
            }
        }

        if !collection.warnings.isEmpty {
            lines.append("Collection warnings: \(collection.warnings.count)")
            for warning in collection.warnings.prefix(5) {
                lines.append("- \(redact(warning))")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension DiagnosticsSupportBundleBuilder {
    fileprivate nonisolated static func fetchOptionalText(
        label: String,
        warnings: inout [String],
        isEnabled: Bool = true,
        fetcher: () async throws -> String
    ) async -> String? {
        guard isEnabled else { return nil }
        do {
            return try await fetcher()
        } catch {
            warnings.append("Failed to collect \(label): \(error.localizedDescription)")
            return nil
        }
    }

    fileprivate nonisolated static func collectContainerInspects(
        enabled: Bool,
        adapter: ContainerCLIAdapter,
        warnings: inout [String],
        progress: (@Sendable (String) async -> Void)?
    ) async -> [DiagnosticsNamedDocument] {
        guard enabled else { return [] }
        if let progress {
            await progress("Collecting container inspect outputs.")
        }

        guard let result = try? await adapter.listContainers() else {
            warnings.append("Failed to list containers for diagnostics inspect export.")
            return []
        }

        let items: [ContainerListItem]
        switch result {
        case .parsed(let value, let diagnostics):
            items = value
            warnings.append(contentsOf: diagnostics.warnings)
        case .raw(_, let diagnostics):
            warnings.append(contentsOf: diagnostics.warnings)
            warnings.append("Skipped container inspect export because container list output could not be parsed.")
            return []
        }

        var documents: [DiagnosticsNamedDocument] = []
        for item in items {
            do {
                let snapshot = try await adapter.inspectContainer(id: item.id)
                documents.append(
                    DiagnosticsNamedDocument(
                        filename: "\(safeFilename(item.name))-\(shortIdentifier(item.id)).json",
                        text: snapshot.rawJSON
                    )
                )
            } catch {
                warnings.append("Could not inspect container \(item.name): \(error.localizedDescription)")
            }
        }
        return documents
    }

    fileprivate nonisolated static func collectImageInspects(
        enabled: Bool,
        adapter: ContainerCLIAdapter,
        warnings: inout [String],
        progress: (@Sendable (String) async -> Void)?
    ) async -> [DiagnosticsNamedDocument] {
        guard enabled else { return [] }
        if let progress {
            await progress("Collecting image inspect outputs.")
        }

        guard let result = try? await adapter.listImages() else {
            warnings.append("Failed to list images for diagnostics inspect export.")
            return []
        }

        let items: [ImageListItem]
        switch result {
        case .parsed(let value, let diagnostics):
            items = value
            warnings.append(contentsOf: diagnostics.warnings)
        case .raw(_, let diagnostics):
            warnings.append(contentsOf: diagnostics.warnings)
            warnings.append("Skipped image inspect export because image list output could not be parsed.")
            return []
        }

        var documents: [DiagnosticsNamedDocument] = []
        for item in items {
            do {
                let snapshot = try await adapter.inspectImage(reference: item.reference)
                documents.append(
                    DiagnosticsNamedDocument(
                        filename: "\(safeFilename(item.reference)).json",
                        text: snapshot.rawJSON
                    )
                )
            } catch {
                warnings.append("Could not inspect image \(item.reference): \(error.localizedDescription)")
            }
        }
        return documents
    }

    fileprivate nonisolated static func collectNetworkInspects(
        enabled: Bool,
        adapter: ContainerCLIAdapter,
        warnings: inout [String],
        progress: (@Sendable (String) async -> Void)?
    ) async -> [DiagnosticsNamedDocument] {
        guard enabled else { return [] }
        if let progress {
            await progress("Collecting network inspect outputs.")
        }

        guard let result = try? await adapter.listNetworks() else {
            warnings.append("Failed to list networks for diagnostics inspect export.")
            return []
        }

        let items: [NetworkListItem]
        switch result {
        case .parsed(let value, let diagnostics):
            items = value
            warnings.append(contentsOf: diagnostics.warnings)
        case .raw(_, let diagnostics):
            warnings.append(contentsOf: diagnostics.warnings)
            warnings.append("Skipped network inspect export because network list output could not be parsed.")
            return []
        }

        var documents: [DiagnosticsNamedDocument] = []
        for item in items {
            do {
                let snapshot = try await adapter.inspectNetwork(name: item.name)
                documents.append(
                    DiagnosticsNamedDocument(
                        filename: "\(safeFilename(item.name)).json",
                        text: snapshot.rawJSON
                    )
                )
            } catch {
                warnings.append("Could not inspect network \(item.name): \(error.localizedDescription)")
            }
        }
        return documents
    }

    fileprivate nonisolated static func collectVolumeInspects(
        enabled: Bool,
        adapter: ContainerCLIAdapter,
        warnings: inout [String],
        progress: (@Sendable (String) async -> Void)?
    ) async -> [DiagnosticsNamedDocument] {
        guard enabled else { return [] }
        if let progress {
            await progress("Collecting volume inspect outputs.")
        }

        guard let result = try? await adapter.listVolumes() else {
            warnings.append("Failed to list volumes for diagnostics inspect export.")
            return []
        }

        let items: [VolumeListItem]
        switch result {
        case .parsed(let value, let diagnostics):
            items = value
            warnings.append(contentsOf: diagnostics.warnings)
        case .raw(_, let diagnostics):
            warnings.append(contentsOf: diagnostics.warnings)
            warnings.append("Skipped volume inspect export because volume list output could not be parsed.")
            return []
        }

        var documents: [DiagnosticsNamedDocument] = []
        for item in items {
            do {
                let snapshot = try await adapter.inspectVolume(name: item.name)
                documents.append(
                    DiagnosticsNamedDocument(
                        filename: "\(safeFilename(item.name)).json",
                        text: snapshot.rawJSON
                    )
                )
            } catch {
                warnings.append("Could not inspect volume \(item.name): \(error.localizedDescription)")
            }
        }
        return documents
    }

    fileprivate nonisolated static func buildHealthSummary(from snapshot: SystemHealthSnapshot)
        -> DiagnosticsHealthSummary
    {
        let compatibilityState: String
        let compatibilityReason: String?

        switch snapshot.compatibilityReport.state {
        case .supported:
            compatibilityState = "supported"
            compatibilityReason = nil
        case .unsupported(let reason):
            compatibilityState = "unsupported"
            compatibilityReason = reason
        case .unavailable(let reason):
            compatibilityState = "unavailable"
            compatibilityReason = reason
        }

        return DiagnosticsHealthSummary(
            engineState: String(describing: snapshot.engineState),
            engineStatusDetail: snapshot.engineStatusDetail,
            compatibilityState: compatibilityState,
            compatibilityReason: compatibilityReason,
            cliVersionDisplay: snapshot.cliVersionDisplay,
            executablePath: snapshot.executablePath,
            installSource: installSourceDescription(snapshot.installSource),
            preflightChecks: snapshot.preflightChecks.map {
                DiagnosticsHealthSummary.Preflight(
                    title: $0.title,
                    detail: $0.detail,
                    severity: String(describing: $0.severity)
                )
            }
        )
    }

    fileprivate nonisolated static func writeDocuments(
        _ documents: [DiagnosticsNamedDocument],
        directory: String,
        in bundleDirectory: URL,
        exportedFiles: inout [String]
    ) throws {
        for document in documents {
            try writeString(
                document.text,
                relativePath: "\(directory)/\(document.filename)",
                in: bundleDirectory,
                exportedFiles: &exportedFiles
            )
        }
    }

    fileprivate nonisolated static func writeString(
        _ text: String,
        relativePath: String,
        in bundleDirectory: URL,
        exportedFiles: inout [String]
    ) throws {
        let fileURL = bundleDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        exportedFiles.append(relativePath)
    }

    fileprivate nonisolated static func writeJSON<T: Encodable>(
        _ value: T,
        relativePath: String,
        in bundleDirectory: URL,
        exportedFiles: inout [String]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let fileURL = bundleDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL)
        exportedFiles.append(relativePath)
    }

    fileprivate nonisolated static func writeJSONObject(
        _ object: [String: Any],
        relativePath: String,
        in bundleDirectory: URL,
        exportedFiles: inout [String]
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let fileURL = bundleDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL)
        exportedFiles.append(relativePath)
    }

    fileprivate nonisolated static func zipBundleDirectory(
        _ bundleDirectory: URL,
        to destinationURL: URL,
        from tempRoot: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = tempRoot
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            bundleDirectory.lastPathComponent,
            destinationURL.path,
        ]

        try process.run()
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility)
            .async {
                process.waitUntilExit()
                completion.signal()
            }
        let waitResult = completion.wait(timeout: .now() + 30)
        if waitResult == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 3)
            throw AppError.commandTimedOut(command: "/usr/bin/ditto", timeout: 30)
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let rawStderr = String(bytes: stderrData, encoding: .utf8) ?? ""
            let stderr = rawStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError.commandLaunchFailed(
                command: "/usr/bin/ditto",
                reason: stderr.isEmpty ? "Failed to create support bundle archive." : stderr
            )
        }
    }

    fileprivate nonisolated static func safeFilename(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    fileprivate nonisolated static func shortIdentifier(_ value: String) -> String {
        String(value.prefix(12))
    }

    fileprivate nonisolated static func installSourceDescription(_ source: ContainerInstallSource?) -> String? {
        guard let source else { return nil }
        switch source {
        case .officialPackage:
            return "Official signed package"
        case .homebrew:
            return "Homebrew"
        case .unknown:
            return "Unknown"
        }
    }

    fileprivate nonisolated static func healthSummaryJSONObject(_ summary: DiagnosticsHealthSummary) -> [String: Any] {
        [
            "engineState": summary.engineState,
            "engineStatusDetail": summary.engineStatusDetail,
            "compatibilityState": summary.compatibilityState,
            "compatibilityReason": summary.compatibilityReason as Any,
            "cliVersionDisplay": summary.cliVersionDisplay as Any,
            "executablePath": summary.executablePath as Any,
            "installSource": summary.installSource as Any,
            "preflightChecks": summary.preflightChecks.map {
                [
                    "title": $0.title,
                    "detail": $0.detail,
                    "severity": $0.severity,
                ]
            },
        ]
    }

    fileprivate nonisolated static func manifestJSONObject(_ manifest: DiagnosticsSupportBundleManifest) -> [String:
        Any]
    {
        [
            "generatedAt": ISO8601DateFormatter().string(from: manifest.generatedAt),
            "options": [
                "includeSystemVersion": manifest.options.includeSystemVersion,
                "includeSystemStatus": manifest.options.includeSystemStatus,
                "includeDiskUsage": manifest.options.includeDiskUsage,
                "includeSystemLogs": manifest.options.includeSystemLogs,
                "includeRecentOperations": manifest.options.includeRecentOperations,
                "includeContainerInspects": manifest.options.includeContainerInspects,
                "includeImageInspects": manifest.options.includeImageInspects,
                "includeNetworkInspects": manifest.options.includeNetworkInspects,
                "includeVolumeInspects": manifest.options.includeVolumeInspects,
                "logWindow": manifest.options.logWindow.rawValue,
            ],
            "warningCount": manifest.warningCount,
            "warnings": manifest.warnings,
            "exportedFiles": manifest.exportedFiles,
            "healthSummary": healthSummaryJSONObject(manifest.healthSummary),
        ]
    }

    fileprivate nonisolated static func redact(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        result = result.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "/Users/<redacted>",
            options: .regularExpression
        )

        let pattern = #"\b[a-f0-9]{12,64}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return result
        }
        let nsRange = NSRange(result.startIndex ..< result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let token = String(result[range])
            result.replaceSubrange(range, with: "\(token.prefix(12))...")
        }
        return result
    }
}
