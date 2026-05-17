import AppKit
import DiffyCore
import Foundation

enum EditorLauncher {
    static func open(file: ChangedFileSummary, in repository: RepositoryConfig) {
        guard file.isOpenableFromWorkingTree else { return }

        let fileURL = URL(fileURLWithPath: repository.path).appendingPathComponent(file.path)

        switch repository.editor {
        case .systemDefault:
            NSWorkspace.shared.open(fileURL)
        case .appBundleIdentifier(let bundleIdentifier):
            runOpen(arguments: ["-b", bundleIdentifier, fileURL.path])
        case .command(let command):
            runShell(command: command, fileURL: fileURL, repositoryURL: URL(fileURLWithPath: repository.path))
        }
    }

    private static func runOpen(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }

    private static func runShell(command: String, fileURL: URL, repositoryURL: URL) {
        let escapedFile = shellEscape(fileURL.path)
        let escapedRepo = shellEscape(repositoryURL.path)
        let expanded = command
            .replacingOccurrences(of: "{path}", with: escapedFile)
            .replacingOccurrences(of: "{repo}", with: escapedRepo)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", expanded]
        try? process.run()
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
