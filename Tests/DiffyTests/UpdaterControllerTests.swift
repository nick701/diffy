import XCTest
@testable import Diffy

@MainActor
final class UpdaterControllerTests: XCTestCase {
    func testDevBundleWithoutSparkleMetadataCannotCheckForUpdates() {
        let controller = UpdaterController()

        XCTAssertFalse(controller.canCheckForUpdates)
    }
}
