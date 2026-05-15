import XCTest
@testable import DiffyCore

final class GitWorktreeParserTests: XCTestCase {
    func testSingleMainWorktreeOnBranch() {
        let output = """
        worktree /tmp/main
        HEAD abcdef0123456789abcdef0123456789abcdef01
        branch refs/heads/main

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "/tmp/main")
        XCTAssertEqual(entries[0].headSHA, "abcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(entries[0].branch, .branch("main"))
        XCTAssertFalse(entries[0].isLocked)
        XCTAssertFalse(entries[0].isPrunable)
    }

    func testMainPlusOneLinkedBothBranched() {
        let output = """
        worktree /tmp/main
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /tmp/wt-feature
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/feature

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].path, "/tmp/main")
        XCTAssertEqual(entries[0].branch, .branch("main"))
        XCTAssertEqual(entries[1].path, "/tmp/wt-feature")
        XCTAssertEqual(entries[1].branch, .branch("feature"))
    }

    func testDetachedWorktreeYieldsShortSHA() {
        let output = """
        worktree /tmp/wt
        HEAD 0123456789abcdef0123456789abcdef01234567
        detached

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, .detached(shortSHA: "0123456"))
        if case .detached(let sha) = entries[0].branch {
            XCTAssertEqual(sha.count, 7)
        } else {
            XCTFail("Expected detached state")
        }
    }

    func testBareWorktree() {
        let output = """
        worktree /tmp/bare
        bare

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].branch, .bare)
    }

    func testLockedEntryWithAndWithoutReason() {
        let withReason = """
        worktree /tmp/wt
        HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        branch refs/heads/foo
        locked needs human

        """
        let withoutReason = """
        worktree /tmp/wt2
        HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        branch refs/heads/bar
        locked

        """
        XCTAssertTrue(GitWorktreeParser.parse(withReason).first?.isLocked == true)
        XCTAssertTrue(GitWorktreeParser.parse(withoutReason).first?.isLocked == true)
    }

    func testPrunableEntryIsFlagged() {
        let output = """
        worktree /tmp/wt-gone
        HEAD cccccccccccccccccccccccccccccccccccccccc
        branch refs/heads/gone
        prunable gitdir file points to non-existent location

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isPrunable)
    }

    func testEmptyInputReturnsEmptyArray() {
        XCTAssertTrue(GitWorktreeParser.parse("").isEmpty)
    }

    func testUnicodeBranchName() {
        let output = """
        worktree /tmp/wt
        HEAD dddddddddddddddddddddddddddddddddddddddd
        branch refs/heads/feature/üñîçødé

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.first?.branch, .branch("feature/üñîçødé"))
    }

    func testBranchRefThatIsNotUnderRefsHeadsIsKeptAsIs() {
        let output = """
        worktree /tmp/wt
        HEAD eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
        branch refs/remotes/origin/main

        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.first?.branch, .branch("refs/remotes/origin/main"))
    }

    func testTrailingRecordWithoutBlankLineStillParses() {
        let output = """
        worktree /tmp/main
        HEAD ffffffffffffffffffffffffffffffffffffffff
        branch refs/heads/main
        """
        let entries = GitWorktreeParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, "/tmp/main")
    }
}
