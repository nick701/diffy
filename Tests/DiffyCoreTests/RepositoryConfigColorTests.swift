import XCTest
@testable import DiffyCore

final class RepositoryConfigColorTests: XCTestCase {
    func testDecodesOldRepositoryConfigWithDefaultDiffColors() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "displayName": "Diffy",
          "path": "/tmp/diffy",
          "editor": {
            "systemDefault": {}
          }
        }
        """

        let config = try JSONDecoder().decode(RepositoryConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.diffColors.additionHex, DiffColors.default.additionHex)
        XCTAssertEqual(config.diffColors.removalHex, DiffColors.default.removalHex)
        XCTAssertNil(config.diffColors.badgeBackgroundHex)
    }

    func testRoundTripsCustomDiffColors() throws {
        let config = RepositoryConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Diffy",
            path: "/tmp/diffy",
            diffColors: DiffColors(
                additionHex: "#11AA44",
                removalHex: "#DD3355",
                badgeBackgroundHex: "#223344"
            )
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RepositoryConfig.self, from: data)

        XCTAssertEqual(decoded.diffColors.additionHex, "#11AA44")
        XCTAssertEqual(decoded.diffColors.removalHex, "#DD3355")
        XCTAssertEqual(decoded.diffColors.badgeBackgroundHex, "#223344")
    }

    func testDefaultBadgeBackgroundIsTransparent() {
        XCTAssertNil(DiffColors.default.badgeBackgroundHex)
    }
}
