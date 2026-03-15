import SwiftUI

@main
struct ContainerUtilityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(.showMenuBarExtraKey) private var showMenuBarExtra = true
    @State private var appModel: AppModel
    @State private var appRefreshController: AppRefreshController
    private let commandRunner: CommandRunner
    private let containerCLIAdapter: ContainerCLIAdapter

    init() {
        let commandRunner = AppDependencies.commandRunner
        let containerCLIAdapter = AppDependencies.containerCLIAdapter
        let appModel = AppModel()
        let appRefreshController = AppRefreshController(
            appModel: appModel,
            containerCLIAdapter: containerCLIAdapter
        )

        self.commandRunner = commandRunner
        self.containerCLIAdapter = containerCLIAdapter
        _appModel = State(initialValue: appModel)
        _appRefreshController = State(initialValue: appRefreshController)

        Task { @MainActor in
            appRefreshController.startIfNeeded()
        }
    }

    var body: some Scene {
        Window("ContainerUtility", id: AppSceneID.mainWindow) {
            AppRootView()
                .environment(appModel)
                .environment(\.commandRunner, commandRunner)
                .environment(\.containerCLIAdapter, containerCLIAdapter)
        }
        .defaultSize(width: 1400, height: 800)
        .defaultLaunchBehavior(shouldPresentMainWindowOnLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)

        MenuBarExtra(menuBarTitle, systemImage: menuBarSymbol, isInserted: $showMenuBarExtra) {
            MenuBarDashboardView(refreshController: appRefreshController)
                .environment(appModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: appDelegate.appUpdater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.appUpdater.checkForUpdates()
                }
                .disabled(!appDelegate.appUpdater.isAvailable)
            }
        }
    }

    private var runningContainerCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var menuBarSymbol: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "shippingbox"
        }

        switch snapshot.compatibilityReport.state {
        case .unsupported, .unavailable:
            return "exclamationmark.triangle.fill"
        case .supported:
            return "shippingbox"
        }
    }

    private var menuBarTitle: String {
        runningContainerCount > 0 ? "\(runningContainerCount)" : ""
    }

    private var shouldPresentMainWindowOnLaunch: Bool {
        !hasCompletedOnboarding || !showMenuBarExtra
    }
}
