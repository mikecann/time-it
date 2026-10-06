import XCTest
@testable import TimeItCore

final class RecentDailyAveragesTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ zone: String = "Australia/Perth") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func entry(_ start: String, _ end: String?, category: String = "convex", deleted: Bool = false) -> TimeEntry {
        TimeEntry(categoryId: category, startedAt: date(start).milliseconds, endedAt: end.map { date($0).milliseconds }, deleted: deleted, deviceId: "test")
    }

    func testPreviousThirtyCompleteDaysExcludeTodayOldHistoryAndEmptyDays() {
        let averages = RecentDailyAverages(entries: [
            entry("2026-09-05T15:00:00Z", "2026-09-05T16:00:00Z"),
            entry("2026-09-06T00:00:00Z", "2026-09-06T06:00:00Z"),
            entry("2026-09-20T00:00:00Z", "2026-09-20T02:00:00Z"),
            entry("2026-10-05T00:00:00Z", "2026-10-05T08:00:00Z"),
            entry("2026-10-06T00:00:00Z", nil),
            entry("2026-10-04T00:00:00Z", "2026-10-04T12:00:00Z", deleted: true),
        ], now: date("2026-10-06T02:00:00Z"), calendar: calendar())
        XCTAssertEqual(averages.interval.start, date("2026-09-05T16:00:00Z"))
        XCTAssertEqual(averages.interval.end, date("2026-10-05T16:00:00Z"))
        XCTAssertEqual(averages.recordedDays, 3)
        XCTAssertEqual(averages.averageRecordedDay, 16 * 3600 / 3)
        XCTAssertEqual(averages.sixHourDays, 2)
        XCTAssertEqual(averages.averageSixHourDay, 7 * 3600)
    }

    func testSixHourThresholdCombinesSessionsAfterCategoryFilteringAndMidnightSplitting() {
        let entries = [
            entry("2026-10-03T15:00:00Z", "2026-10-03T17:00:00Z"), // One hour on each local day.
            entry("2026-10-04T00:00:00Z", "2026-10-04T05:00:00Z"), // Exactly six hours on 4 October.
            entry("2026-10-05T00:00:00Z", "2026-10-05T05:59:59Z"),
            entry("2026-10-05T06:00:00Z", "2026-10-05T08:00:00Z", category: "personal"),
        ]
        let filtered = RecentDailyAverages(entries: entries, categoryId: "convex", now: date("2026-10-06T02:00:00Z"), calendar: calendar())
        XCTAssertEqual(filtered.recordedDays, 3)
        XCTAssertEqual(filtered.sixHourDays, 1)
        XCTAssertEqual(filtered.averageSixHourDay, 6 * 3600)
        let all = RecentDailyAverages(entries: entries, now: date("2026-10-06T02:00:00Z"), calendar: calendar())
        XCTAssertEqual(all.sixHourDays, 2)
        XCTAssertEqual(all.averageSixHourDay!, (14 * 3600 - 1) / 2, accuracy: 0.0001)
    }

    func testWindowUsesCalendarDaysAcrossDaylightSaving() {
        let averages = RecentDailyAverages(entries: [entry("2026-10-03T14:00:00Z", "2026-10-04T13:00:00Z")], now: date("2026-10-06T04:00:00Z"), calendar: calendar("Australia/Sydney"))
        XCTAssertEqual(averages.interval.duration, (30 * 24 - 1) * 3600)
        XCTAssertEqual(averages.recordedDays, 1)
        XCTAssertEqual(averages.averageRecordedDay, 23 * 3600)
        XCTAssertEqual(averages.averageSixHourDay, 23 * 3600)
    }

    func testEmptyAndNoQualifyingDaysHaveNoAverage() {
        let empty = RecentDailyAverages(entries: [], now: date("2026-10-06T02:00:00Z"), calendar: calendar())
        XCTAssertEqual(empty.recordedDays, 0)
        XCTAssertEqual(empty.sixHourDays, 0)
        XCTAssertNil(empty.averageRecordedDay)
        XCTAssertNil(empty.averageSixHourDay)
        let short = RecentDailyAverages(entries: [entry("2026-10-05T00:00:00Z", "2026-10-05T01:00:00Z")], now: date("2026-10-06T02:00:00Z"), calendar: calendar())
        XCTAssertEqual(short.averageRecordedDay, 3600)
        XCTAssertNil(short.averageSixHourDay)
    }
}
