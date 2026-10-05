import Foundation

public struct ReportDay: Identifiable, Sendable {
    public var date: Date
    public var secondsByCategory: [String: TimeInterval]
    public var id: Date { date }
    public var seconds: TimeInterval { secondsByCategory.values.reduce(0, +) }
}

public struct ReportBucket: Identifiable, Sendable {
    public var date: Date
    public var categoryId: String
    public var seconds: TimeInterval
    public var id: String { "\(date.timeIntervalSince1970):\(categoryId)" }
}

public struct TimeReport: Sendable {
    public let interval: DateInterval
    public let days: [ReportDay]
    public let buckets: [ReportBucket]
    public let categorySeconds: [String: TimeInterval]
    public let sessionCount: Int
    public let overlapSeconds: TimeInterval
    public let granularity: Calendar.Component
    public var total: TimeInterval { categorySeconds.values.reduce(0, +) }
    public var activeDays: Int { days.filter { $0.seconds > 0 }.count }
    public var averageActiveDay: TimeInterval { activeDays == 0 ? 0 : total / Double(activeDays) }

    public init(entries: [TimeEntry], interval: DateInterval, categoryId: String? = nil, now: Date = Date(), calendar: Calendar = .current) {
        self.interval = interval
        var dayTotals: [Date: [String: TimeInterval]] = [:]
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            dayTotals[day] = [:]
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        var totals: [String: TimeInterval] = [:]
        var spans: [(Date, Date)] = []
        for entry in entries where !entry.deleted && (categoryId == nil || entry.categoryId == categoryId) {
            let start = max(Date(milliseconds: entry.startedAt), interval.start)
            let end = min(Date(milliseconds: entry.endedAt ?? now.milliseconds), interval.end, now)
            guard end > start else { continue }
            spans.append((start, end))
            totals[entry.categoryId, default: 0] += end.timeIntervalSince(start)
            // Calendar boundaries, rather than 86,400-second jumps, keep DST and overnight entries accurate.
            var cursor = start
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let segmentEnd = min(next, end)
                dayTotals[day, default: [:]][entry.categoryId, default: 0] += segmentEnd.timeIntervalSince(cursor)
                cursor = segmentEnd
            }
        }
        self.days = dayTotals.keys.sorted().map { ReportDay(date: $0, secondsByCategory: dayTotals[$0]!) }
        self.categorySeconds = totals
        self.sessionCount = spans.count
        self.granularity = days.count <= 62 ? .day : days.count <= 370 ? .weekOfYear : .month
        var grouped: [Date: [String: TimeInterval]] = [:]
        for day in days {
            let date = calendar.dateInterval(of: granularity, for: day.date)?.start ?? day.date
            // Include empty periods so gaps in a long history remain visible in the chart.
            if grouped[date] == nil { grouped[date] = [:] }
            for (id, seconds) in day.secondsByCategory { grouped[date, default: [:]][id, default: 0] += seconds }
        }
        self.buckets = grouped.keys.sorted().flatMap { date in
            let values = grouped[date]!
            return values.isEmpty ? [ReportBucket(date: date, categoryId: "", seconds: 0)] : values.keys.sorted().map {
                ReportBucket(date: date, categoryId: $0, seconds: values[$0]!)
            }
        }
        // Total tracked time includes overlapping sessions. Surface the excess without changing source records.
        var covered: TimeInterval = 0
        var current: (Date, Date)?
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let previous = current {
                if span.0 <= previous.1 { current = (previous.0, max(previous.1, span.1)) }
                else { covered += previous.1.timeIntervalSince(previous.0); current = span }
            } else { current = span }
        }
        if let current { covered += current.1.timeIntervalSince(current.0) }
        self.overlapSeconds = max(0, totals.values.reduce(0, +) - covered)
    }
}
