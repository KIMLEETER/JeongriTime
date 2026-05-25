import SwiftUI

enum ScheduleCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case free = "자유시간"
    case planned = "계획"
    case sleep = "수면"
    case movement = "이동"
    case classTime = "수업"
    case lab = "업무"
    case church = "개인 일정"
    case meal = "식사/점심"
    case chapel = "모임"
    case club = "활동"
    case language = "학습"
    case preparation = "준비"
    case other = "기타"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let category = ScheduleCategory(rawValue: rawValue) {
            self = category
            return
        }

        switch rawValue {
        case "\u{C5F0}\u{AD6C}\u{C18C}":
            self = .lab
        case "\u{AD50}\u{D68C}/\u{C608}\u{BC30}":
            self = .church
        case "\u{CC44}\u{D50C}":
            self = .chapel
        case "\u{B3D9}\u{C544}\u{B9AC}":
            self = .club
        case "\u{C5B8}\u{C5B4}":
            self = .language
        default:
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .free: "빈 시간"
        case .planned: "계획"
        case .sleep: "수면"
        case .movement: "이동"
        case .classTime: "수업"
        case .lab: "업무"
        case .church: "개인"
        case .meal: "식사"
        case .chapel: "모임"
        case .club: "활동"
        case .language: "학습"
        case .preparation: "준비"
        case .other: "기타"
        }
    }

    var symbolName: String {
        switch self {
        case .free: "sparkles"
        case .planned: "calendar.badge.checkmark"
        case .sleep: "moon.zzz"
        case .movement: "figure.walk"
        case .classTime: "book.closed"
        case .lab: "building.2"
        case .church: "hands.sparkles"
        case .meal: "fork.knife"
        case .chapel: "sun.max"
        case .club: "person.3"
        case .language: "textformat.characters"
        case .preparation: "checklist"
        case .other: "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .free: Color(red: 0.99, green: 0.99, blue: 0.97)
        case .planned: Color(red: 0.17, green: 0.47, blue: 0.52)
        case .sleep: Color(red: 0.39, green: 0.44, blue: 0.75)
        case .movement: Color(red: 0.70, green: 0.73, blue: 0.78)
        case .classTime: Color(red: 0.43, green: 0.62, blue: 0.88)
        case .lab: Color(red: 0.40, green: 0.70, blue: 0.49)
        case .church: Color(red: 0.91, green: 0.75, blue: 0.29)
        case .meal: Color(red: 0.91, green: 0.56, blue: 0.31)
        case .chapel: Color(red: 0.44, green: 0.72, blue: 0.86)
        case .club: Color(red: 0.62, green: 0.49, blue: 0.82)
        case .language: Color(red: 0.33, green: 0.70, blue: 0.65)
        case .preparation: Color(red: 0.52, green: 0.62, blue: 0.72)
        case .other: Color(red: 0.66, green: 0.66, blue: 0.66)
        }
    }

    var surface: Color {
        switch self {
        case .free:
            tint.opacity(0.35)
        case .planned:
            tint.opacity(0.14)
        case .sleep:
            tint.opacity(0.16)
        default:
            tint.opacity(0.18)
        }
    }

    static func infer(from title: String) -> ScheduleCategory {
        let text = title.lowercased()

        if containsAny(text, ["수면", "잠", "취침", "기상"]) {
            return .sleep
        }
        if containsAny(text, ["이동", "버스", "지하철", "자전거", "도보", "귀가", "출발", "정류장", "역"]) {
            return .movement
        }
        if containsAny(text, ["준비", "씻", "세면", "정리"]) {
            return .preparation
        }
        if containsAny(text, ["식사", "점심", "저녁", "아침", "밥", "카페"]) {
            return .meal
        }
        if containsAny(text, ["수업", "세미나", "강의"]) {
            return .classTime
        }
        if containsAny(text, ["업무", "작업", "프로젝트", "집중"]) {
            return .lab
        }
        if containsAny(text, ["개인 일정", "개인"]) {
            return .church
        }
        if containsAny(text, ["모임"]) {
            return .chapel
        }
        if containsAny(text, ["활동", "운동"]) {
            return .club
        }
        if containsAny(text, ["학습", "스터디", "언어", "영어"]) {
            return .language
        }
        return .other
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

enum SchedulePlace: String, CaseIterable, Identifiable, Hashable, Codable {
    case home = "집"
    case school = "학교"
    case lab = "업무 장소"
    case church = "개인 장소"
    case moving = "이동"
    case free = "빈 시간"
    case other = "기타"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let place = SchedulePlace(rawValue: rawValue) {
            self = place
            return
        }

        switch rawValue {
        case "\u{C5F0}\u{AD6C}\u{C18C}":
            self = .lab
        case "\u{AD50}\u{D68C}":
            self = .church
        default:
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .school: "graduationcap"
        case .lab: "building.2"
        case .church: "hands.sparkles"
        case .moving: "figure.walk"
        case .free: "sparkles"
        case .other: "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .home: Color(red: 0.50, green: 0.57, blue: 0.66)
        case .school: ScheduleCategory.classTime.tint
        case .lab: ScheduleCategory.lab.tint
        case .church: ScheduleCategory.church.tint
        case .moving: ScheduleCategory.movement.tint
        case .free: AppTheme.free
        case .other: ScheduleCategory.other.tint
        }
    }

    var surface: Color {
        tint.opacity(self == .free ? 0.12 : 0.14)
    }

    static func infer(from block: ScheduleBlock) -> SchedulePlace {
        if let place = block.place {
            return place
        }

        let title = block.title
        let category = block.displayCategory

        if block.isFree && category == .free {
            return .free
        }

        if category == .movement || containsAny(title, ["이동", "귀가", "출발", "정류장", "역", "자전거", "버스", "지하철", "도보"]) {
            return .moving
        }
        if containsAny(title, ["집", "기상", "취침", "수면", "씻기", "세면"]) {
            return .home
        }
        if containsAny(title, ["학교", "수업", "세미나"]) {
            return .school
        }
        if containsAny(title, ["업무", "작업", "프로젝트", "집중"]) {
            return .lab
        }
        if containsAny(title, ["개인 일정"]) {
            return .church
        }

        switch category {
        case .sleep, .preparation:
            return .home
        case .movement:
            return .moving
        case .classTime, .chapel, .club:
            return .school
        case .language:
            return title.contains("수업") ? .school : .other
        case .meal:
            return .school
        case .lab:
            return .lab
        case .church:
            return .church
        case .free:
            return .free
        case .planned, .other:
            return .other
        }
    }

    static func infer(title: String, category: ScheduleCategory) -> SchedulePlace {
        let block = ScheduleBlock(
            day: .monday,
            startMinute: 0,
            endMinute: 5,
            title: title,
            category: category
        )
        return infer(from: block)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
