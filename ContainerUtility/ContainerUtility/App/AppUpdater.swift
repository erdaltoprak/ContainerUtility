import AppKit
import Foundation
import Security

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
protocol AppUpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var availabilityDescription: String? { get }
    var isAvailable: Bool { get }

    func checkForUpdates()
}

@MainActor
final class DisabledAppUpdater: AppUpdaterProviding {
    var automaticallyChecksForUpdates = false
    let availabilityDescription: String?
    let isAvailable = false

    init(reason: String? = "Updates are unavailable in this build.") {
        availabilityDescription = reason
    }

    func checkForUpdates() {}
}

#if canImport(Sparkle)
extension SPUStandardUpdaterController: AppUpdaterProviding {
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var availabilityDescription: String? { nil }
    var isAvailable: Bool { true }

    func checkForUpdates() {
        checkForUpdates(nil)
    }
}

private struct SparkleConfiguration {
    let feedURL: URL
    let publicKey: String
}

@MainActor
func makeAppUpdater() -> any AppUpdaterProviding {
    guard Bundle.main.bundleURL.pathExtension == "app" else {
        return DisabledAppUpdater(reason: "Update checks are available only from an app bundle.")
    }

    guard let configuration = sparkleConfiguration() else {
        return DisabledAppUpdater(
            reason: "Set SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY before shipping a Sparkle-enabled release."
        )
    }

    guard configuration.feedURL.scheme == "https" else {
        return DisabledAppUpdater(reason: "Sparkle feed URLs should use HTTPS.")
    }

    guard isDeveloperIDSigned(bundleURL: Bundle.main.bundleURL) else {
        return DisabledAppUpdater(reason: "Update checks are available only in Developer ID-signed builds.")
    }

    let savedAutomaticChecks = (UserDefaults.standard.object(forKey: .autoUpdateEnabledKey) as? Bool) ?? true
    let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    controller.updater.automaticallyChecksForUpdates = savedAutomaticChecks
    controller.startUpdater()
    return controller
}

private func sparkleConfiguration() -> SparkleConfiguration? {
    let feedURLString = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let feedURLString, !feedURLString.isEmpty,
          let feedURL = URL(string: feedURLString),
          let publicKey, !publicKey.isEmpty else {
        return nil
    }

    return SparkleConfiguration(feedURL: feedURL, publicKey: publicKey)
}
#else
@MainActor
func makeAppUpdater() -> any AppUpdaterProviding {
    DisabledAppUpdater(reason: "Sparkle is not linked in this build.")
}
#endif

private func isDeveloperIDSigned(bundleURL: URL) -> Bool {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
          let code = staticCode
    else {
        return false
    }

    var infoCF: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
          let info = infoCF as? [String: Any],
          let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leafCertificate = certificates.first,
          let summary = SecCertificateCopySubjectSummary(leafCertificate) as String? else {
        return false
    }

    return summary.hasPrefix("Developer ID Application:")
}
