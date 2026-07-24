import Combine
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

        store.addRepository(path: invalidRepo.path, destination: .newGroup)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.repositories.isEmpty)
        XCTAssertEqual(store.lastAddError, "Not a readable git repository: \(invalidRepo.path)")
    }

    func testAddingRepositoryUsesSelectedExistingGroup() throws {
        let tempDir = try makeTemporaryDirectory()
        let repositoryURL = tempDir.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init"], in: repositoryURL)

        let group = RepositoryGroup(name: "Existing")
        let storageURL = try writeState(groups: [group], repositories: [])
        let store = DiffyStore(storageURL: storageURL)
        defer { store.stop() }
        store.load()

        store.addRepository(path: repositoryURL.path, destination: .existingGroup(group.id))

        XCTAssertEqual(store.groups.map(\.id), [group.id])
        XCTAssertEqual(store.repositories.count, 1)
        XCTAssertEqual(store.repositories.first?.groupID, group.id)
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
        store.addRepository(path: childURL.path, destination: .existingGroup(group.id))

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

    func testRecentCommitLimitPersistsWithoutEagerHistoryLoading() throws {
        let group = RepositoryGroup(name: "Group")
        let repository = RepositoryConfig(displayName: "repo", path: "/tmp/repo", groupID: group.id)
        let storageURL = try writeState(groups: [group], repositories: [repository])
        let store = DiffyStore(storageURL: storageURL)
        store.load()

        XCTAssertNil(store.commitHistories[repository.id])
        store.updateRecentCommitLimit(for: repository.id, limit: 2)

        let persisted = try StoredStateMigration.decode(Data(contentsOf: storageURL))
        XCTAssertEqual(persisted.repositories.first?.recentCommitLimit, 2)
    }

    // MARK: - Removal cascades (git-free)

    func testRemoveRepositoryCascadesToAutoManagedChildren() throws {
        let group = RepositoryGroup(name: "Group")
        let parent = RepositoryConfig(displayName: "parent", path: "/tmp/parent", groupID: group.id)
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

        store.removeRepository(parent)

        XCTAssertTrue(store.repositories.isEmpty)
        XCTAssertNil(store.summaries[parent.id])
        XCTAssertNil(store.summaries[child.id])
        XCTAssertEqual(store.groups.count, 1, "Removing a repo preserves its now-empty group")
    }

    func testRemoveGroupDeleteReposCascadesToChildren() throws {
        let group = RepositoryGroup(name: "Group")
        let parent = RepositoryConfig(displayName: "parent", path: "/tmp/parent", groupID: group.id)
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

        store.removeGroup(group.id, mode: .deleteRepos)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.repositories.isEmpty)
    }

    func testRemoveGroupDissolveReassignsParentsAndChildrenToNewGroups() throws {
        let group = RepositoryGroup(name: "Shared")
        let parentA = RepositoryConfig(displayName: "A", path: "/tmp/a", groupID: group.id)
        let childA = RepositoryConfig(
            displayName: "A-wt", path: "/tmp/a-wt", groupID: group.id,
            parentRepositoryID: parentA.id, isAutoManaged: true
        )
        let parentB = RepositoryConfig(displayName: "B", path: "/tmp/b", groupID: group.id)
        let childB = RepositoryConfig(
            displayName: "B-wt", path: "/tmp/b-wt", groupID: group.id,
            parentRepositoryID: parentB.id, isAutoManaged: true
        )
        let storageURL = try writeState(groups: [group], repositories: [parentA, childA, parentB, childB])
        let store = DiffyStore(storageURL: storageURL)
        store.load()

        store.removeGroup(group.id, mode: .dissolveIntoStandalone)

        XCTAssertFalse(store.groups.contains { $0.id == group.id })
        XCTAssertEqual(store.groups.count, 2)
        XCTAssertEqual(store.repositories.count, 4)

        let a = try XCTUnwrap(store.repositories.first { $0.id == parentA.id })
        let aChild = try XCTUnwrap(store.repositories.first { $0.id == childA.id })
        let b = try XCTUnwrap(store.repositories.first { $0.id == parentB.id })
        let bChild = try XCTUnwrap(store.repositories.first { $0.id == childB.id })

        XCTAssertEqual(a.groupID, aChild.groupID, "Child follows its parent into the new group")
        XCTAssertEqual(b.groupID, bChild.groupID)
        XCTAssertNotEqual(a.groupID, b.groupID, "Each parent dissolves into its own standalone group")
        XCTAssertNotEqual(a.groupID, group.id, "Reassigned away from the dissolved group")
    }

    // MARK: - Worktree reconcile (real git)

    func testAddingParentAutoDiscoversLinkedWorktreeChild() throws {
        let (store, _, childURL) = try makeStoreWithDiscoveredWorktreeChild()
        defer { store.stop() }

        XCTAssertEqual(store.repositories.count, 2)
        let parent = try XCTUnwrap(store.repositories.first { !$0.isAutoManaged })
        let child = try XCTUnwrap(store.repositories.first { $0.isAutoManaged })
        XCTAssertEqual(child.parentRepositoryID, parent.id)
        XCTAssertEqual(child.groupID, parent.groupID)
        XCTAssertEqual(DiffyCore.canonicalPath(child.path), DiffyCore.canonicalPath(childURL.path))
    }

    func testRemovingWorktreePrunesAutoManagedChildOnRefresh() throws {
        let (store, repoURL, childURL) = try makeStoreWithDiscoveredWorktreeChild()
        defer { store.stop() }
        let parentID = try XCTUnwrap(store.repositories.first { !$0.isAutoManaged }).id

        try waitForRepositoryCount(store, count: 1) {
            try self.runGit(["worktree", "remove", childURL.path], in: repoURL)
            store.refresh(repositoryID: parentID)
        }

        XCTAssertEqual(store.repositories.count, 1)
        XCTAssertTrue(store.repositories.allSatisfy { !$0.isAutoManaged })
    }

    /// Builds a temp repo with one commit + a linked `feature` worktree, points a fresh store at
    /// it, adds the repo, and waits until the auto-managed child row is reconciled into existence.
    private func makeStoreWithDiscoveredWorktreeChild() throws -> (store: DiffyStore, repoURL: URL, childURL: URL) {
        let tempDir = try makeTemporaryDirectory()
        let repoURL = tempDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init"], in: repoURL)
        try runGit(["config", "user.email", "diffy@example.com"], in: repoURL)
        try runGit(["config", "user.name", "Diffy Tests"], in: repoURL)
        try "one\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)

        let childURL = tempDir.appendingPathComponent("child")
        try runGit(["worktree", "add", "-b", "feature", childURL.path], in: repoURL)

        let store = DiffyStore(storageURL: tempDir.appendingPathComponent("repositories.json"))
        try waitForRepositoryCount(store, count: 2) {
            store.addRepository(path: repoURL.path, destination: .newGroup)
        }
        return (store, repoURL, childURL)
    }

    /// Subscribe to `$repositories`, run `trigger`, and block until the row count reaches `count`.
    /// Subscribing first guards against missing a fast synchronous mutation; over-fulfillment is
    /// tolerated because polling/FSEvents may re-emit the same count.
    private func waitForRepositoryCount(
        _ store: DiffyStore,
        count: Int,
        timeout: TimeInterval = 5,
        _ trigger: () throws -> Void
    ) throws {
        let expectation = XCTestExpectation(description: "repositories.count == \(count)")
        expectation.assertForOverFulfill = false
        let cancellable = store.$repositories.sink { repos in
            if repos.count == count { expectation.fulfill() }
        }
        defer { cancellable.cancel() }
        try trigger()
        wait(for: [expectation], timeout: timeout)
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
