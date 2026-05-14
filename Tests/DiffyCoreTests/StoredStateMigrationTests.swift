import XCTest
@testable import DiffyCore

final class StoredStateMigrationTests: XCTestCase {
    func testMigratesLegacyArrayIntoOneGroupPerRepo() throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "displayName": "Alpha",
            "path": "/tmp/alpha",
            "editor": { "systemDefault": {} },
            "diffColors": {
              "additionHex": "#001122",
              "removalHex": "#332211"
            }
          },
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "displayName": "Beta",
            "path": "/tmp/beta",
            "editor": { "systemDefault": {} }
          }
        ]
        """

        let state = try StoredStateMigration.decode(Data(json.utf8))

        XCTAssertEqual(state.repositories.count, 2)
        XCTAssertEqual(state.groups.count, 2)

        let alpha = state.repositories.first { $0.displayName == "Alpha" }
        let beta = state.repositories.first { $0.displayName == "Beta" }
        XCTAssertNotNil(alpha)
        XCTAssertNotNil(beta)

        let alphaGroup = state.groups.first { $0.id == alpha?.groupID }
        let betaGroup = state.groups.first { $0.id == beta?.groupID }
        XCTAssertNotNil(alphaGroup)
        XCTAssertNotNil(betaGroup)
        XCTAssertNotEqual(alphaGroup?.id, betaGroup?.id)

        XCTAssertEqual(alphaGroup?.name, "Alpha")
        XCTAssertEqual(alphaGroup?.diffColors.additionHex, "#001122")
        XCTAssertEqual(alphaGroup?.diffColors.removalHex, "#332211")

        XCTAssertEqual(betaGroup?.name, "Beta")
        XCTAssertEqual(betaGroup?.diffColors.additionHex, DiffColors.default.additionHex)

        XCTAssertFalse(alpha?.isHidden ?? true)
        XCTAssertFalse(beta?.isHidden ?? true)
    }

    func testDecodesEnvelopeShapeUnchanged() throws {
        let groupID = UUID()
        let original = StoredState(
            groups: [
                RepositoryGroup(
                    id: groupID,
                    name: "Frontend",
                    diffColors: .default,
                    badgeLabel: BadgeLabel(text: "fe", position: .above)
                )
            ],
            repositories: [
                RepositoryConfig(
                    id: UUID(),
                    displayName: "web",
                    path: "/tmp/web",
                    groupID: groupID,
                    isHidden: true
                )
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try StoredStateMigration.decode(data)

        XCTAssertEqual(decoded.groups.count, 1)
        XCTAssertEqual(decoded.groups.first?.id, groupID)
        XCTAssertEqual(decoded.groups.first?.badgeLabel?.position, .above)
        XCTAssertEqual(decoded.repositories.first?.groupID, groupID)
        XCTAssertTrue(decoded.repositories.first?.isHidden ?? false)
    }

    func testEmptyLegacyArrayMigratesToEmptyState() throws {
        let state = try StoredStateMigration.decode(Data("[]".utf8))
        XCTAssertTrue(state.groups.isEmpty)
        XCTAssertTrue(state.repositories.isEmpty)
    }
}
