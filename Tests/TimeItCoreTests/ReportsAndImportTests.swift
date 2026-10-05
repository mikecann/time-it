import XCTest
@testable import TimeItCore

final class ReportsAndImportTests: XCTestCase {
    private func calendar(_ zone: String = "Australia/Perth") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func entry(_ start: String, _ end: String?, category: String = "convex", deleted: Bool = false) -> TimeEntry {
        TimeEntry(categoryId: category, startedAt: date(start).milliseconds, endedAt: end.map { date($0).milliseconds }, deleted: deleted, deviceId: "test")
    }
    func testOvernightSessionsSplitIntoLocalDaysAndKeepCategoryTotals() {
        let report = TimeReport(entries: [entry("2026-10-04T15:30:00Z", "2026-10-04T17:30:00Z"), entry("2026-10-05T01:00:00Z", "2026-10-05T02:00:00Z", category: "personal")], interval: DateInterval(start: date("2026-10-03T16:00:00Z"), end: date("2026-10-05T16:00:00Z")), now: date("2026-10-06T00:00:00Z"), calendar: calendar())
        XCTAssertEqual(report.days.map(\.seconds), [1800, 9000])
        XCTAssertEqual(report.total, 10800)
        XCTAssertEqual(report.categorySeconds["personal"], 3600)
        XCTAssertEqual(report.averageActiveDay, 5400)
        XCTAssertEqual(report.buckets.reduce(0) { $0 + $1.seconds }, report.total)
    }
    func testDSTDaysUseCalendarBoundaries() {
        let interval = DateInterval(start: date("2026-10-03T14:00:00Z"), end: date("2026-10-04T13:00:00Z"))
        let report = TimeReport(entries: [entry("2026-10-03T14:00:00Z", "2026-10-04T13:00:00Z")], interval: interval, now: interval.end, calendar: calendar("Australia/Sydney"))
        XCTAssertEqual(report.days.count, 1)
        XCTAssertEqual(report.total, 23 * 3600)
    }
    func testFilteringTombstonesRunningAndFutureTime() {
        let now = date("2026-10-05T02:00:00Z")
        let report = TimeReport(entries: [entry("2026-10-05T01:00:00Z", nil), entry("2026-10-05T00:00:00Z", "2026-10-05T01:00:00Z", deleted: true), entry("2026-10-05T00:00:00Z", "2026-10-05T01:00:00Z", category: "personal"), entry("2026-10-05T03:00:00Z", nil)], interval: DateInterval(start: date("2026-10-04T16:00:00Z"), end: date("2026-10-05T16:00:00Z")), categoryId: "convex", now: now, calendar: calendar())
        XCTAssertEqual(report.total, 3600)
        XCTAssertEqual(report.sessionCount, 1)
        XCTAssertEqual(report.activeDays, 1)
    }
    func testOverlapCountsUnionAndClipsToSelectedRange() {
        let report = TimeReport(entries: [entry("2026-10-05T00:00:00Z", "2026-10-05T02:00:00Z"), entry("2026-10-05T01:00:00Z", "2026-10-05T03:00:00Z"), entry("2026-10-05T01:30:00Z", "2026-10-05T02:00:00Z")], interval: DateInterval(start: date("2026-10-05T01:00:00Z"), end: date("2026-10-05T03:00:00Z")), now: date("2026-10-05T04:00:00Z"), calendar: calendar())
        XCTAssertEqual(report.total, 3.5 * 3600)
        XCTAssertEqual(report.overlapSeconds, 1.5 * 3600)
    }
    func testLongRangeGroupsMonthsAndKeepsZeroPeriods() {
        let interval = DateInterval(start: date("2024-01-01T00:00:00Z"), end: date("2026-01-01T00:00:00Z"))
        let report = TimeReport(entries: [entry("2024-01-05T01:00:00Z", "2024-01-05T02:00:00Z")], interval: interval, now: interval.end, calendar: calendar("UTC"))
        XCTAssertEqual(report.granularity, .month)
        XCTAssertEqual(Set(report.buckets.map(\.date)).count, 24)
        XCTAssertEqual(report.buckets.reduce(0) { $0 + $1.seconds }, 3600)
        let empty = TimeReport(entries: [], interval: interval, now: interval.end, calendar: calendar())
        XCTAssertEqual(empty.averageActiveDay, 0)
        XCTAssertEqual(empty.overlapSeconds, 0)
    }

