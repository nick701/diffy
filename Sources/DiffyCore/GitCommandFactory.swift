import Foundation

public struct GitCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: String = "/usr/bin/git", arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public enum GitReadCommandKind: CaseIterable, Sendable {
    case stagedNumstat
    case unstagedNumstat
    case porcelainStatus
}

public enum GitCommandFactory {
    public static func commands(for repositoryPath: String) -> [GitCommand] {
        GitReadCommandKind.allCases.map { command(for: $0, repositoryPath: repositoryPath) }
    }

    public static func command(for kind: GitReadCommandKind, repositoryPath: String) -> GitCommand {
        let base = ["-C", repositoryPath, "--no-optional-locks"]
        let suffix: [String]

        switch kind {
        case .stagedNumstat:
            suffix = ["diff", "--cached", "--numstat"]
        case .unstagedNumstat:
            suffix = ["diff", "--numstat"]
        case .porcelainStatus:
            suffix = ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        }

        return GitCommand(arguments: base + suffix, environment: ["GIT_OPTIONAL_LOCKS": "0"])
    }
}
