import XCTest
@testable import DiffyCore

final class WorktreeInventoryPolicyTests: XCTestCase {
    func testThreeManualSiblingsProduceNoAutoChildren() {
        let groupID = UUID()
        let deployment = repo("deployment", path: "/tmp/ablafemx", groupID: groupID)
        let free = repo("free", path: "/tmp/ablafemx-free", groupID: groupID)
        let main = repo("main", path: "/tmp/ablafemx-main", groupID: groupID)
        let repositories = [deployment, free, main]
        let entries = [
            entry("/tmp/ablafemx", branch: "deployment-branch"),
            entry("/tmp/ablafemx-free", branch: "free-version"),
            entry("/tmp/ablafemx-main", branch: "main")
        ]

        XCTAssertEqual(WorktreeInventoryPolicy.familyOwnerID(repositories: repositories, entries: entries), deployment.id)
        XCTAssertTrue(WorktreeInventoryPolicy.desiredAutoManagedChildren(parent: deployment, repositories: repositories, entries: entries).isEmpty)
        XCTAssertTrue(WorktreeInventoryPolicy.desiredAutoManagedChildren(parent: free, repositories: repositories, entries: entries).isEmpty)
        XCTAssertTrue(WorktreeInventoryPolicy.desiredAutoManagedChildren(parent: main, repositories: repositories, entries: entries).isEmpty)
    }

    func testOwnerAutoShowsOnlyUnaddedSiblings() {
        let groupID = UUID()
        let deployment = repo("deployment", path: "/tmp/ablafemx", groupID: groupID)
        let free = repo("free", path: "/tmp/ablafemx-free", groupID: groupID)
        let repositories = [deployment, free]
        let entries = [
            entry("/tmp/ablafemx", branch: "deployment-branch"),
            entry("/tmp/ablafemx-free", branch: "free-version"),
            entry("/tmp/ablafemx-main", branch: "main")
        ]

        let desired = WorktreeInventoryPolicy.desiredAutoManagedChildren(parent: deployment, repositories: repositories, entries: entries)

        XCTAssertEqual(desired.map(\.canonicalPath), ["/tmp/ablafemx-main"])
        XCTAssertEqual(desired.first?.entry.branch, .branch("main"))
    }

    func testNonOwnerDoesNotAutoShowUnaddedSiblings() {
        let groupID = UUID()
        let deployment = repo("deployment", path: "/tmp/ablafemx", groupID: groupID)
        let free = repo("free", path: "/tmp/ablafemx-free", groupID: groupID)
        let repositories = [deployment, free]
        let entries = [
            entry("/tmp/ablafemx", branch: "deployment-branch"),
            entry("/tmp/ablafemx-free", branch: "free-version"),
            entry("/tmp/ablafemx-main", branch: "main")
        ]

        XCTAssertTrue(WorktreeInventoryPolicy.desiredAutoManagedChildren(parent: free, repositories: repositories, entries: entries).isEmpty)
    }

    func testDuplicatePathCleanupPrefersUserManagedRows() {
        let groupID = UUID()
        let parent = repo("parent", path: "/tmp/parent", groupID: groupID)
        let auto = repo("auto", path: "/tmp/wt", groupID: groupID, parentID: parent.id, isAutoManaged: true)
        let user = repo("user", path: "/tmp/wt", groupID: groupID)

        let ids = WorktreeInventoryPolicy.duplicateRepositoryIDsToRemove(repositories: [auto, user])

        XCTAssertEqual(ids, [auto.id])
    }

    func testDuplicatePathCleanupKeepsFirstAutoManagedRowWhenNoUserRowExists() {
        let groupID = UUID()
        let parent = repo("parent", path: "/tmp/parent", groupID: groupID)
        let first = repo("first", path: "/tmp/wt", groupID: groupID, parentID: parent.id, isAutoManaged: true)
        let second = repo("second", path: "/tmp/wt", groupID: groupID, parentID: parent.id, isAutoManaged: true)

        let ids = WorktreeInventoryPolicy.duplicateRepositoryIDsToRemove(repositories: [first, second])

        XCTAssertEqual(ids, [second.id])
    }

    private func repo(
        _ name: String,
        path: String,
        groupID: UUID,
        parentID: UUID? = nil,
        isAutoManaged: Bool = false
    ) -> RepositoryConfig {
        RepositoryConfig(
            displayName: name,
            path: path,
            groupID: groupID,
            parentRepositoryID: parentID,
            isAutoManaged: isAutoManaged
        )
    }

    private func entry(_ path: String, branch: String) -> WorktreeEntry {
        WorktreeEntry(path: path, branch: .branch(branch))
    }
}
