import XCTest
@testable import TimeItCore

final class DurationParsingTests: XCTestCase {
    func testClockFormats() {
        XCTAssertEqual(parseDuration("16:47:23"), 16 * 3600 + 47 * 60 + 23)
        XCTAssertEqual(parseDuration("3:00"), 3 * 3600)
        XCTAssertEqual(parseDuration(" 0:45 "), 45 * 60)
        XCTAssertEqual(parseDuration("25:00:00"), 25 * 3600)
    }

    func testDecimalHoursAndUnits() {
        XCTAssertEqual(parseDuration("3"), 3 * 3600)
        XCTAssertEqual(parseDuration("1.5"), 5400)
        XCTAssertEqual(parseDuration("1h 30m"), 5400)
        XCTAssertEqual(parseDuration("2H15M10S"), 2 * 3600 + 15 * 60 + 10)
        XCTAssertEqual(parseDuration("45m"), 45 * 60)
    }

    func testRejectsNonsense() {
        for text in ["", "abc", "1:60", "1:2:3:4", "-1", "1:-5", "10x", "1h 30", ":"] {
            XCTAssertNil(parseDuration(text), text)
        }
    }
}
