import XCTest
@testable import TToolkit

final class TToolkitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(TToolkit().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
