import SwiftUI
import Charts
import TimeItCore

private enum ReportPeriod: String, CaseIterable {
    case week = "This week", month = "This month", quarter = "Last 3 months", year = "This year", all = "All time", custom = "Custom"
}

struct ReportsView: View {
    @ObservedObject var model: AppModel
    @State private var period = ReportPeriod.month
    @State private var category = "all"
    @State private var start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-30 * 86400)
    @State private var end = Date()
    @State private var report: TimeReport?
    @State private var recentAverages: RecentDailyAverages?
    @State private var selectedDate: Date?
    private var calendar: Calendar { var value = Calendar.current; value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4; return value }
    private var categories: [TimeItCore.Category] { model.store?.state.categories ?? [] }
    private var categoryNames: [String] { categories.map(\.name) + ["No time"] }
    private var categoryColors: [Color] { categories.map { Color(hex: $0.color) } + [.clear] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(); exportButton }
                VStack(alignment: .leading, spacing: 12) { filters; exportButton }
            }
            if period == .custom {
                HStack {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                    DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                }
            }
            if let report {
                Text("\(report.interval.start.formatted(date: .abbreviated, time: .omitted)) – \(report.interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)) · \(calendar.timeZone.identifier)")
                    .font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { metrics(report) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { metrics(report) }
                }
                if let recentAverages {
                    VStack(alignment: .leading, spacing: 10) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { dailyAverages(recentAverages) }
                            VStack(spacing: 12) { dailyAverages(recentAverages) }
                        }
                        Text("\(recentAverages.interval.start.formatted(date: .abbreviated, time: .omitted)) – \(recentAverages.interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)). Both averages use the category filter and exclude today and days with no recorded time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if report.total == 0 {
                    ContentUnavailableView("No time in this range", systemImage: "chart.bar", description: Text("Choose another date range or import your Clockify history from History."))
                } else {
                    trend(report)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            breakdown(report).frame(minWidth: 310)
                            weekdayProfile(report).frame(minWidth: 310)
                        }
                        VStack(spacing: 18) { breakdown(report); weekdayProfile(report) }
                    }
                    activity(report)
                    if report.overlapSeconds >= 1 {
                        Label("\(hours(report.overlapSeconds)) of overlapping time is included in these totals. You can review sessions in History.", systemImage: "rectangle.on.rectangle")
                            .font(.callout).foregroundStyle(.secondary).padding(16)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text("Reports use the history saved on this Mac and work offline. The running timer is included and updates each minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
        .onChange(of: period) { _, _ in refresh() }
        .onChange(of: category) { _, _ in refresh() }
        .onChange(of: start) { _, _ in if end < start { end = start }; refresh() }
        .onChange(of: end) { _, _ in refresh() }
        .onChange(of: model.store?.state) { _, _ in refresh() }
        .onChange(of: Int(model.now.timeIntervalSince1970 / 60)) { _, _ in refresh() }
        .environment(\.calendar, calendar)
    }

    private var filters: some View {
        HStack {
            Picker("Date range", selection: $period) { ForEach(ReportPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 220)
            Picker("Category", selection: $category) {
                Text("All categories").tag("all")
                ForEach(categories) { Text($0.name + ($0.archived ? " (archived)" : "")).tag($0.id) }
            }.frame(width: 250)
        }
    }
    private var exportButton: some View { Button("Export history", systemImage: "square.and.arrow.up") { model.exportCSV() } }

    private func refresh() {
        let today = calendar.startOfDay(for: model.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let from: Date
        var through = tomorrow
        switch period {
        case .week: from = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        case .month: from = calendar.dateInterval(of: .month, for: today)!.start
        case .quarter: from = calendar.date(byAdding: .month, value: -3, to: today)!
        case .year: from = calendar.dateInterval(of: .year, for: today)!.start
        case .all: from = calendar.startOfDay(for: model.entries.map { Date(milliseconds: $0.startedAt) }.min() ?? today)
        case .custom:
            from = calendar.startOfDay(for: start)
            through = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end)))!
        }
        report = TimeReport(entries: model.store?.state.entries ?? [], interval: DateInterval(start: from, end: max(through, from)), categoryId: category == "all" ? nil : category, now: model.now, calendar: calendar)
        recentAverages = RecentDailyAverages(entries: model.store?.state.entries ?? [], categoryId: category == "all" ? nil : category, now: model.now, calendar: calendar)
        selectedDate = nil
    }

    @ViewBuilder private func metrics(_ report: TimeReport) -> some View {
        metric("Tracked time", value: hours(report.total))
        metric("Days recorded", value: "\(report.activeDays)")
        metric("Sessions", value: report.sessionCount.formatted())
    }
    @ViewBuilder private func dailyAverages(_ averages: RecentDailyAverages) -> some View {
        metric("30-day daily average", value: averages.averageRecordedDay.map(hours) ?? "No data", detail: "\(averages.recordedDays) \(averages.recordedDays == 1 ? "recorded day" : "recorded days")")
        metric("30-day average · 6h+ days", value: averages.averageSixHourDay.map(hours) ?? "No data", detail: "\(averages.sixHourDays) \(averages.sixHourDays == 1 ? "day" : "days") with at least 6h recorded")
    }
    private func metric(_ title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func card<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
    private func trend(_ report: TimeReport) -> some View {
        card("Time over time", subtitle: report.granularity == .day ? "Daily hours, split by category" : report.granularity == .weekOfYear ? "Weekly hours, split by category" : "Monthly hours, split by category") {
            Chart(report.buckets) { bucket in
                BarMark(x: .value("Date", bucket.date, unit: report.granularity), y: .value("Hours", bucket.seconds / 3600))
                    .foregroundStyle(by: .value("Category", name(bucket.categoryId)))
                    .accessibilityLabel("\(bucket.date.formatted(date: .abbreviated, time: .omitted)), \(name(bucket.categoryId))")
                    .accessibilityValue(hours(bucket.seconds))
                if let selectedDate, calendar.isDate(bucket.date, equalTo: selectedDate, toGranularity: report.granularity) {
                    RuleMark(x: .value("Selected date", bucket.date)).foregroundStyle(.secondary.opacity(0.35))
                }
            }
            .chartForegroundStyleScale(domain: categoryNames, range: categoryColors)
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: report.granularity, count: max(1, Set(report.buckets.map(\.date)).count / 7))) {
                    AxisGridLine(); AxisTick()
                    AxisValueLabel(format: report.granularity == .month ? .dateTime.month(.abbreviated).year(.twoDigits) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 240)
            if let selectedDate {
                let selected = report.buckets.filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: report.granularity) }
                Text("\(selected.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "") · \(hours(selected.reduce(0) { $0 + $1.seconds }))")
                    .font(.callout).monospacedDigit()
            }
        }
    }
    private func breakdown(_ report: TimeReport) -> some View {
        let sorted = report.categorySeconds.keys.sorted { report.categorySeconds[$0]! > report.categorySeconds[$1]! }
        return card("Where the time went") {
            Chart(sorted, id: \.self) { id in
                SectorMark(angle: .value("Hours", report.categorySeconds[id]! / 3600), innerRadius: .ratio(0.68), angularInset: 2)
                    .foregroundStyle(by: .value("Category", name(id)))
                    .accessibilityLabel(name(id)).accessibilityValue(hours(report.categorySeconds[id]!))
            }.chartForegroundStyleScale(domain: categoryNames, range: categoryColors).chartLegend(.hidden).frame(height: 170)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let rect = geometry[frame]
                            Text(hours(report.total)).font(.title3.weight(.semibold)).position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            ForEach(sorted, id: \.self) { id in
                HStack {
                    Circle().fill(color(id)).frame(width: 9, height: 9)
                    Text(name(id)).lineLimit(1)
                    Spacer()
                    Text(hours(report.categorySeconds[id]!)).monospacedDigit()
                    Text((report.categorySeconds[id]! / report.total).formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }.font(.callout)
            }
        }
    }
    private func weekdayProfile(_ report: TimeReport) -> some View {
        let weekdays = [2, 3, 4, 5, 6, 7, 1]
        return card("Your weekly rhythm", subtitle: "Average hours per weekday, including days with no time") {
            Chart(weekdays, id: \.self) { weekday in
                let days = report.days.filter { calendar.component(.weekday, from: $0.date) == weekday && $0.date <= calendar.startOfDay(for: model.now) }
                let average = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.seconds } / Double(days.count)
                BarMark(x: .value("Day", calendar.shortWeekdaySymbols[weekday - 1]), y: .value("Hours", average / 3600))
                    .foregroundStyle(Color(hex: "#79B8B0")).cornerRadius(3)
                    .accessibilityValue(hours(average))
            }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 230)
            Text("\(report.activeDays) \(report.activeDays == 1 ? "day" : "days") with recorded time in this range.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private func activity(_ report: TimeReport) -> some View {
        let last = min(calendar.startOfDay(for: model.now), calendar.startOfDay(for: report.interval.end.addingTimeInterval(-1)))
        let first = max(calendar.startOfDay(for: report.interval.start), calendar.date(byAdding: .weekOfYear, value: -11, to: calendar.dateInterval(of: .weekOfYear, for: last)!.start)!)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        let totals = Dictionary(uniqueKeysWithValues: report.days.map { ($0.date, $0.seconds) })
        let maximum = max(1, report.days.filter { $0.date >= first && $0.date <= last }.map(\.seconds).max() ?? 1)
        return card("Daily activity", subtitle: "The last 12 weeks within your selected range. Hover over a day to see its time.") {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<7, id: \.self) { row in
                    GridRow {
                        Text(calendar.veryShortWeekdaySymbols[(row + 1) % 7]).font(.caption).foregroundStyle(.secondary).frame(width: 18)
                        ForEach(0..<12, id: \.self) { week in
                            let date = calendar.date(byAdding: .day, value: week * 7 + row, to: weekStart)!
                            let visible = date >= first && date <= last
                            let seconds = totals[date] ?? 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(visible ? (seconds == 0 ? Color.primary.opacity(0.06) : Color(hex: "#E8AE58").opacity(0.2 + 0.8 * seconds / maximum)) : .clear)
                                .frame(minWidth: 12, maxWidth: .infinity).frame(height: 20)
                                .help(visible ? "\(date.formatted(date: .abbreviated, time: .omitted)): \(durationText(seconds))" : "Outside this range")
                                .accessibilityLabel(visible ? "\(date.formatted(date: .abbreviated, time: .omitted)), \(hours(seconds))" : "Outside this range")
                        }
                    }
                }
            }
            HStack {
                Text(first.formatted(date: .abbreviated, time: .omitted)); Spacer()
                Text("Less")
                ForEach([0.1, 0.35, 0.65, 1.0], id: \.self) { opacity in RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#E8AE58").opacity(opacity)).frame(width: 12, height: 12) }
                Text("More"); Spacer(); Text(last.formatted(date: .abbreviated, time: .omitted))
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func name(_ id: String) -> String { id.isEmpty ? "No time" : categories.first { $0.id == id }?.name ?? "Unknown" }
    private func color(_ id: String) -> Color { Color(hex: categories.first { $0.id == id }?.color ?? "#E8AE58") }
    private func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
