import Foundation

struct ScheduleBlock: Identifiable, Hashable {
    let id: String
    let day: Weekday
    let startMinute: Int
    let endMinute: Int
    let title: String
    let category: ScheduleCategory
    let tagCategory: ScheduleCategory?
    let place: SchedulePlace?
    let note: String?
    let isTemporaryOverride: Bool

    init(
        id: String? = nil,
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        category: ScheduleCategory,
        tagCategory: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        note: String? = nil,
        isTemporaryOverride: Bool = false
    ) {
        self.day = day
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.title = title
        self.category = category
        self.tagCategory = tagCategory
        self.place = place
        self.note = note
        self.isTemporaryOverride = isTemporaryOverride
        self.id = id ?? "\(day.rawValue)-\(startMinute)-\(endMinute)-\(title)"
    }

    var durationMinutes: Int {
        max(0, endMinute - startMinute)
    }

    var isFree: Bool {
        category != .planned && (category == .free || title.contains("자유시간") || title.contains("빈 시간"))
    }

    var isPlanned: Bool {
        category == .planned
    }

    var displayCategory: ScheduleCategory {
        tagCategory ?? category
    }

    var displayPlace: SchedulePlace {
        SchedulePlace.infer(from: self)
    }

    var intervalText: String {
        "\(TimeFormatter.clock(startMinute))-\(TimeFormatter.clock(endMinute))"
    }

    var durationText: String {
        TimeFormatter.duration(durationMinutes)
    }

    func contains(minute: Int) -> Bool {
        startMinute <= minute && minute < endMinute
    }

    func clippedDuration(from minute: Int) -> Int {
        max(0, endMinute - max(startMinute, minute))
    }
}

enum ScheduleEntryKind: String, CaseIterable, Codable, Identifiable {
    case once = "이번만"
    case weeklyPlan = "매주 반복"
    case timetable = "시간표에 고정"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: "이번만"
        case .weeklyPlan: "매주"
        case .timetable: "시간표에 고정"
        }
    }

    var saveLabel: String {
        switch self {
        case .once: "저장"
        case .weeklyPlan: "매주 저장"
        case .timetable: "시간표에 고정"
        }
    }

    var symbolName: String {
        switch self {
        case .once: "checkmark"
        case .weeklyPlan: "repeat"
        case .timetable: "calendar.badge.plus"
        }
    }
}

struct PlannedBlock: Identifiable, Codable, Hashable {
    let id: String
    let day: Weekday
    let date: Date?
    let startMinute: Int
    let endMinute: Int
    let title: String
    let kind: ScheduleEntryKind
    let category: ScheduleCategory
    let place: SchedulePlace?
    let sourceBlockID: String?
    let calendarEventIdentifier: String?
    let isTodayCancellation: Bool

    init(
        id: String = UUID().uuidString,
        day: Weekday,
        date: Date? = nil,
        startMinute: Int,
        endMinute: Int,
        title: String,
        kind: ScheduleEntryKind = .once,
        category: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        sourceBlockID: String? = nil,
        calendarEventIdentifier: String? = nil,
        isTodayCancellation: Bool = false
    ) {
        self.id = id
        self.day = day
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.title = title
        self.kind = kind
        self.category = category ?? ScheduleCategory.infer(from: title)
        self.place = place
        self.sourceBlockID = sourceBlockID
        self.calendarEventIdentifier = calendarEventIdentifier
        self.isTodayCancellation = isTodayCancellation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        day = try container.decode(Weekday.self, forKey: .day)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(ScheduleEntryKind.self, forKey: .kind) ?? .weeklyPlan
        category = try container.decodeIfPresent(ScheduleCategory.self, forKey: .category) ?? ScheduleCategory.infer(from: title)
        place = try container.decodeIfPresent(SchedulePlace.self, forKey: .place)
        sourceBlockID = try container.decodeIfPresent(String.self, forKey: .sourceBlockID)
        calendarEventIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        isTodayCancellation = try container.decodeIfPresent(Bool.self, forKey: .isTodayCancellation) ?? false
    }

