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
            badgeLabel: nil,
            hasError: false
        )
        let renamed = BadgeState(
            displayName: "New",
            added: 1,
            removed: 2,
            visibleRepoCount: 1,
            colors: .default,
            badgeLabel: nil,
            hasError: false
        )

        XCTAssertNotEqual(original, renamed)
    }

    func testBadgeStateChangesWhenErrorStateChanges() {
        let healthy = BadgeState(
            displayName: "Group",
            added: 0,
            removed: 0,
            visibleRepoCount: 1,
            colors: .default,
            badgeLabel: nil,
            hasError: false
        )
        let errored = BadgeState(
            displayName: "Group",
            added: 0,
            removed: 0,
            visibleRepoCount: 1,
            colors: .default,
            badgeLabel: nil,
            hasError: true
        )

        XCTAssertNotEqual(healthy, errored)
    }
}
