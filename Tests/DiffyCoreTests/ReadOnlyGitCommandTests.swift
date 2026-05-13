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
        let banned = Set(["add", "commit", "checkout", "restore", "reset", "stash", "clean", "rm", "mv", "merge", "rebase", "switch"])
        let commands = GitCommandFactory.commands(for: "/tmp/repo")

        for command in commands {
            XCTAssertTrue(Set(command.arguments).isDisjoint(with: banned), "Unexpected mutating git argument in \(command.arguments)")
        }
    }
}
