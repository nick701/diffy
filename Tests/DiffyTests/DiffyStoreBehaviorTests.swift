import XCTest
import DiffyCore
@testable import Diffy

@MainActor
final class DiffyStoreBehaviorTests: XCTestCase {
    func testVisibleChildRemainsOrderedWhenParentIsHidden() throws {
        let group = RepositoryGroup(name: "Group")
        let parent = RepositoryConfig(
            displayName: "parent",
            path: "/tmp/parent",
            groupID: group.id,
            isHidden: true
        )
        let child = RepositoryConfig(
            displayName: "child",
            path: "/tmp/child",
            groupID: group.id,
            parentRepositoryID: parent.id,
            isAutoManaged: true
        )
        let storageURL = try writeState(groups: [group], repositories: [parent, child])
        let store = DiffyStore(storageURL: storageURL)

        store.load()

        XCTAssertEqual(store.orderedRepositories(in: group.id, includeHidden: false).map(\.id), [child.id])
    }

    func testHiddenChildStaysExcludedFromVisibleOrdering() throws {
        let group = RepositoryGroup(name: "Group")
        let parent = RepositoryConfig(displayName: "parent", path: "/tmp/parent", groupID: group.id)
        let child = RepositoryConfig(
            displayName: "child",
            path: "/tmp/child",
            groupID: group.id,
            isHidden: true,
            parentRepositoryID: parent.id,
            isAutoManaged: true
        )
        let storageURL = try writeState(groups: [group], repositories: [parent, child])
        let store = DiffyStore(storageURL: storageURL)

        store.load()

        XCTAssertEqual(store.orderedRepositories(in: group.id, includeHidden: false).map(\.id), [parent.id])
    }

    func testInvalidRepositoryPathDoesNotCreateRows() throws {
        let tempDir = try makeTemporaryDirectory()
        let store = DiffyStore(storageURL: tempDir.appendingPathComponent("repositories.json"))
        let invalidRepo = tempDir.appendingPathComponent("not-a-repo")
        try FileManager.default.createDirectory(at: invalidRepo, withIntermediateDirectories: true)

        store.addRepository(path: invalidRepo.path)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.repositories.isEmpty)
        XCTAssertEqual(store.lastAddError, "Not a readable git repository: \(invalidRepo.path)")
    }

    func testAddingExistingAutoManagedPathPromotesWithoutCreatingDuplicate() throws {
        let tempDir = try makeTemporaryDirectory()
        let parentURL = tempDir.appendingPathComponent("parent")
        let childURL = tempDir.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        try runGit(["init"], in: parentURL)
        try runGit(["init"], in: childURL)

        let group = RepositoryGroup(name: "Group")
        let parent = RepositoryConfig(displayName: "parent", path: parentURL.path, groupID: group.id)
        let child = RepositoryConfig(
            displayName: "child",
            path: childURL.path,
            groupID: group.id,
            parentRepositoryID: parent.id,
            isAutoManaged: true
        )
        let storageURL = try writeState(groups: [group], repositories: [parent, child])
        let store = DiffyStore(storageURL: storageURL)
        defer { store.stop() }

        store.load()
        store.addRepository(path: childURL.path)

        XCTAssertEqual(store.repositories.count, 2)
        XCTAssertEqual(store.groups.count, 1)
        let promoted = try XCTUnwrap(store.repositories.first { $0.id == child.id })
        XCTAssertFalse(promoted.isAutoManaged)
        XCTAssertNil(promoted.parentRepositoryID)
        XCTAssertNil(store.lastAddError)
    }

    func testCorruptStateSetsLoadErrorAndDoesNotCreateRows() throws {
        let storageURL = try makeTemporaryDirectory().appendingPathComponent("repositories.json")
        try "{".write(to: storageURL, atomically: true, encoding: .utf8)
        let store = DiffyStore(storageURL: storageURL)

        store.load()

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.repositories.isEmpty)
        XCTAssertNotNil(store.lastLoadError)
    }

    private func writeState(groups: [RepositoryGroup], repositories: [RepositoryConfig]) throws -> URL {
        let storageURL = try makeTemporaryDirectory().appendingPathComponent("repositories.json")
        let data = try JSONEncoder().encode(StoredState(groups: groups, repositories: repositories))
        try data.write(to: storageURL)
        return storageURL
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiffyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}
