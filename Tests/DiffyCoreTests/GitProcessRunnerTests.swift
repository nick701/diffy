import XCTest
@testable import DiffyCore

final class GitProcessRunnerTests: XCTestCase {
    func testRunDrainsLargeStdoutWithoutDeadlock() throws {
        let command = GitCommand(
            executable: "/bin/sh",
            arguments: ["-c", "yes line | head -c 200000"]
        )
        let output = try GitProcessRunner().run(command)
        XCTAssertGreaterThanOrEqual(output.utf8.count, 200_000)
    }

    func testRunDrainsLargeStderrAndSurfacesItInError() {
        let command = GitCommand(
            executable: "/bin/sh",
            arguments: ["-c", "yes line | head -c 200000 1>&2; exit 1"]
        )
        do {
            _ = try GitProcessRunner().run(command)
            XCTFail("Expected commandFailed error")
        } catch let GitClientError.commandFailed(message) {
            XCTAssertGreaterThanOrEqual(message.utf8.count, 200_000)
        } catch {
            XCTFail("Expected GitClientError.commandFailed, got \(error)")
        }
    }
}
