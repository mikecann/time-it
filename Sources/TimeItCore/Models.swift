import Foundation

public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var clientId: String
    public var name: String
    public var color: String
    public var archived: Bool
    public var revision: Int
    public var deviceId: String
    public var updatedAt: Double
    public var id: String { clientId }
    public init(clientId: String = UUID().uuidString.lowercased(), name: String, color: String = "#E8AE58", archived: Bool = false, revision: Int = 1, deviceId: String, updatedAt: Double = Date().milliseconds) {
        self.clientId = clientId; self.name = name; self.color = color; self.archived = archived
        self.revision = revision; self.deviceId = deviceId; self.updatedAt = updatedAt
    }
}

public struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    public var clientId: String
    public var categoryId: String
    public var note: String
    public var startedAt: Double
    public var endedAt: Double?
    public var deleted: Bool
    public var revision: Int
    public var deviceId: String
    public var updatedAt: Double
    public var id: String { clientId }
    public init(clientId: String = UUID().uuidString.lowercased(), categoryId: String, note: String = "", startedAt: Double, endedAt: Double? = nil, deleted: Bool = false, revision: Int = 1, deviceId: String, updatedAt: Double = Date().milliseconds) {
        self.clientId = clientId; self.categoryId = categoryId; self.note = note
        self.startedAt = startedAt; self.endedAt = endedAt; self.deleted = deleted
        self.revision = revision; self.deviceId = deviceId; self.updatedAt = updatedAt
    }
    public func duration(at date: Date = Date()) -> TimeInterval {
        max(0, ((endedAt ?? date.milliseconds) - startedAt) / 1000)
    }
    // Split overnight sessions at local day boundaries, including daylight saving changes.
    public func duration(in interval: DateInterval, now: Date = Date()) -> TimeInterval {
        max(0, min(endedAt ?? now.milliseconds, interval.end.milliseconds) - max(startedAt, interval.start.milliseconds)) / 1000
    }
}

public struct LocalState: Codable, Equatable, Sendable {
    public var version = 1
    public var deviceId: String
    public var categories: [Category]
    public var entries: [TimeEntry]
    public var pendingCategories: Set<String>
    public var pendingEntries: Set<String>
    public init(deviceId: String = UUID().uuidString.lowercased()) {
        self.deviceId = deviceId
        categories = [Category(clientId: "convex", name: "Convex", color: "#E8AE58", deviceId: deviceId)]
        entries = []; pendingCategories = ["convex"]; pendingEntries = []
    }
}

public struct SyncRequest: Codable, Sendable {
    public var categories: [Category]
    public var entries: [TimeEntry]
    public var categoryCursor: String?
    public var entryCursor: String?
    public var includeCategories: Bool
    public var includeEntries: Bool
    public init(categories: [Category] = [], entries: [TimeEntry] = [], categoryCursor: String? = nil, entryCursor: String? = nil, includeCategories: Bool = true, includeEntries: Bool = true) {
        self.categories = categories; self.entries = entries
        self.categoryCursor = categoryCursor; self.entryCursor = entryCursor
        self.includeCategories = includeCategories; self.includeEntries = includeEntries
    }
}

public struct SyncResponse: Codable, Sendable {
    // These are the server's winning records for every uploaded ID, including stale retries.
    public var acknowledgedCategories: [Category]
    public var acknowledgedEntries: [TimeEntry]
    public var categories: [Category]
    public var entries: [TimeEntry]
    public var categoryCursor: String?
    public var entryCursor: String?
    public var categoriesDone: Bool
    public var entriesDone: Bool
    public init(acknowledgedCategories: [Category] = [], acknowledgedEntries: [TimeEntry] = [], categories: [Category] = [], entries: [TimeEntry] = [], categoryCursor: String? = nil, entryCursor: String? = nil, categoriesDone: Bool = true, entriesDone: Bool = true) {
        self.acknowledgedCategories = acknowledgedCategories; self.acknowledgedEntries = acknowledgedEntries
        self.categories = categories; self.entries = entries
        self.categoryCursor = categoryCursor; self.entryCursor = entryCursor
        self.categoriesDone = categoriesDone; self.entriesDone = entriesDone
    }
}

public extension Date {
    var milliseconds: Double { (timeIntervalSince1970 * 1000).rounded() }
    init(milliseconds: Double) { self.init(timeIntervalSince1970: milliseconds / 1000) }
}

public func durationText(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}

/// Reads a typed duration the way Clockify does: "3:00", "2:30:15", "1.5" (hours), "1h 30m", "45m" or "90s".
public func parseDuration(_ text: String) -> TimeInterval? {
    let value = text.trimmingCharacters(in: .whitespaces).lowercased()
    if value.isEmpty { return nil }
    if value.contains(":") {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let numbers = parts.map { $0! }
        guard numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return TimeInterval(numbers[0] * 3600 + numbers[1] * 60 + (numbers.count == 3 ? numbers[2] : 0))
    }
    if let hours = Double(value) { return hours >= 0 ? hours * 3600 : nil }
    let units: [Character: Double] = ["h": 3600, "m": 60, "s": 1]
    var total = 0.0, number = ""
    for character in value where character != " " {
        if character.isNumber || character == "." { number.append(character); continue }
        guard let unit = units[character], let amount = Double(number) else { return nil }
        total += amount * unit; number = ""
    }
    return number.isEmpty ? total : nil
}
