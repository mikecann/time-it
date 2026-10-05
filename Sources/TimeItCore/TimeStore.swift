import Foundation

public enum StoreError: LocalizedError {
    case alreadyRunning, noTimer, invalidCategory, invalidName, invalidRange, missingEntry, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "A timer is already running. Stop it first."
        case .noTimer: return "There is no running timer."
        case .invalidCategory: return "Choose an available category."
        case .invalidName: return "Give the category a unique name of up to 100 characters."
        case .invalidRange: return "The end must be after the start."
        case .missingEntry: return "This entry is no longer available."
        case .unsupportedVersion: return "This data was saved by a newer Time It. Update the app before opening it."
        }
    }
}

@MainActor public final class TimeStore {
    public private(set) var state: LocalState
    public let fileURL: URL
    private let write: (Data, URL) throws -> Void
    public var onChange: (() -> Void)?

    public init(fileURL: URL, write: @escaping (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }) throws {
        self.fileURL = fileURL; self.write = write
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // Never silently replace unreadable data with an empty store.
            state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: fileURL))
            guard state.version == 1 else { throw StoreError.unsupportedVersion }
        } else {
            state = LocalState()
            try write(JSONEncoder().encode(state), fileURL)
        }
    }

    public var activeEntry: TimeEntry? { state.entries.filter { !$0.deleted && $0.endedAt == nil }.sorted { $0.startedAt > $1.startedAt }.first }
    public var entries: [TimeEntry] { state.entries.filter { !$0.deleted }.sorted { $0.startedAt > $1.startedAt } }
    public var categories: [Category] { state.categories.filter { !$0.archived }.sorted { ($0.id == "convex" ? "" : $0.name.lowercased()) < ($1.id == "convex" ? "" : $1.name.lowercased()) } }
    public var pendingCount: Int { state.pendingEntries.count + state.pendingCategories.count }
    public func category(_ id: String) -> Category? { state.categories.first { $0.id == id } }

    private func commit(_ transform: (inout LocalState) throws -> Void) throws {
        var next = state
        try transform(&next)
        try write(JSONEncoder().encode(next), fileURL)
        // Publish only after durable storage succeeds. The UI must never claim a failed start worked.
        state = next
        onChange?()
    }

    public func start(categoryId: String = "convex", note: String = "", at date: Date = Date()) throws {
        guard activeEntry == nil else { throw StoreError.alreadyRunning }
        guard categories.contains(where: { $0.id == categoryId }) else { throw StoreError.invalidCategory }
        try commit { state in
            let entry = TimeEntry(categoryId: categoryId, note: String(note.prefix(2000)), startedAt: date.milliseconds, deviceId: state.deviceId, updatedAt: date.milliseconds)
            state.entries.append(entry); state.pendingEntries.insert(entry.id)
        }
    }
    public func stop(at date: Date = Date()) throws {
        guard let active = activeEntry else { throw StoreError.noTimer }
        try updateEntry(id: active.id, categoryId: active.categoryId, note: active.note, start: Date(milliseconds: active.startedAt), end: max(date, Date(milliseconds: active.startedAt)))
    }
    public func updateEntry(id: String, categoryId: String, note: String, start: Date, end: Date?) throws {
        guard categories.contains(where: { $0.id == categoryId }) || categoryId == state.entries.first(where: { $0.id == id })?.categoryId else { throw StoreError.invalidCategory }
        guard end == nil || end! >= start else { throw StoreError.invalidRange }
        try commit { state in
            guard let index = state.entries.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw StoreError.missingEntry }
            state.entries[index].categoryId = categoryId; state.entries[index].note = String(note.prefix(2000))
            state.entries[index].startedAt = start.milliseconds; state.entries[index].endedAt = end?.milliseconds
            state.entries[index].revision += 1; state.entries[index].deviceId = state.deviceId; state.entries[index].updatedAt = Date().milliseconds
            state.pendingEntries.insert(id)
        }
    }
    public func addManual(categoryId: String, note: String, start: Date, end: Date) throws {
        guard end >= start else { throw StoreError.invalidRange }
        guard categories.contains(where: { $0.id == categoryId }) else { throw StoreError.invalidCategory }
        try commit { state in
            let entry = TimeEntry(categoryId: categoryId, note: String(note.prefix(2000)), startedAt: start.milliseconds, endedAt: end.milliseconds, deviceId: state.deviceId)
            state.entries.append(entry); state.pendingEntries.insert(entry.id)
        }
    }
    public func deleteEntry(id: String) throws {
        try commit { state in
            guard let i = state.entries.firstIndex(where: { $0.id == id }) else { throw StoreError.missingEntry }
            state.entries[i].deleted = true; state.entries[i].revision += 1
            state.entries[i].deviceId = state.deviceId; state.entries[i].updatedAt = Date().milliseconds
            state.pendingEntries.insert(id)
        }
    }
    public func saveCategory(id: String? = nil, name: String, color: String = "#E8AE58", archived: Bool = false) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100, !state.categories.contains(where: { $0.id != id && !$0.archived && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { throw StoreError.invalidName }
        guard id != "convex" || (!archived && trimmed == "Convex") else { throw StoreError.invalidCategory }
        guard !archived || activeEntry?.categoryId != id else { throw StoreError.alreadyRunning }
        try commit { state in
            if let id, let i = state.categories.firstIndex(where: { $0.id == id }) {
                state.categories[i].name = trimmed; state.categories[i].color = color; state.categories[i].archived = archived
                state.categories[i].revision += 1; state.categories[i].deviceId = state.deviceId; state.categories[i].updatedAt = Date().milliseconds
                state.pendingCategories.insert(id)
            } else {
                let category = Category(name: trimmed, color: color, deviceId: state.deviceId)
                state.categories.append(category); state.pendingCategories.insert(category.id)
            }
        }
    }

    public func pendingBatch(limit: Int = 100) -> SyncRequest {
        let categories = Array(state.categories.filter { state.pendingCategories.contains($0.id) }.prefix(limit))
        let uploadedCategories = Set(categories.map(\.id))
        // A category outside this batch must reach the server before its entries.
        let entries = Array(state.entries.filter {
            state.pendingEntries.contains($0.id) && (!state.pendingCategories.contains($0.categoryId) || uploadedCategories.contains($0.categoryId))
        }.prefix(limit))
        return SyncRequest(categories: categories, entries: entries, includeCategories: false, includeEntries: false)
    }
    public func apply(_ response: SyncResponse, sent: SyncRequest) throws {
        try commit { state in
            for record in response.acknowledgedCategories {
                if let uploaded = sent.categories.first(where: { $0.id == record.id }), let local = state.categories.first(where: { $0.id == record.id }), uploaded == local {
                    state.pendingCategories.remove(record.id)
                }
            }
            for record in response.acknowledgedEntries {
                if let uploaded = sent.entries.first(where: { $0.id == record.id }), let local = state.entries.first(where: { $0.id == record.id }), uploaded == local {
                    state.pendingEntries.remove(record.id)
                }
            }
            for remote in response.acknowledgedCategories + response.categories {
                guard !state.pendingCategories.contains(remote.id) else { continue }
                if let i = state.categories.firstIndex(where: { $0.id == remote.id }) {
                    if Self.wins(remote.revision, remote.deviceId, over: state.categories[i].revision, state.categories[i].deviceId) { state.categories[i] = remote }
                } else { state.categories.append(remote) }
            }
            for remote in response.acknowledgedEntries + response.entries {
                guard !state.pendingEntries.contains(remote.id) else { continue }
                if let i = state.entries.firstIndex(where: { $0.id == remote.id }) {
                    if Self.wins(remote.revision, remote.deviceId, over: state.entries[i].revision, state.entries[i].deviceId) { state.entries[i] = remote }
                } else { state.entries.append(remote) }
            }
        }
    }
    static func wins(_ revision: Int, _ device: String, over otherRevision: Int, _ otherDevice: String) -> Bool {
        revision > otherRevision || (revision == otherRevision && device >= otherDevice)
    }
    public func total(in interval: DateInterval, categoryId: String? = nil, now: Date = Date()) -> TimeInterval {
        entries.filter { categoryId == nil || $0.categoryId == categoryId }.reduce(0) { $0 + $1.duration(in: interval, now: now) }
    }
    public func csv() -> String {
        func quote(_ text: String) -> String {
            // Spreadsheet software evaluates cells beginning with these characters as formulas.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { text.hasPrefix($0) }) ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        return (["ID,Category,Note,Start,End,Seconds"] + entries.map { entry in
            [entry.id, category(entry.categoryId)?.name ?? entry.categoryId, entry.note,
             formatter.string(from: Date(milliseconds: entry.startedAt)), entry.endedAt.map { formatter.string(from: Date(milliseconds: $0)) } ?? "", String(Int(entry.duration()))].map(quote).joined(separator: ",")
        }).joined(separator: "\r\n") + "\r\n"
    }
}
