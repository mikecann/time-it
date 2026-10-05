import Foundation

/// A portable export produced by scripts/export-clockify.py. Raw source metadata stays in its audit archive.
public struct ClockifyArchive: Codable, Sendable {
    public var version: Int
    public var source: String
    public var categories: [Category]
    public var entries: [TimeEntry]
    public var skippedRunning: Int
    public init(categories: [Category], entries: [TimeEntry], skippedRunning: Int = 0) {
        version = 1; source = "clockify"; self.categories = categories; self.entries = entries; self.skippedRunning = skippedRunning
    }
    public func validate() throws {
        guard version == 1, source == "clockify", skippedRunning >= 0,
              Set(categories.map(\.id)).count == categories.count,
              Set(entries.map(\.id)).count == entries.count else { throw ClockifyImportError.invalidArchive }
        let ids = Set(categories.map(\.id))
        for category in categories {
            guard category.id.hasPrefix("clockify:"), category.id.count <= 100,
                  !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.name.utf16.count <= 100,
                  category.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw ClockifyImportError.invalidArchive }
        }
        for entry in entries {
            guard entry.id.hasPrefix("clockify:"), entry.id.count <= 100, ids.contains(entry.categoryId),
                  !entry.deleted, entry.note.utf16.count <= 2000, entry.startedAt.isFinite, entry.startedAt >= 0,
                  let end = entry.endedAt, end.isFinite, end >= entry.startedAt, end <= 8640000000000000 else { throw ClockifyImportError.invalidArchive }
        }
    }
}

public enum ClockifyImportError: LocalizedError {
    case invalidArchive
    public var errorDescription: String? { "This Clockify archive is invalid. No history has been imported. Export it again with Time It’s Clockify exporter." }
}

public struct ClockifyImportResult: Sendable {
    public let added: Int
    public let existing: Int
    public let categoriesAdded: Int
    public let skippedRunning: Int
    public let backupURL: URL
}
