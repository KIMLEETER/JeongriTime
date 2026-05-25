import Foundation

enum ScheduleData {
    static let fixedBlocks: [ScheduleBlock] = [
        block(.sunday, 9, 0, 10, 0, "주간 정리", .preparation),
        block(.sunday, 14, 0, 16, 0, "개인 프로젝트", .other),

        block(.monday, 8, 0, 8, 30, "아침 루틴", .preparation),
        block(.monday, 9, 0, 12, 0, "오전 업무", .lab),
        block(.monday, 12, 0, 13, 0, "점심", .meal),
        block(.monday, 14, 0, 17, 0, "오후 업무", .lab),

        block(.tuesday, 8, 0, 8, 30, "아침 루틴", .preparation),
        block(.tuesday, 9, 0, 12, 0, "오전 수업", .classTime),
        block(.tuesday, 12, 0, 13, 0, "점심", .meal),
        block(.tuesday, 14, 0, 16, 0, "스터디", .language),
        block(.tuesday, 16, 30, 17, 0, "이동", .movement),

        block(.wednesday, 8, 0, 8, 30, "아침 루틴", .preparation),
        block(.wednesday, 9, 0, 11, 0, "오전 업무", .lab),
        block(.wednesday, 13, 0, 15, 0, "집중 작업", .lab),
        block(.wednesday, 17, 0, 18, 0, "운동", .other),

        block(.thursday, 8, 0, 8, 30, "아침 루틴", .preparation),
        block(.thursday, 9, 0, 11, 0, "오전 수업", .classTime),
        block(.thursday, 13, 0, 15, 0, "언어 학습", .language),
        block(.thursday, 16, 0, 18, 0, "프로젝트 작업", .lab),

        block(.friday, 8, 0, 8, 30, "아침 루틴", .preparation),
        block(.friday, 9, 0, 11, 0, "오전 업무", .lab),
        block(.friday, 13, 15, 15, 30, "오후 수업", .classTime)
    ]

    static let missingItems: [MissingInfoItem] = [
        missing(.monday, "저녁 계획", "17:00 이후가 빈 시간", "저녁 이후 시간을 계획할지 결정", .medium),
        missing(.tuesday, "아침 식사", "아침 루틴에 식사 여부가 없음", "식사를 별도 블록으로 둘지 결정", .medium),
        missing(.wednesday, "운동 후 계획", "18:00 이후가 빈 시간", "휴식 또는 추가 계획을 둘지 결정", .low),
        missing(.thursday, "학습 복습", "언어 학습 이후 복습 시간이 없음", "복습 시간을 반복 계획으로 둘지 결정", .low),
        missing(.friday, "주말 준비", "15:30 이후가 빈 시간", "주말 준비 시간을 둘지 결정", .low),
        missing(.saturday, "하루 시작", "고정 일정 없음", "하루 시작 기준을 정할지 결정", .high)
    ]

    private static func block(
        _ day: Weekday,
        _ startHour: Int,
        _ startMinute: Int,
        _ endHour: Int,
        _ endMinute: Int,
        _ title: String,
        _ category: ScheduleCategory,
        _ note: String? = nil
    ) -> ScheduleBlock {
        ScheduleBlock(
            day: day,
            startMinute: TimeFormatter.minutes(startHour, startMinute),
            endMinute: TimeFormatter.minutes(endHour, endMinute),
            title: title,
            category: category,
            note: note
        )
    }

    private static func missing(
        _ day: Weekday,
        _ topic: String,
        _ currentState: String,
        _ decisionNeeded: String,
        _ priority: MissingPriority
    ) -> MissingInfoItem {
        MissingInfoItem(
            day: day,
            topic: topic,
            currentState: currentState,
            decisionNeeded: decisionNeeded,
            priority: priority
        )
    }
}
