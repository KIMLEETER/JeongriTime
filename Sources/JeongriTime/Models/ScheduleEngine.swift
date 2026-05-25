import Foundation

struct ScheduleEngine {
    let fixedBlocks: [ScheduleBlock]
    let missingItems: [MissingInfoItem]

    init(
        fixedBlocks: [ScheduleBlock] = ScheduleData.fixedBlocks,
        missingItems: [MissingInfoItem] = ScheduleData.missingItems
    ) {
        self.fixedBlocks = fixedBlocks
        self.missingItems = missingItems
    }

    func blocks(for day: Weekday) -> [ScheduleBlock] {
        let fixed = fixedBlocks
            .filter { $0.day == day }
            .sorted { $0.startMinute < $1.startMinute }

        var result: [ScheduleBlock] = []
        var cursor = 0

        for block in fixed {
            if cursor < block.startMinute {
                result.append(freeBlock(day: day, start: cursor, end: block.startMinute))
            }
            result.append(block)
            cursor = max(cursor, block.endMinute)
        }

        if cursor < 24 * 60 {
            result.append(freeBlock(day: day, start: cursor, end: 24 * 60))
        }

        if result.isEmpty {
            return [freeBlock(day: day, start: 0, end: 24 * 60)]
        }
        return result
    }

    func currentBlock(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> ScheduleBlock {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return blocks(for: day).first { $0.contains(minute: minute) }
            ?? freeBlock(day: day, start: minute, end: min(minute + 5, 24 * 60))
    }

    func nextBlock(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> ScheduleBlock? {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return blocks(for: day).first { $0.startMinute > minute }
    }

    func remainingFreeMinutes(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return remainingFreeMinutes(day: day, fromMinute: minute)
    }

    func remainingFreeMinutes(day: Weekday, fromMinute minute: Int) -> Int {
        blocks(for: day)
            .filter(\.isFree)
            .reduce(0) { total, block in
                total + block.clippedDuration(from: minute)
            }
    }

    func freeMinutes(for day: Weekday) -> Int {
        blocks(for: day)
            .filter(\.isFree)
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func fixedMinutes(for day: Weekday) -> Int {
        24 * 60 - freeMinutes(for: day)
    }

    func categoryMinutes(for day: Weekday, matching categories: Set<ScheduleCategory>) -> Int {
        blocks(for: day)
            .filter { categories.contains($0.category) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func missingItems(for day: Weekday) -> [MissingInfoItem] {
        missingItems.filter { $0.day == day }
    }

    func unresolvedHighPriorityCount(resolvedIDs: Set<String>) -> Int {
        missingItems.filter { $0.priority == .high && !resolvedIDs.contains($0.id) }.count
    }

    private func freeBlock(day: Weekday, start: Int, end: Int) -> ScheduleBlock {
        ScheduleBlock(
            day: day,
            startMinute: start,
            endMinute: end,
            title: "빈 시간",
            category: .free
        )
    }
}
