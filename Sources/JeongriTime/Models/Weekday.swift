import Foundation

enum Weekday: String, CaseIterable, Identifiable, Hashable, Codable {
    case sunday = "일"
    case monday = "월"
    case tuesday = "화"
    case wednesday = "수"
    case thursday = "목"
    case friday = "금"
    case saturday = "토"

    var id: String { rawValue }

    var longName: String {
        switch self {
        case .sunday: "일요일"
        case .monday: "월요일"
        case .tuesday: "화요일"
        case .wednesday: "수요일"
        case .thursday: "목요일"
        case .friday: "금요일"
        case .saturday: "토요일"
        }
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    var next: Weekday {
        switch self {
        case .sunday: .monday
        case .monday: .tuesday
        case .tuesday: .wednesday
        case .wednesday: .thursday
        case .thursday: .friday
        case .friday: .saturday
        case .saturday: .sunday
        }
    }

    static func from(date: Date, calendar: Calendar = .autoupdatingCurrent) -> Weekday {
        let value = calendar.component(.weekday, from: date)
        return Weekday.allCases.first { $0.calendarWeekday == value } ?? .monday
    }
}
