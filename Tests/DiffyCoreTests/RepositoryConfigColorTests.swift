import XCTest
@testable import DiffyCore

final class RepositoryConfigColorTests: XCTestCase {
    func testRepositoryConfigDecodesWithDefaultEditorAndHidden() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "displayName": "Diffy",
          "path": "/tmp/diffy",
          "groupID": "00000000-0000-0000-0000-000000000099"
        }
        """

        let config = try JSONDecoder().decode(RepositoryConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.editor, .systemDefault)
        XCTAssertEqual(config.groupID, UUID(uuidString: "00000000-0000-0000-0000-000000000099"))
        XCTAssertFalse(config.isHidden)
    }

    func testRepositoryConfigRoundTripsHiddenAndGroupID() throws {
        let groupID = UUID()
        let config = RepositoryConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Diffy",
            path: "/tmp/diffy",
            groupID: groupID,
            isHidden: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RepositoryConfig.self, from: data)

        XCTAssertEqual(decoded.groupID, groupID)
        XCTAssertTrue(decoded.isHidden)
    }

    func testDefaultBadgeBackgroundIsTransparent() {
        XCTAssertNil(DiffColors.default.badgeBackgroundHex)
    }
}
