import Foundation

/// The single git write operation Diffy ever performs: `git worktree remove <path>`.
///
/// Lives on a separate surface from `GitClient` / `GitCommandFactory` so that the
/// read-only contract test sweeping `GitCommandFactory.commands(for:)` stays meaningful.
public struct GitWorktreeMutator: Sendable {
    private let runner: GitProcessRunning

    public init(runner: GitProcessRunning = GitProcessRunner()) {
        self.runner = runner
    }

    /// Run `git -C <parentPath> worktree remove <worktreePath>`. No `--force`.
    /// Throws `GitClientError.commandFailed(stderr)` on non-zero exit.
    public func remove(parentPath: String, worktreePath: String) throws {
        let command = GitCommand(
            arguments: ["-C", parentPath, "worktree", "remove", worktreePath],
            environment: ["GIT_OPTIONAL_LOCKS": "0"]
        )
        _ = try runner.run(command)
    }
}
