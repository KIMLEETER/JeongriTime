import Foundation

enum TimeFormatter {
    static func minutes(_ hour: Int, _ minute: Int = 0) -> Int {
        hour * 60 + minute
    }

    static func clock(_ minutes: Int) -> String {
        let clamped = max(0, min(minutes, 24 * 60))
        if clamped == 24 * 60 {
            return "24:00"
        }
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    static func duration(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hours = safe / 60
        let remainder = safe % 60

        if hours > 0 && remainder > 0 {
            return "\(hours)시간 \(remainder)분"
        }
        if hours > 0 {
            return "\(hours)시간"
        }
        return "\(remainder)분"
    }

    static func compactDuration(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }

    static func minuteOfDay(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    static func floorToFive(_ minute: Int) -> Int {
        max(0, min(23 * 60 + 55, minute - minute % 5))
    }

    static func ceilToFive(_ minute: Int) -> Int {
        let clamped = max(0, min(24 * 60, minute))
        guard clamped % 5 != 0 else {
            return clamped
        }
        return min(24 * 60, clamped + (5 - clamped % 5))
    }

    static func nextFiveMinuteBoundary(after minute: Int) -> Int? {
        let next = ((minute / 5) + 1) * 5
        return next < 24 * 60 ? next : nil
    }
}