    private func archive() -> ClockifyArchive {
        let category = Category(clientId: "clockify:category:convex", name: "Convex", deviceId: "import")
        let entry = TimeEntry(clientId: "clockify:workspace:entry", categoryId: category.id, startedAt: 1000, endedAt: 61000, deviceId: "import")
        return ClockifyArchive(categories: [category], entries: [entry])
    }
    @MainActor private func store() throws -> TimeStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
    }
    func testImportPreservesActiveTimerAndQueuesHistoryWithBackup() async throws {
        try await MainActor.run {
            let store = try store()
            try store.start(at: date("2026-10-05T01:00:00Z"))
            let before = store.state
            let result = try store.importClockify(archive())
            XCTAssertEqual(store.activeEntry, before.entries.first)
            XCTAssertEqual(result.added, 1)
            XCTAssertEqual(result.categoriesAdded, 0)
            XCTAssertEqual(store.entries.first { $0.id.hasPrefix("clockify:") }?.categoryId, "convex")
            XCTAssertTrue(store.state.pendingEntries.contains("clockify:workspace:entry"))
            XCTAssertEqual(try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: result.backupURL)), before)
        }
    }
    func testReimportPreservesEditsAndTombstones() async throws {
        try await MainActor.run {
            let store = try store()
            _ = try store.importClockify(archive())
            try store.updateEntry(id: "clockify:workspace:entry", categoryId: "convex", note: "Edited", start: Date(milliseconds: 1000), end: Date(milliseconds: 61000))
            let edited = store.entries.first!
            XCTAssertEqual(try store.importClockify(archive()).added, 0)
            XCTAssertEqual(store.entries.first, edited)
            try store.deleteEntry(id: edited.id)
            let deleted = store.state.entries.first!
            XCTAssertEqual(try store.importClockify(archive()).existing, 1)
            XCTAssertEqual(store.state.entries.first, deleted)
            XCTAssertTrue(store.entries.isEmpty)
        }
    }
    func testInvalidArchiveIsRejectedBeforeAnyImport() async throws {
        try await MainActor.run {
            let store = try store()
            let before = store.state
            var archive = archive()
            archive.entries[0].endedAt = nil
            XCTAssertThrowsError(try store.importClockify(archive))
            archive = self.archive(); archive.entries.append(archive.entries[0])
            XCTAssertThrowsError(try store.importClockify(archive))
            archive = self.archive(); archive.categories[0].color = "red"
            XCTAssertThrowsError(try store.importClockify(archive))
            XCTAssertEqual(store.state, before)
        }
    }
    func testFailedImportWriteLeavesActiveAndHistoryUntouched() async throws {
        try await MainActor.run {
            let initial = try store(); try initial.start()
            let failing = try TimeStore(fileURL: initial.fileURL, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            let before = failing.state
            XCTAssertThrowsError(try failing.importClockify(archive()))
            XCTAssertEqual(failing.state, before)
            XCTAssertEqual(try TimeStore(fileURL: initial.fileURL).state, before)
        }
    }
    @MainActor func testImportedHistorySurvivesOfflineRestartThenDrainsMultipleSyncBatches() async throws {
        let original = try store()
        try original.start()
        let active = original.activeEntry
        var archive = archive()
        archive.entries = (0..<205).map { index in
            var entry = archive.entries[0]
            entry.clientId = "clockify:workspace:\(index)"
            return entry
        }
        _ = try original.importClockify(archive)
        do {
            try await SyncEngine.run(store: original, download: false) { _ in throw URLError(.notConnectedToInternet) }
            XCTFail("An offline sync should fail")
        } catch {}
        let restored = try TimeStore(fileURL: original.fileURL)
        XCTAssertEqual(restored.activeEntry, active)
        var uploaded: [String] = []
        var batches = 0
        try await SyncEngine.run(store: restored, download: false) { request in
            XCTAssertLessThanOrEqual(request.entries.count, 100)
            uploaded += request.entries.map(\.id)
            batches += 1
            return SyncResponse(acknowledgedCategories: request.categories, acknowledgedEntries: request.entries)
        }
        XCTAssertEqual(batches, 3)
        XCTAssertEqual(uploaded.count, 206)
        XCTAssertEqual(Set(uploaded).count, 206)
        XCTAssertEqual(restored.pendingCount, 0)
        XCTAssertEqual(restored.activeEntry, active)
    }
}
