import XCTest
@testable import Route_Builder

@MainActor
final class ShellTests: XCTestCase {
    func testBaseURLConstant() {
        XCTAssertEqual(AppConfig.baseURL.absoluteString, "http://127.0.0.1:4000")
    }
}
