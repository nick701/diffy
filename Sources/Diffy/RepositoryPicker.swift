import AppKit

@MainActor
enum RepositoryPicker {
    static func addRepository(to store: DiffyStore) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            store.addRepository(path: url.path)
        }
    }
}
