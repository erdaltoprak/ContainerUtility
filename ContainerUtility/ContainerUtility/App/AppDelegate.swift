import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appUpdater: any AppUpdaterProviding = makeAppUpdater()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isMenuBarExtraEnabled
    }

    private var isMenuBarExtraEnabled: Bool {
        guard let value = UserDefaults.standard.object(forKey: .showMenuBarExtraKey) as? Bool else {
            return true
        }

        return value
    }
}