    var durationMinutes: Int {
        max(0, endMinute - startMinute)
    }

    var isPlan: Bool {
        !isTodayCancellation && (kind == .once || kind == .weeklyPlan)
    }

    var isTimetableEntry: Bool {
        kind == .timetable
    }

    var kindText: String {
        kind.displayName
    }
}

enum SchedulePlanner {
    static func merge(baseBlocks: [ScheduleBlock], plannedBlocks: [PlannedBlock]) -> [ScheduleBlock] {
        let plansByDay = Dictionary(grouping: plannedBlocks.filter { !$0.isTodayCancellation }) { $0.day }

        return baseBlocks
            .sorted { $0.startMinute < $1.startMinute }
            .flatMap { block -> [ScheduleBlock] in
                guard block.isFree, let plans = plansByDay[block.day] else {
                    return [block]
                }
                return split(block: block, with: plans)
            }
    }

    static func canPlan(
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        baseBlocks: [ScheduleBlock],
        plannedBlocks: [PlannedBlock]
    ) -> Bool {
        guard startMinute >= 0,
              endMinute <= 24 * 60,
              startMinute < endMinute,
              startMinute % 5 == 0,
              endMinute % 5 == 0
        else {
            return false
        }

        let fitsFreeBlock = baseBlocks.contains { block in
            block.day == day &&
            block.isFree &&
            block.startMinute <= startMinute &&
            endMinute <= block.endMinute
        }

        guard fitsFreeBlock else {
            return false
        }

        return !plannedBlocks.contains { plan in
            guard !plan.isTodayCancellation else {
                return false
            }
            return plan.day == day &&
            plan.startMinute < endMinute &&
            startMinute < plan.endMinute
        }
    }

    private static func split(block: ScheduleBlock, with plans: [PlannedBlock]) -> [ScheduleBlock] {
        var result: [ScheduleBlock] = []
        var cursor = block.startMinute
        let overlappingPlans = plans
            .filter { $0.startMinute < block.endMinute && block.startMinute < $0.endMinute }
            .sorted { $0.startMinute < $1.startMinute }

        for plan in overlappingPlans {
            let start = max(plan.startMinute, block.startMinute)
            let end = min(plan.endMinute, block.endMinute)
            guard cursor < end else {
                continue
            }

            if cursor < start {
                result.append(segment(from: block, start: cursor, end: start))
            }

            result.append(planBlock(from: plan, day: block.day, start: start, end: end))
            cursor = max(cursor, end)
        }

        if cursor < block.endMinute {
            result.append(segment(from: block, start: cursor, end: block.endMinute))
        }

        return result
    }

    private static func planBlock(from plan: PlannedBlock, day: Weekday, start: Int, end: Int) -> ScheduleBlock {
        let isTodayOverride = plan.kind == .once && plan.sourceBlockID != nil && !plan.isTodayCancellation

        return ScheduleBlock(
            id: plan.id,
            day: day,
            startMinute: start,
            endMinute: end,
            title: plan.title,
            category: isTodayOverride ? plan.category : .planned,
            tagCategory: isTodayOverride ? nil : plan.category,
            place: plan.place,
            note: isTodayOverride ? "오늘만 조정됨" : "계획한 빈 시간",
            isTemporaryOverride: isTodayOverride
        )
    }

    private static func segment(from block: ScheduleBlock, start: Int, end: Int) -> ScheduleBlock {
        ScheduleBlock(
            id: "\(block.id)-\(start)-\(end)",
            day: block.day,
            startMinute: start,
            endMinute: end,
            title: block.title,
            category: block.category,
            tagCategory: block.tagCategory,
            place: block.place,
            note: block.note,
            isTemporaryOverride: block.isTemporaryOverride
        )
    }
}
