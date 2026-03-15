import SwiftUI

@MainActor
struct AboutSettingsView: View {
    let updater: any AppUpdaterProviding
    @AppStorage(.autoUpdateEnabledKey) private var autoUpdateEnabled = true
    @State private var hasSyncedUpdaterPreference = false

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("Name", value: appName)
                LabeledContent("Version", value: appVersion)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdateEnabled)

                Button("Check for Updates…", action: checkForUpdates)
                    .disabled(!updater.isAvailable)

                if let availabilityDescription = updater.availabilityDescription {
                    Text(availabilityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links") {
                Link("Repository", destination: repositoryURL)
                Link("Developer Website", destination: developerWebsiteURL)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: syncUpdaterPreferenceIfNeeded)
        .onChange(of: autoUpdateEnabled) { _, newValue in
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ContainerUtility"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/erdaltoprak/ContainerUtility")!
    }

    private var developerWebsiteURL: URL {
        URL(string: "https://erdaltoprak.com")!
    }

    private func syncUpdaterPreferenceIfNeeded() {
        guard !hasSyncedUpdaterPreference else { return }
        updater.automaticallyChecksForUpdates = autoUpdateEnabled
        hasSyncedUpdaterPreference = true
    }

    private func checkForUpdates() {
        updater.checkForUpdates()
    }
}

#Preview {
    AboutSettingsView(updater: DisabledAppUpdater())
}
