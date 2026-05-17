import XCTest
import DiffyCore
@testable import Diffy

final class StatusItemManagerTests: XCTestCase {
    func testBadgeStateChangesWhenDisplayNameChanges() {
        let original = BadgeState(
            displayName: "Old",
            added: 1,
            removed: 2,
            visibleRepoCount: 1,
            colors: .default,
            badgeLabel: nil
        )
        let renamed = BadgeState(
            displayName: "New",
            added: 1,
            removed: 2,
            visibleRepoCount: 1,
            colors: .default,
            badgeLabel: nil
        )

        XCTAssertNotEqual(original, renamed)
    }
}
