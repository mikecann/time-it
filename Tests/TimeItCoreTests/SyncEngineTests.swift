import XCTest
@testable import TimeItCore

final class SyncEngineTests: XCTestCase {
    @MainActor func testOfflineRestartThenReconnectAndLostResponseRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let initial = try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
        try initial.start(at: Date(timeIntervalSince1970: 100))
        try initial.stop(at: Date(timeIntervalSince1970: 160))
        let store = try TimeStore(fileURL: initial.fileURL)
        var serverEntries: [String: TimeEntry] = [:]
        var serverCategories: [String: TimeItCore.Category] = [:]
        var lostResponse = true
        func server(_ request: SyncRequest) async throws -> SyncResponse {
            for category in request.categories { serverCategories[category.id] = category }
            for entry in request.entries { serverEntries[entry.id] = entry }
            if lostResponse { lostResponse = false; throw URLError(.networkConnectionLost) }
            return SyncResponse(acknowledgedCategories: request.categories, acknowledgedEntries: request.entries, categories: request.includeCategories ? Array(serverCategories.values) : [], entries: request.includeEntries ? Array(serverEntries.values) : [])
        }
        do { try await SyncEngine.run(store: store, send: server); XCTFail("Expected interrupted network") }
        catch { XCTAssertEqual(store.pendingCount, 2) }
        try await SyncEngine.run(store: store, send: server)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(serverEntries.count, 1)
        XCTAssertEqual(store.entries[0].duration(), 60)
        XCTAssertEqual(try TimeStore(fileURL: initial.fileURL).pendingCount, 0)
    }
    @MainActor func testStopDuringUploadIsUploadedAsNextRevision() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
        try store.start(at: Date(timeIntervalSince1970: 100))
        var uploaded: [TimeEntry] = []
        var first = true
        try await SyncEngine.run(store: store) { request in
            uploaded += request.entries
            if first { first = false; try store.stop(at: Date(timeIntervalSince1970: 180)) }
            return SyncResponse(acknowledgedCategories: request.categories, acknowledgedEntries: request.entries)
        }
        XCTAssertEqual(uploaded.map(\.revision), [1, 2])
        XCTAssertEqual(uploaded.last?.endedAt, 180000)
        XCTAssertEqual(store.pendingCount, 0)
    }
    @MainActor func testCategoriesOutsideBatchAreSentBeforeTheirEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
        try store.saveCategory(name: "Other")
        try store.start(categoryId: store.categories.first { $0.name == "Other" }!.id)
        let first = store.pendingBatch(limit: 1)
        XCTAssertEqual(first.categories[0].id, "convex")
        XCTAssertTrue(first.entries.isEmpty)
        try store.apply(SyncResponse(acknowledgedCategories: first.categories), sent: first)
        XCTAssertEqual(store.pendingBatch(limit: 1).entries.count, 1)
    }
    @MainActor func testUploadsDoNotDownloadWholeHistoryUnlessRequested() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
        var requests = 0
        try await SyncEngine.run(store: store, download: false) { request in
            requests += 1
            XCTAssertFalse(request.includeCategories)
            XCTAssertFalse(request.includeEntries)
            return SyncResponse(acknowledgedCategories: request.categories, acknowledgedEntries: request.entries)
        }
        XCTAssertEqual(requests, 1)
        try await SyncEngine.run(store: store, download: false) { _ in XCTFail("An idle app should not transfer history"); return SyncResponse() }
    }
    @MainActor func testIndependentPageCursorsAndStalledPageDetection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TimeStore(fileURL: folder.appendingPathComponent("state.json"))
        var page = 0
        try await SyncEngine.run(store: store) { request in
            if !request.categories.isEmpty { return SyncResponse(acknowledgedCategories: request.categories) }
            page += 1
            if page == 1 { return SyncResponse(entryCursor: "page-2", entriesDone: false) }
            XCTAssertFalse(request.includeCategories)
            XCTAssertEqual(request.entryCursor, "page-2")
            return SyncResponse()
        }
        XCTAssertEqual(page, 2)
        do {
            try await SyncEngine.run(store: store) { _ in SyncResponse(entriesDone: false) }
            XCTFail("A stalled cursor must not create an infinite retry loop")
        } catch { XCTAssertTrue(error is SyncError) }
    }
}
