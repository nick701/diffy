import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DiffyStore()

    private var statusItemManager: StatusItemManager?
    private var mainWindowController: MainWindowController?
    private var updaterController: UpdaterController?
    private var launchAtLoginController: LaunchAtLoginController?

    private static let hasLaunchedBeforeKey = "DiffyHasLaunchedBefore"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        launchAtLoginController = LaunchAtLoginController()
        updaterController = UpdaterController()
        mainWindowController = MainWindowController(
            store: store,
            launchAtLoginController: launchAtLoginController!,
            updaterController: updaterController!
        )

        statusItemManager = StatusItemManager(store: store) { [weak self] in
            self?.mainWindowController?.show()
        }

        store.start()

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.hasLaunchedBeforeKey) == false {
            defaults.set(true, forKey: Self.hasLaunchedBeforeKey)
            mainWindowController?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
