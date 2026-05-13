import XCTest
@testable import DiffyCore

final class GitParsingTests: XCTestCase {
    func testParsesNumstatForTextBinaryAndDeletedFiles() {
        let output = """
        12\t3\tSources/App.swift
        -\t-\tAssets/logo.png
        0\t8\tSources/Removed.swift

        """

        let stats = GitNumstatParser.parse(output)

        XCTAssertEqual(stats["Sources/App.swift"]?.addedLines, 12)
        XCTAssertEqual(stats["Sources/App.swift"]?.removedLines, 3)
        XCTAssertEqual(stats["Assets/logo.png"]?.isBinary, true)
        XCTAssertEqual(stats["Assets/logo.png"]?.addedLines, 0)
        XCTAssertEqual(stats["Sources/Removed.swift"]?.removedLines, 8)
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
            repository: RepositoryConfig(displayName: "Diffy", path: "/tmp/diffy"),
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
