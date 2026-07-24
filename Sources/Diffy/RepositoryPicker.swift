import AppKit

@MainActor
enum RepositoryPicker {
    static func addRepository(to store: DiffyStore) {
        chooseRepository { url in
            store.addRepository(path: url.path, destination: .newGroup)
        }
    }

    static func chooseRepository(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Git Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
