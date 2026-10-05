import XCTest
@testable import TimeItCore

final class TimeStoreTests: XCTestCase {
    @MainActor private func makeStore() throws -> TimeStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try TimeStore(fileURL: directory.appendingPathComponent("state.json"))
    }
    func testOfflineTimerSurvivesRestartAndStop() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try store.start(at: Date(timeIntervalSince1970: 100))
            let restored = try TimeStore(fileURL: store.fileURL)
            XCTAssertEqual(restored.activeEntry?.categoryId, "convex")
            XCTAssertThrowsError(try restored.start())
            try restored.stop(at: Date(timeIntervalSince1970: 160))
            XCTAssertNil(restored.activeEntry)
            XCTAssertEqual(restored.entries.first?.duration(), 60)
            XCTAssertEqual(restored.pendingBatch().entries.first?.revision, 2)
        }
    }
    func testFailedWriteDoesNotPublishTimer() async throws {
        try await MainActor.run {
            let initial = try makeStore()
            let store = try TimeStore(fileURL: initial.fileURL, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            XCTAssertThrowsError(try store.start())
            XCTAssertNil(store.activeEntry)
            XCTAssertEqual(try TimeStore(fileURL: initial.fileURL).entries.count, 0)
        }
    }
    func testAcknowledgementDoesNotLoseAnEditMadeDuringSync() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try store.start(at: Date(timeIntervalSince1970: 100))
            let upload = store.pendingBatch()
            try store.stop(at: Date(timeIntervalSince1970: 160))
            try store.apply(SyncResponse(acknowledgedCategories: upload.categories, acknowledgedEntries: upload.entries), sent: upload)
            XCTAssertEqual(store.pendingCount, 1)
            XCTAssertEqual(store.entries.first?.endedAt, 160000)
            let second = store.pendingBatch()
            try store.apply(SyncResponse(acknowledgedEntries: second.entries), sent: second)
            XCTAssertEqual(store.pendingCount, 0)
        }
    }
    func testRetryAndTombstoneDoNotDuplicateOrResurrectEntry() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try store.start(); try store.stop()
            let upload = store.pendingBatch()
            let response = SyncResponse(acknowledgedCategories: upload.categories, acknowledgedEntries: upload.entries)
            try store.apply(response, sent: upload); try store.apply(response, sent: upload)
            XCTAssertEqual(store.entries.count, 1)
            let id = store.entries[0].id
            try store.deleteEntry(id: id)
            try store.apply(SyncResponse(entries: upload.entries), sent: SyncRequest())
            XCTAssertEqual(store.entries.count, 0)
            XCTAssertTrue(store.pendingBatch().entries.first!.deleted)
        }
    }
    func testUnreadableStoreIsPreserved() async throws {
        try await MainActor.run {
            let store = try makeStore()
            let broken = Data("invalid json".utf8)
            try broken.write(to: store.fileURL)
            XCTAssertThrowsError(try TimeStore(fileURL: store.fileURL))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), broken)
        }
    }
    func testDefaultCategoryAndArchivedHistory() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try store.saveCategory(name: "Personal")
            let personal = store.categories.first { $0.name == "Personal" }!
            try store.start(categoryId: personal.id); try store.stop()
            try store.saveCategory(id: personal.id, name: personal.name, archived: true)
            XCTAssertEqual(store.categories.count, 1)
            XCTAssertEqual(store.category(personal.id)?.name, "Personal")
            try store.start()
            XCTAssertEqual(store.activeEntry?.categoryId, "convex")
            XCTAssertThrowsError(try store.saveCategory(id: "convex", name: "Convex", archived: true))
        }
    }
    func testMidnightTotalsAndCSVFormulaEscaping() async throws {
        try await MainActor.run {
            let store = try makeStore()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
            let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
            let end = start.addingTimeInterval(3600)
            try store.addManual(categoryId: "convex", note: "=SUM(1,2)\n\"test\"", start: start, end: end)
            XCTAssertEqual(store.total(in: calendar.dateInterval(of: .day, for: end)!), 1800)
            XCTAssertTrue(store.csv().contains("'=SUM(1,2)"))
            XCTAssertThrowsError(try store.addManual(categoryId: "convex", note: "", start: end, end: start))
        }
    }
    func testRemoteHigherRevisionWinsButPendingWorkIsKept() async throws {
        try await MainActor.run {
            let store = try makeStore()
            try store.start(); try store.stop()
            let sent = store.pendingBatch()
            var remote = sent.entries[0]
            remote.revision += 1; remote.note = "Other device"; remote.deviceId = "other"
            try store.apply(SyncResponse(entries: [remote]), sent: SyncRequest())
            XCTAssertEqual(store.entries[0].note, "")
            try store.apply(SyncResponse(acknowledgedEntries: [remote]), sent: sent)
            XCTAssertEqual(store.entries[0].note, "Other device")
            XCTAssertTrue(store.pendingBatch().entries.isEmpty)
        }
    }
    func testSyncOnlyAcceptsConvexHTTPSWithoutRedirectCredentials() throws {
        XCTAssertThrowsError(try SyncClient(baseURL: "http://example.convex.site", token: "key"))
        XCTAssertThrowsError(try SyncClient(baseURL: "https://example.com", token: "key"))
        XCTAssertThrowsError(try SyncClient(baseURL: "https://user:password@a.convex.site", token: "key"))
        XCTAssertThrowsError(try SyncClient(baseURL: "https://a.convex.site/path", token: "key"))
        XCTAssertNoThrow(try SyncClient(baseURL: "https://a.convex.site", token: "key"))
    }
}
