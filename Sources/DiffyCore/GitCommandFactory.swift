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
    case worktreeListPorcelain
    case isInsideWorkTree
    case upstreamName
    case hasHead
}

public enum GitCommandFactory {
    public static func commands(for repositoryPath: String) -> [GitCommand] {
        GitReadCommandKind.allCases.map { command(for: $0, repositoryPath: repositoryPath) } + [
            recentCommits(repositoryPath: repositoryPath, limit: RepositoryConfig.defaultRecentCommitLimit),
            commitsNotOnUpstream(
                repositoryPath: repositoryPath,
                upstream: "origin/main",
                limit: RepositoryConfig.defaultRecentCommitLimit
            ),
            commitNameStatus(repositoryPath: repositoryPath, sha: String(repeating: "0", count: 40)),
            commitNumstat(repositoryPath: repositoryPath, sha: String(repeating: "0", count: 40)),
        ]
    }

    public static func command(for kind: GitReadCommandKind, repositoryPath: String) -> GitCommand {
        let suffix: [String]

        switch kind {
        case .stagedNumstat:
            suffix = ["diff", "--cached", "--numstat", "-z"]
        case .unstagedNumstat:
            suffix = ["diff", "--numstat", "-z"]
        case .porcelainStatus:
            suffix = ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        case .worktreeListPorcelain:
            suffix = ["worktree", "list", "--porcelain"]
        case .isInsideWorkTree:
            suffix = ["rev-parse", "--is-inside-work-tree"]
        case .upstreamName:
            suffix = ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]
        case .hasHead:
            suffix = ["rev-parse", "--verify", "-q", "HEAD"]
        }

        return readCommand(repositoryPath: repositoryPath, suffix: suffix)
    }

    public static func recentCommits(repositoryPath: String, limit: Int) -> GitCommand {
        readCommand(
            repositoryPath: repositoryPath,
            suffix: [
                "log",
                "-n", String(RepositoryConfig.clampedRecentCommitLimit(limit)),
                "-z",
                "--format=%H%x00%h%x00%s%x00%ct",
                "HEAD",
                "--",
            ]
        )
    }

    public static func commitsNotOnUpstream(
        repositoryPath: String,
        upstream: String,
        limit: Int
    ) -> GitCommand {
        readCommand(
            repositoryPath: repositoryPath,
            suffix: [
                "rev-list",
                "--max-count=\(RepositoryConfig.clampedRecentCommitLimit(limit))",
                "HEAD",
                "--not", upstream,
                "--",
            ]
        )
    }

    public static func commitNameStatus(repositoryPath: String, sha: String) -> GitCommand {
        commitDetailsCommand(repositoryPath: repositoryPath, sha: sha, format: "--name-status")
    }

    public static func commitNumstat(repositoryPath: String, sha: String) -> GitCommand {
        commitDetailsCommand(repositoryPath: repositoryPath, sha: sha, format: "--numstat")
    }

    private static func commitDetailsCommand(repositoryPath: String, sha: String, format: String) -> GitCommand {
        readCommand(
            repositoryPath: repositoryPath,
            suffix: [
                "show", "--first-parent", "--root", "--find-renames", "--find-copies-harder",
                "--format=", format, "-z", sha, "--",
            ]
        )
    }

    private static func readCommand(repositoryPath: String, suffix: [String]) -> GitCommand {
        let base = ["-C", repositoryPath, "--no-optional-locks", "-c", "core.quotePath=false"]
        return GitCommand(arguments: base + suffix, environment: ["GIT_OPTIONAL_LOCKS": "0"])
    }
}
