import SwiftUI

@MainActor
struct SettingsView: View {
    let updater: any AppUpdaterProviding
    @AppStorage(.showMenuBarExtraKey) private var showMenuBarExtra = true
    @AppStorage(.showSidebarBadgesKey) private var showSidebarBadges = true
    @State private var selectedTab: SettingsTab = .general
    @State private var loginLaunchController = LoginLaunchController.shared
    @State private var openAtLogin: Bool
    @State private var isUpdatingOpenAtLogin = false
    @State private var loginLaunchErrorMessage: String?

    init(updater: any AppUpdaterProviding) {
        self.updater = updater
        _openAtLogin = State(initialValue: LoginLaunchController.shared.isOpenAtLoginEnabled)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tag(SettingsTab.general)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            aboutTab
                .tag(SettingsTab.about)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 420)
        .navigationTitle("Settings")
        .alert("Open at Login", isPresented: loginLaunchErrorIsPresented) {
            Button("OK", role: .cancel) {
                loginLaunchErrorMessage = nil
            }
        } message: {
            Text(loginLaunchErrorMessage ?? "ContainerUtility could not update the login item setting.")
        }
    }

    private var generalTab: some View {
        Form {
            Section("Navigation") {
                Toggle("Show sidebar badges", isOn: $showSidebarBadges)
            }

            Section("Menu Bar") {
                Toggle("Show menu bar extra", isOn: $showMenuBarExtra)

                Text(menuBarDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Launch") {
                Toggle("Open at Login", isOn: openAtLoginBinding)
                    .disabled(isUpdatingOpenAtLogin)

                Text(openAtLoginDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loginLaunchController.needsApproval {
                    Button("Open Login Items Settings") {
                        loginLaunchController.openLoginItemsSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            syncOpenAtLoginState()
        }
    }

    private var aboutTab: some View {
        AboutSettingsView(updater: updater)
    }

    private var menuBarDescription: String {
        if showMenuBarExtra {
            return "Shows a compact runtime and resource summary in the macOS menu bar. Closing the main window keeps the app running there."
        }

        return "Hides the menu bar extra. Closing the main window quits the app."
    }

    private var openAtLoginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { newValue in
                let previousValue = openAtLogin
                openAtLogin = newValue
                isUpdatingOpenAtLogin = true

                Task { @MainActor in
                    defer { isUpdatingOpenAtLogin = false }

                    do {
                        try loginLaunchController.setOpenAtLoginEnabled(newValue)
                        syncOpenAtLoginState()
                    } catch {
                        openAtLogin = previousValue
                        loginLaunchErrorMessage = error.localizedDescription
                    }
                }
            }
        )
    }

    private var loginLaunchErrorIsPresented: Binding<Bool> {
        Binding(
            get: { loginLaunchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    loginLaunchErrorMessage = nil
                }
            }
        )
    }

    private var openAtLoginDescription: String {
        if loginLaunchController.needsApproval {
            return "macOS requires approval in System Settings before ContainerUtility can launch automatically."
        }

        if openAtLogin {
            if showMenuBarExtra {
                return "Starts in the menu bar when you log in instead of opening the main window."
            }

            return "Launches when you log in, and opens the main window because the menu bar extra is turned off."
        }

        if showMenuBarExtra {
            return "Keeps launch manual. If enabled later, login launches will start in the menu bar."
        }

        return "Keeps launch manual until you open the app yourself."
    }

    private func syncOpenAtLoginState() {
        loginLaunchController.refreshStatus()
        openAtLogin = loginLaunchController.isOpenAtLoginEnabled
    }
}

private enum SettingsTab: Hashable {
    case general
    case about
}

#Preview {
    SettingsView(updater: DisabledAppUpdater())
}
