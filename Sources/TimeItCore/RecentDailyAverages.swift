import Foundation

public struct RecentDailyAverages: Sendable {
    public let interval: DateInterval
    public let recordedDays: Int
    public let sixHourDays: Int
    public let averageRecordedDay: TimeInterval?
    public let averageSixHourDay: TimeInterval?

    public init(entries: [TimeEntry], categoryId: String? = nil, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        // Use complete local calendar days so today's timer and DST cannot skew the window.
        interval = DateInterval(start: calendar.date(byAdding: .day, value: -30, to: today)!, end: today)
        let report = TimeReport(entries: entries, interval: interval, categoryId: categoryId, now: now, calendar: calendar)
        let recorded = report.days.filter { $0.seconds > 0 }
        // Qualify whole daily totals after category filtering, not individual sessions.
        let sixHours = recorded.filter { $0.seconds >= 6 * 3600 }
        recordedDays = recorded.count
        sixHourDays = sixHours.count
        averageRecordedDay = recorded.isEmpty ? nil : recorded.reduce(0) { $0 + $1.seconds } / Double(recorded.count)
        averageSixHourDay = sixHours.isEmpty ? nil : sixHours.reduce(0) { $0 + $1.seconds } / Double(sixHours.count)
    }
}
