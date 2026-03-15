import Foundation

enum DiagnosticsLogWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveMinutes:
            "Last 5 Minutes"
        case .thirtyMinutes:
            "Last 30 Minutes"
        case .oneHour:
            "Last Hour"
        case .sixHours:
            "Last 6 Hours"
        case .oneDay:
            "Last Day"
        }
    }
}

struct DiagnosticsBundleOptions: Codable, Sendable {
    var includeSystemVersion = true
    var includeSystemStatus = true
    var includeDiskUsage = true
    var includeSystemLogs = true
    var includeRecentOperations = true
    var includeContainerInspects = true
    var includeImageInspects = false
    var includeNetworkInspects = false
    var includeVolumeInspects = false
    var logWindow: DiagnosticsLogWindow = .thirtyMinutes
}

struct DiagnosticsOperationSnapshot: Codable, Sendable {
    var activities: [ActivityRecord]
}

struct DiagnosticsNamedDocument: Codable, Sendable {
    let filename: String
    let text: String
}

struct DiagnosticsHealthSummary: Codable, Sendable {
    struct Preflight: Codable, Sendable {
        let title: String
        let detail: String
        let severity: String
    }

    let engineState: String
    let engineStatusDetail: String
    let compatibilityState: String
    let compatibilityReason: String?
    let cliVersionDisplay: String?
    let executablePath: String?
    let installSource: String?
    let preflightChecks: [Preflight]
}

struct DiagnosticsSupportBundleManifest: Codable, Sendable {
    let generatedAt: Date
    let options: DiagnosticsBundleOptions
    let warningCount: Int
    let warnings: [String]
    let exportedFiles: [String]
    let healthSummary: DiagnosticsHealthSummary
}

struct DiagnosticsCollectionResult: Sendable {
    let generatedAt: Date
    let options: DiagnosticsBundleOptions
    let healthSnapshot: SystemHealthSnapshot
    let operationSnapshot: DiagnosticsOperationSnapshot
    let systemVersionOutput: String?
    let systemStatusOutput: String?
    let systemDiskUsageOutput: String?
    let systemLogsOutput: String?
    let containerInspects: [DiagnosticsNamedDocument]
    let imageInspects: [DiagnosticsNamedDocument]
    let networkInspects: [DiagnosticsNamedDocument]
    let volumeInspects: [DiagnosticsNamedDocument]
    let warnings: [String]
}

struct DiagnosticsBundleExportResult: Sendable {
    let archiveURL: URL
    let summary: String
    let warningCount: Int
}
