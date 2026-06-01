import XCTest
@testable import DiffyCore

final class GitParsingTests: XCTestCase {
    func testParsesNumstatForTextBinaryAndDeletedFiles() {
        let output = "12\t3\tSources/App.swift\u{0}-\t-\tAssets/logo.png\u{0}0\t8\tSources/Removed.swift\u{0}"

        let stats = GitNumstatParser.parse(output)

        XCTAssertEqual(stats["Sources/App.swift"]?.addedLines, 12)
        XCTAssertEqual(stats["Sources/App.swift"]?.removedLines, 3)
        XCTAssertEqual(stats["Assets/logo.png"]?.isBinary, true)
        XCTAssertEqual(stats["Assets/logo.png"]?.addedLines, 0)
        XCTAssertEqual(stats["Sources/Removed.swift"]?.removedLines, 8)
    }

    func testParsesNumstatForUnicodeFilenames() {
        let output = "4\t2\tSources/мир.swift\u{0}1\t0\tassets/🚀.png\u{0}"

        let stats = GitNumstatParser.parse(output)

        XCTAssertEqual(stats["Sources/мир.swift"]?.addedLines, 4)
        XCTAssertEqual(stats["Sources/мир.swift"]?.removedLines, 2)
        XCTAssertEqual(stats["assets/🚀.png"]?.addedLines, 1)
    }

    func testParsesNumstatForRenamedPath() {
        // Rename record: `<added>\t<removed>\t\0<oldpath>\0<newpath>\0`.
        let output = "5\t3\t\u{0}src/old.swift\u{0}src/new.swift\u{0}9\t1\tSources/Other.swift\u{0}"

        let stats = GitNumstatParser.parse(output)

        XCTAssertEqual(stats["src/new.swift"]?.addedLines, 5)
        XCTAssertEqual(stats["src/new.swift"]?.removedLines, 3)
        XCTAssertNil(stats["src/old.swift"])
        XCTAssertNil(stats["{old.swift => new.swift}"])
        XCTAssertEqual(stats["Sources/Other.swift"]?.addedLines, 9)
    }

    func testParsesPorcelainStatusForTrackedUntrackedAndConflictStates() {
        let output = " M Sources/App.swift\u{0}A  Sources/New.swift\u{0}?? Scratch.txt\u{0}UU Conflict.swift\u{0} D Removed.swift\u{0}"

        let statuses = GitStatusParser.parsePorcelainV1Z(output)

        XCTAssertEqual(statuses["Sources/App.swift"]?.unstagedStatus, .modified)
        XCTAssertEqual(statuses["Sources/New.swift"]?.stagedStatus, .added)
        XCTAssertEqual(statuses["Scratch.txt"]?.unstagedStatus, .untracked)
        XCTAssertEqual(statuses["Conflict.swift"]?.unstagedStatus, .conflicted)
        XCTAssertEqual(statuses["Removed.swift"]?.unstagedStatus, .deleted)
    }

    func testParsesPorcelainRenameAndCopyKeyingNewPathAndSkippingOrigin() {
        // `git status --porcelain=v1 -z` emits renames/copies as two NUL-separated records,
        // NEW path first: `R  new\0old\0` (verified empirically). The parser keys the NEW path
        // and skips the origin record. A trailing normal record proves the index advanced past
        // both two-record entries.
        let output = "R  new.swift\u{0}old.swift\u{0}C  copy.swift\u{0}orig.swift\u{0} M other.swift\u{0}"

        let statuses = GitStatusParser.parsePorcelainV1Z(output)

        XCTAssertEqual(statuses.count, 3)
        XCTAssertEqual(statuses["new.swift"]?.stagedStatus, .renamed)
        XCTAssertNil(statuses["new.swift"]?.unstagedStatus)
        XCTAssertEqual(statuses["copy.swift"]?.stagedStatus, .copied)
        XCTAssertNil(statuses["old.swift"])
        XCTAssertNil(statuses["orig.swift"])
        XCTAssertEqual(statuses["other.swift"]?.unstagedStatus, .modified)
    }

    func testBuildsSummaryRendersRenamedStagedFileAsR() {
        // numstat and status both key the NEW path for a rename, so the join must surface "R".
        let summary = RepoDiffBuilder.build(
            repository: RepositoryConfig(displayName: "Diffy", path: "/tmp/diffy", groupID: UUID()),
            stagedStats: ["src/new.swift": FileLineStat(addedLines: 3, removedLines: 1, isBinary: false)],
            unstagedStats: [:],
            statuses: ["src/new.swift": GitPathStatus(stagedStatus: .renamed, unstagedStatus: nil)],
            untrackedStats: [:]
        )

        XCTAssertEqual(summary.stagedFiles.map(\.path), ["src/new.swift"])
        XCTAssertEqual(summary.stagedFiles.first?.displayStatus, "R")
    }

    func testConflictedAndCopiedHaveDistinctDisplayGlyphs() {
        XCTAssertEqual(GitChangeStatus.copied.displayStatus, "C")
        XCTAssertEqual(GitChangeStatus.conflicted.displayStatus, "!")
        XCTAssertNotEqual(
            GitChangeStatus.conflicted.displayStatus,
            GitChangeStatus.copied.displayStatus
        )
    }

    func testDeletedFileSummaryIsNotOpenableFromWorkingTree() {
        let deleted = ChangedFileSummary(
            path: "Removed.swift",
            displayStatus: GitChangeStatus.deleted.displayStatus,
            addedLines: 0,
            removedLines: 4,
            section: .unstaged
        )
        let modified = ChangedFileSummary(
            path: "Changed.swift",
            displayStatus: GitChangeStatus.modified.displayStatus,
            addedLines: 1,
            removedLines: 1,
            section: .unstaged
        )

        XCTAssertFalse(deleted.isOpenableFromWorkingTree)
        XCTAssertTrue(modified.isOpenableFromWorkingTree)
    }

    func testBuildsSummaryWithSeparateStagedAndUnstagedSections() {
        let stagedStats = [
            "Sources/App.swift": FileLineStat(addedLines: 4, removedLines: 1, isBinary: false)
        ]
        let unstagedStats = [
            "Sources/App.swift": FileLineStat(addedLines: 2, removedLines: 3, isBinary: false),
            "Sources/Other.swift": FileLineStat(addedLines: 5, removedLines: 0, isBinary: false)
        ]
        let statuses = [
            "Sources/App.swift": GitPathStatus(stagedStatus: .modified, unstagedStatus: .modified),
            "Sources/Other.swift": GitPathStatus(stagedStatus: nil, unstagedStatus: .modified),
            "Notes.md": GitPathStatus(stagedStatus: nil, unstagedStatus: .untracked)
        ]
        let untrackedStats = [
            "Notes.md": FileLineStat(addedLines: 7, removedLines: 0, isBinary: false)
        ]

        let summary = RepoDiffBuilder.build(
            repository: RepositoryConfig(displayName: "Diffy", path: "/tmp/diffy", groupID: UUID()),
            stagedStats: stagedStats,
            unstagedStats: unstagedStats,
            statuses: statuses,
            untrackedStats: untrackedStats
        )

        XCTAssertEqual(summary.addedLines, 18)
        XCTAssertEqual(summary.removedLines, 4)
        XCTAssertEqual(summary.stagedFiles.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(summary.unstagedFiles.map(\.path), ["Notes.md", "Sources/App.swift", "Sources/Other.swift"])
        XCTAssertEqual(summary.unstagedFiles.first { $0.path == "Notes.md" }?.displayStatus, "U")
        XCTAssertEqual(summary.stagedFiles.first?.displayStatus, "M")
    }
}
