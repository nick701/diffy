import XCTest
@testable import DiffyCore

final class ReadOnlyGitCommandTests: XCTestCase {
    func testCommandsUseNoOptionalLocksAndReadOnlyEnvironment() {
        let commands = GitCommandFactory.commands(for: "/tmp/repo")

        XCTAssertFalse(commands.isEmpty)
        for command in commands {
            XCTAssertEqual(command.environment["GIT_OPTIONAL_LOCKS"], "0")
            XCTAssertTrue(command.arguments.contains("--no-optional-locks"))
        }
    }

    func testCommandsDoNotContainMutationVerbs() {
        let banned = Set([
            "add", "commit", "checkout", "restore", "reset", "stash", "clean", "rm", "mv",
            "merge", "rebase", "switch",
            // Destructive worktree subcommands (worktree list is the only allowed one).
            "remove", "prune", "repair", "lock", "unlock",
            // Network operations.
            "fetch", "pull", "push",
        ])
        let commands = GitCommandFactory.commands(for: "/tmp/repo")

        for command in commands {
            XCTAssertTrue(Set(command.arguments).isDisjoint(with: banned), "Unexpected mutating git argument in \(command.arguments)")
        }
    }

    func testWorktreeListCommandShape() {
        let command = GitCommandFactory.command(for: .worktreeListPorcelain, repositoryPath: "/tmp/repo")
        XCTAssertEqual(
            command.arguments,
            ["-C", "/tmp/repo", "--no-optional-locks", "-c", "core.quotePath=false", "worktree", "list", "--porcelain"]
        )
        XCTAssertEqual(command.environment["GIT_OPTIONAL_LOCKS"], "0")
    }
}
