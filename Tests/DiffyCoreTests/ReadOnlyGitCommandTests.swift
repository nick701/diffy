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
            XCTAssertFalse(command.arguments.contains("-p"))
            XCTAssertFalse(command.arguments.contains("--patch"))
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

    func testRecentCommitCommandShapesAndLimits() {
        let recent = GitCommandFactory.recentCommits(repositoryPath: "/tmp/repo", limit: 99)
        XCTAssertEqual(
            recent.arguments,
            [
                "-C", "/tmp/repo", "--no-optional-locks", "-c", "core.quotePath=false",
                "log", "-n", "20", "-z", "--format=%H%x00%h%x00%s%x00%ct", "HEAD", "--",
            ]
        )

        let local = GitCommandFactory.commitsNotOnUpstream(
            repositoryPath: "/tmp/repo",
            upstream: "origin/main",
            limit: 0
        )
        XCTAssertEqual(
            local.arguments,
            [
                "-C", "/tmp/repo", "--no-optional-locks", "-c", "core.quotePath=false",
                "rev-list", "--max-count=1", "HEAD", "--not", "origin/main", "--",
            ]
        )
    }

    func testCommitDetailCommandShapes() {
        let sha = String(repeating: "a", count: 40)
        let commands = [
            (GitCommandFactory.commitNameStatus(repositoryPath: "/tmp/repo", sha: sha), "--name-status"),
            (GitCommandFactory.commitNumstat(repositoryPath: "/tmp/repo", sha: sha), "--numstat"),
        ]

        for (command, format) in commands {
            XCTAssertEqual(Array(command.arguments.suffix(10)), [
                "show", "--first-parent", "--root", "--find-renames", "--find-copies-harder",
                "--format=", format, "-z", sha, "--",
            ])
        }
    }
}
