import XCTest
@testable import DiffyCore

final class StoredStateLegacyDecodeTests: XCTestCase {
    /// New fields on `RepositoryConfig` (added 2026-05-15: `parentRepositoryID`, `isAutoManaged`)
    /// must round-trip through encode/decode without losing values.
    /// Legacy decode paths (envelope without these fields, pre-groups array) are covered by
    /// `StoredStateMigrationTests` — extending them with these defaults works because the new
    /// fields use `decodeIfPresent`.
    func testCurrentEnvelopeWithNewFieldsRoundTrips() throws {
        let parentID = UUID()
        let groupID = UUID()
        let child = RepositoryConfig(
            id: UUID(),
            displayName: "wt-feature",
            path: "/tmp/wt-feature",
            groupID: groupID,
            isHidden: false,
            parentRepositoryID: parentID,
            isAutoManaged: true
        )
        let state = StoredState(
            groups: [RepositoryGroup(id: groupID, name: "g")],
            repositories: [child]
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try StoredStateMigration.decode(encoded)

        XCTAssertEqual(decoded.repositories.count, 1)
        XCTAssertEqual(decoded.repositories[0].parentRepositoryID, parentID)
        XCTAssertTrue(decoded.repositories[0].isAutoManaged)
    }
}
