import Foundation

struct CalendarInboxItem: Identifiable, Codable, Hashable {
    let id: String
    let calendarEventIdentifier: String
    let calendarTitle: String
    let title: String
    let startDate: Date
    let endDate: Date
    let importedAt: Date

    init(
        calendarEventIdentifier: String,
        calendarTitle: String,
        title: String,
        startDate: Date,
        endDate: Date,
        importedAt: Date = Date()
    ) {
        self.id = calendarEventIdentifier
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarTitle = calendarTitle
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.importedAt = importedAt
    }

    func day(calendar: Calendar = .autoupdatingCurrent) -> Weekday {
        Weekday.from(date: startDate, calendar: calendar)
    }

    func startMinute(calendar: Calendar = .autoupdatingCurrent) -> Int {
        TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: startDate, calendar: calendar))
    }

    func endMinute(calendar: Calendar = .autoupdatingCurrent) -> Int {
        if !calendar.isDate(startDate, inSameDayAs: endDate) {
            return 24 * 60
        }

        let rawEnd = TimeFormatter.minuteOfDay(from: endDate, calendar: calendar)
        let rounded = TimeFormatter.ceilToFive(rawEnd)
        return max(startMinute(calendar: calendar) + 5, rounded)
    }

    func intervalText(calendar: Calendar = .autoupdatingCurrent) -> String {
        "\(TimeFormatter.clock(startMinute(calendar: calendar)))-\(TimeFormatter.clock(endMinute(calendar: calendar)))"
    }
}
