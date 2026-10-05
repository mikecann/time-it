import Foundation

@MainActor public enum SyncEngine {
    public static func run(store: TimeStore, send: (SyncRequest) async throws -> SyncResponse) async throws {
        var batches = 0
        while store.pendingCount > 0 && batches < 100 {
            let sent = store.pendingBatch()
            let result = try await send(sent)
            try store.apply(result, sent: sent)
            batches += 1
            if result.acknowledgedEntries.isEmpty && result.acknowledgedCategories.isEmpty { throw SyncError.server(502) }
        }
        var categoryCursor: String?, entryCursor: String?
        var categoriesDone = false, entriesDone = false
        repeat {
            let sent = SyncRequest(categoryCursor: categoryCursor, entryCursor: entryCursor, includeCategories: !categoriesDone, includeEntries: !entriesDone)
            let result = try await send(sent)
            try store.apply(result, sent: sent)
            if (!result.categoriesDone && result.categoryCursor == categoryCursor) || (!result.entriesDone && result.entryCursor == entryCursor) { throw SyncError.server(502) }
            categoriesDone = categoriesDone || result.categoriesDone; entriesDone = entriesDone || result.entriesDone
            categoryCursor = result.categoryCursor; entryCursor = result.entryCursor
        } while !categoriesDone || !entriesDone
    }
}
