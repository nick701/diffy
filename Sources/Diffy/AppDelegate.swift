import AppKit
import DiffyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DiffyStore()

    private var statusItemManager: StatusItemManager?
    private var updaterController: UpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store.load()
        statusItemManager = StatusItemManager(store: store)
        updaterController = UpdaterController()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
