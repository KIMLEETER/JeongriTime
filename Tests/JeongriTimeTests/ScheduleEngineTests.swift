import XCTest
@testable import JeongriTime

final class ScheduleEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: ScheduleEngine!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        self.calendar = calendar
        self.engine = ScheduleEngine()
    }

    func testTuesdayCurrentBlockAtClassStart() throws {
        let date = try makeDate(year: 2026, month: 5, day: 19, hour: 9, minute: 0)
        let block = engine.currentBlock(at: date, calendar: calendar)

        XCTAssertEqual(block.day, .tuesday)
        XCTAssertEqual(block.title, "오전 수업")
        XCTAssertEqual(block.startMinute, TimeFormatter.minutes(9, 0))
        XCTAssertEqual(block.endMinute, TimeFormatter.minutes(12, 0))
    }

    func testTuesdayRemainingFreeMinutesFromMidnight() throws {
        let date = try makeDate(year: 2026, month: 5, day: 19, hour: 0, minute: 0)
        let remaining = engine.remainingFreeMinutes(from: date, calendar: calendar)

        XCTAssertEqual(remaining, 17 * 60)
    }

    func testMondayFreeMinutesReflectSampleWorkday() {
        XCTAssertEqual(engine.freeMinutes(for: .monday), 16 * 60 + 30)
        XCTAssertEqual(engine.fixedMinutes(for: .monday), 7 * 60 + 30)
    }

    func testSaturdayIsAllFreeUntilMissingInfoIsResolved() {
        let blocks = engine.blocks(for: .saturday)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].title, "빈 시간")
        XCTAssertEqual(blocks[0].durationMinutes, 24 * 60)
    }

    func testHighPriorityMissingInformationIncludesSaturdayStart() {
        let topics = engine.missingItems(for: .saturday)
            .filter { $0.priority == .high }
            .map(\.topic)

        XCTAssertTrue(topics.contains("하루 시작"))
    }

    func testPlannedBlockSplitsFreeTime() {
        let baseBlocks = engine.blocks(for: .monday)
        let plan = PlannedBlock(
            id: "plan-1",
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "자료 읽기"
        )

        let merged = SchedulePlanner.merge(baseBlocks: baseBlocks, plannedBlocks: [plan])

        XCTAssertTrue(merged.contains { $0.id == "plan-1" && $0.category == .planned })
        XCTAssertTrue(merged.contains { $0.isFree && $0.startMinute == TimeFormatter.minutes(17, 0) && $0.endMinute == TimeFormatter.minutes(18, 0) })
        XCTAssertTrue(merged.contains { $0.isFree && $0.startMinute == TimeFormatter.minutes(19, 0) && $0.endMinute == 24 * 60 })
    }

    func testPlannerRejectsFixedTimeOverlap() {
        let canPlan = SchedulePlanner.canPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(12, 30),
            endMinute: TimeFormatter.minutes(13, 0),
            baseBlocks: engine.blocks(for: .monday),
            plannedBlocks: []
        )

        XCTAssertFalse(canPlan)
    }

    @MainActor
    func testOncePlanDoesNotRepeatNextWeek() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "이번 주 과제",
            kind: .once
        ))
        XCTAssertEqual(store.plannedMinutes(for: .monday), 60)

        store.updateNow(try makeDate(year: 2026, month: 5, day: 25, hour: 9, minute: 0))
        XCTAssertEqual(store.plannedMinutes(for: .monday), 0)
    }

    @MainActor
    func testTimetableEntryConsumesFreeTimeWithoutBecomingPlan() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "정기 운동",
            kind: .timetable
        ))

        XCTAssertEqual(store.plannedMinutes(for: .monday), 0)
        XCTAssertTrue(store.timetableBlocks(for: .monday).contains { $0.title == "정기 운동" })
        XCTAssertEqual(store.freeMinutes(for: .monday), 15 * 60 + 30)
    }

    @MainActor
    func testUpdateNowDoesNotMoveSelectedDay() throws {
        let store = ScheduleStore(now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0))
        store.selectedDay = .thursday

        store.updateNow(try makeDate(year: 2026, month: 5, day: 19, hour: 9, minute: 0))

        XCTAssertEqual(store.selectedDay, .thursday)
    }

    @MainActor
    func testDefaultTimetableCanBeOverriddenByCopy() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let original = try XCTUnwrap(store.timetableBlocks(for: .monday).first { $0.title == "오후 업무" })

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(13, 0),
            endMinute: TimeFormatter.minutes(17, 0),
            title: "오후 업무 수정",
            kind: .timetable,
            category: .lab,
            sourceBlockID: original.id
        ))

        let titles = store.timetableBlocks(for: .monday).map(\.title)
        XCTAssertFalse(titles.contains("오후 업무"))
        XCTAssertTrue(titles.contains("오후 업무 수정"))
    }

    @MainActor
    func testTodayOverrideReplacesFixedBlockOnlyForCurrentWeek() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let original = try XCTUnwrap(store.timetableBlocks(for: .monday).first { $0.title == "오후 업무" })

        XCTAssertTrue(store.saveTodayOverride(
            sourceBlockID: original.id,
            day: .monday,
            startMinute: TimeFormatter.minutes(14, 0),
            endMinute: TimeFormatter.minutes(15, 0),
            title: "오늘만 업무",
            category: .lab
        ))

        let todayBlocks = store.blocks(for: .monday)
        XCTAssertFalse(todayBlocks.contains { $0.id == original.id })
        XCTAssertTrue(todayBlocks.contains {
            $0.title == "오늘만 업무" &&
            $0.category == .lab &&
            $0.isTemporaryOverride &&
            $0.note == "오늘만 조정됨"
        })
        XCTAssertTrue(store.timetableBlocks(for: .monday).contains { $0.id == original.id })
        XCTAssertEqual(store.plannedMinutes(for: .monday), 0)

        store.updateNow(try makeDate(year: 2026, month: 5, day: 25, hour: 9, minute: 0))

        XCTAssertTrue(store.blocks(for: .monday).contains { $0.id == original.id })
        XCTAssertFalse(store.blocks(for: .monday).contains { $0.title == "오늘만 업무" })
    }

    @MainActor
    func testTodayOverrideFreesOriginalTimeForPlanning() throws {
        let fixed = ScheduleBlock(
            id: "external-trip",
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "외부 이동",
            category: .movement
        )
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [fixed], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 20, hour: 17, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.saveTodayOverride(
            sourceBlockID: fixed.id,
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 50),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "차량 이동",
            category: .movement
        ))
        XCTAssertTrue(store.addPlan(
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(18, 30),
            title: "출발 전 정리",
            kind: .once,
            category: .preparation
        ))

        XCTAssertTrue(store.blocks(for: .wednesday).contains {
            $0.title == "출발 전 정리" &&
            $0.category == .planned
        })
    }

    @MainActor
    func testTodayCancellationFreesFixedTimeForPlanning() throws {
        let fixed = ScheduleBlock(
            id: "holiday-class",
            day: .wednesday,
            startMinute: TimeFormatter.minutes(13, 0),
            endMinute: TimeFormatter.minutes(15, 0),
            title: "휴일 수업",
            category: .classTime
        )
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [fixed], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 20, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.hideTimetableBlockForToday(sourceBlockID: fixed.id, day: .wednesday))
        XCTAssertFalse(store.blocks(for: .wednesday).contains { $0.id == fixed.id })
        XCTAssertEqual(store.todayCancellations(for: .wednesday).map(\.sourceBlockID), [fixed.id])
        XCTAssertEqual(store.plannedMinutes(for: .wednesday), 0)

        XCTAssertTrue(store.addPlan(
            day: .wednesday,
            startMinute: TimeFormatter.minutes(13, 30),
            endMinute: TimeFormatter.minutes(14, 30),
            title: "휴일 과제",
            kind: .once,
            category: .planned
        ))
        XCTAssertTrue(store.blocks(for: .wednesday).contains {
            $0.title == "휴일 과제" &&
            $0.category == .planned
        })
    }

    @MainActor
    func testTodayCancellationRestoresAndDoesNotRepeatNextWeek() throws {
        let fixed = ScheduleBlock(
            id: "one-day-work",
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "정기 업무",
            category: .lab
        )
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [fixed], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 20, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.hideTimetableBlockForToday(sourceBlockID: fixed.id, day: .wednesday))
        let cancellation = try XCTUnwrap(store.todayCancellations(for: .wednesday).first)

        store.restoreTodayCancellation(id: cancellation.id)
        XCTAssertTrue(store.blocks(for: .wednesday).contains { $0.id == fixed.id })
        XCTAssertTrue(store.todayCancellations(for: .wednesday).isEmpty)

        XCTAssertTrue(store.hideTimetableBlockForToday(sourceBlockID: fixed.id, day: .wednesday))
        XCTAssertFalse(store.blocks(for: .wednesday).contains { $0.id == fixed.id })

        store.updateNow(try makeDate(year: 2026, month: 5, day: 27, hour: 9, minute: 0))

        XCTAssertTrue(store.blocks(for: .wednesday).contains { $0.id == fixed.id })
        XCTAssertTrue(store.todayCancellations(for: .wednesday).isEmpty)
    }

    @MainActor
    func testWholeDayCancellationHandlesCustomTimetableEntries() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(10, 0),
            endMinute: TimeFormatter.minutes(11, 0),
            title: "정기 운동",
            kind: .timetable,
            category: .other
        ))
        let timetableCount = store.timetableBlocks(for: .monday).count

        XCTAssertEqual(store.hideAllTimetableBlocksForToday(day: .monday), timetableCount)
        XCTAssertTrue(store.blocks(for: .monday).allSatisfy(\.isFree))
        XCTAssertEqual(store.todayCancellations(for: .monday).count, timetableCount)
        XCTAssertEqual(store.restoreAllTodayCancellations(day: .monday), timetableCount)
        XCTAssertTrue(store.blocks(for: .monday).contains { $0.title == "정기 운동" })
    }

    @MainActor
    func testCalendarInboxItemCanBecomeTodayOverride() throws {
        let fixed = ScheduleBlock(
            id: "wednesday-trip",
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "외부 이동",
            category: .movement
        )
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [fixed], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 20, hour: 17, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-today-override",
            title: "차량 이동",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 20, hour: 18, minute: 50),
            endDate: try makeDate(year: 2026, month: 5, day: 20, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertFalse(store.canAcceptCalendarInboxItem(id: "calendar-today-override", calendar: calendar))
        XCTAssertEqual(store.calendarInboxTodayOverrideSource(id: "calendar-today-override", calendar: calendar)?.id, fixed.id)
        XCTAssertTrue(store.acceptCalendarInboxItemAsTodayOverride(
            id: "calendar-today-override",
            category: .movement,
            calendar: calendar
        ))

        XCTAssertTrue(store.calendarInboxItems.isEmpty)
        XCTAssertTrue(store.entries(for: .wednesday, kind: .once).contains {
            $0.title == "차량 이동" &&
            $0.sourceBlockID == fixed.id &&
            $0.calendarEventIdentifier == "calendar-today-override"
        })
        XCTAssertFalse(store.blocks(for: .wednesday).contains { $0.id == fixed.id })
        XCTAssertTrue(store.blocks(for: .wednesday).contains {
            $0.title == "차량 이동" &&
            $0.category == .movement &&
            $0.isTemporaryOverride
        })
    }

    @MainActor
    func testFridayAfternoonClassCanBeEdited() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 22, hour: 9, minute: 0),
            defaults: defaults
        )
        let original = try XCTUnwrap(store.timetableBlocks(for: .friday).first { $0.title == "오후 수업" })

        XCTAssertTrue(store.saveTimetableBlock(
            originalID: original.id,
            day: .friday,
            startMinute: original.startMinute,
            endMinute: original.endMinute,
            title: "오후 강의",
            category: .classTime
        ))

        let titles = store.timetableBlocks(for: .friday).map(\.title)
        XCTAssertFalse(titles.contains("오후 수업"))
        XCTAssertTrue(titles.contains("오후 강의"))
    }

    @MainActor
    func testDeletingBaseTimetableBlockHidesIt() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 22, hour: 9, minute: 0),
            defaults: defaults
        )
        let original = try XCTUnwrap(store.timetableBlocks(for: .friday).first { $0.title == "오후 수업" })

        store.deleteTimetableBlock(id: original.id)

        XCTAssertFalse(store.timetableBlocks(for: .friday).contains { $0.title == "오후 수업" })
    }

    @MainActor
    func testSleepScheduleSplitsAcrossMidnight() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 22, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.addSleepSchedule(
            day: .friday,
            startMinute: TimeFormatter.minutes(22, 0),
            endMinute: TimeFormatter.minutes(8, 0)
        ))

        XCTAssertTrue(store.timetableBlocks(for: .friday).contains {
            $0.title == "수면" &&
            $0.startMinute == TimeFormatter.minutes(22, 0) &&
            $0.endMinute == 24 * 60 &&
            $0.category == .sleep
        })
        XCTAssertTrue(store.timetableBlocks(for: .saturday).contains {
            $0.title == "수면" &&
            $0.startMinute == 0 &&
            $0.endMinute == TimeFormatter.minutes(8, 0) &&
            $0.category == .sleep
        })
    }

    func testCategoryInferenceUsesScheduleWords() {
        XCTAssertEqual(ScheduleCategory.infer(from: "버스 이동"), .movement)
        XCTAssertEqual(ScheduleCategory.infer(from: "프로젝트 작업"), .lab)
        XCTAssertEqual(ScheduleCategory.infer(from: "수면"), .sleep)
    }

    @MainActor
    func testNotificationCandidatesUseScheduleTransitions() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )

        let candidates = ScheduleNotificationScheduler.candidates(from: store, calendar: calendar)
        let titles = candidates.map(\.title)

        XCTAssertTrue(titles.contains("곧 이동"))
        XCTAssertTrue(titles.contains("오후 업무 시작"))
        XCTAssertTrue(titles.contains("곧 학습"))
        XCTAssertFalse(titles.contains("빈 시간 시작"))
    }

    @MainActor
    func testTodayOverrideDrivesNotificationTiming() throws {
        let fixed = ScheduleBlock(
            id: "wednesday-trip",
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "외부 이동",
            category: .movement
        )
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [fixed], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 20, hour: 17, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.saveTodayOverride(
            sourceBlockID: fixed.id,
            day: .wednesday,
            startMinute: TimeFormatter.minutes(18, 50),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "차량 이동",
            category: .movement
        ))

        let candidates = ScheduleNotificationScheduler.candidates(from: store, calendar: calendar)
        let adjustedFireDate = try makeDate(year: 2026, month: 5, day: 20, hour: 18, minute: 40)
        let originalFireDate = try makeDate(year: 2026, month: 5, day: 20, hour: 17, minute: 50)

        XCTAssertTrue(candidates.contains {
            $0.title == "곧 이동" &&
            $0.body == "10분 뒤 차량 이동이 시작됩니다." &&
            $0.fireDate == adjustedFireDate
        })
        XCTAssertFalse(candidates.contains {
            $0.title == "곧 이동" &&
            $0.body == "10분 뒤 외부 이동이 시작됩니다." &&
            $0.fireDate == originalFireDate
        })
    }

    @MainActor
    func testOvernightSleepDoesNotScheduleNextDaySleepStartAlert() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 19, hour: 23, minute: 50),
            defaults: defaults
        )

        XCTAssertTrue(store.addSleepSchedule(
            day: .tuesday,
            startMinute: TimeFormatter.minutes(23, 0),
            endMinute: TimeFormatter.minutes(8, 0)
        ))

        let candidates = ScheduleNotificationScheduler.candidates(from: store, calendar: calendar)
        let nextDay = try makeDate(year: 2026, month: 5, day: 20, hour: 0, minute: 0)
        let wakeDate = try makeDate(year: 2026, month: 5, day: 20, hour: 8, minute: 0)

        XCTAssertFalse(candidates.contains {
            $0.title == "곧 취침 시간" &&
            calendar.isDate($0.fireDate, inSameDayAs: nextDay)
        })
        XCTAssertTrue(candidates.contains {
            $0.title == "기상 시간" &&
            $0.fireDate == wakeDate
        })
    }

    @MainActor
    func testNextBlockOccurrenceFindsNextDaySleepContinuation() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 19, hour: 23, minute: 50),
            defaults: defaults
        )

        XCTAssertTrue(store.addSleepSchedule(
            day: .tuesday,
            startMinute: TimeFormatter.minutes(23, 0),
            endMinute: TimeFormatter.minutes(8, 0)
        ))

        let occurrence = try XCTUnwrap(store.nextBlockOccurrence(after: store.now, calendar: calendar))

        XCTAssertEqual(occurrence.dayOffset, 1)
        XCTAssertEqual(occurrence.block.day, .wednesday)
        XCTAssertEqual(occurrence.block.startMinute, 0)
        XCTAssertEqual(occurrence.block.endMinute, TimeFormatter.minutes(8, 0))
        XCTAssertEqual(occurrence.block.category, .sleep)
    }

    @MainActor
    func testCustomPlaceOverridesAutomaticLocationGrouping() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(10, 0),
            endMinute: TimeFormatter.minutes(11, 0),
            title: "프로젝트 문서 읽기",
            kind: .timetable,
            category: .lab,
            place: .home
        ))

        let block = try XCTUnwrap(store.timetableBlocks(for: .monday).first { $0.title == "프로젝트 문서 읽기" })
        XCTAssertEqual(block.displayPlace, .home)
    }

    func testPrimarySectionsAreFourMainTabs() {
        XCTAssertEqual(AppSection.primarySections, [.dashboard, .schedule, .statistics, .settings])
    }

    @MainActor
    func testCheckNeededCountIncludesCalendarInbox() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            engine: ScheduleEngine(fixedBlocks: [], missingItems: []),
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-pending-count",
            title: "새 약속",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 18, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertEqual(store.unresolvedMissingCount, 0)
        XCTAssertEqual(store.checkNeededCount, 1)
    }

    @MainActor
    func testWeeklyUsageStatisticsMeasurePlannedFreeTime() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let originalSchedulable = store.freeMinutes(for: .monday)

        XCTAssertTrue(store.addPlan(
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "프로젝트 문서 읽기",
            kind: .once,
            category: .lab,
            place: .home
        ))

        let stats = store.weeklyUsageStatistics()
        let monday = try XCTUnwrap(stats.dayStats.first { $0.day == .monday })

        XCTAssertEqual(monday.plannedMinutes, 60)
        XCTAssertEqual(monday.freeMinutes, originalSchedulable - 60)
        XCTAssertEqual(monday.schedulableMinutes, originalSchedulable)
        XCTAssertEqual(stats.categoryMinutes[.lab], 60)
        XCTAssertEqual(stats.placeMinutes[.home], 60)
    }

    @MainActor
    func testCalendarInboxItemCanBecomeOncePlan() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-1",
            title: "상담",
            calendarTitle: "iCloud",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 18, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)
        XCTAssertEqual(store.calendarInboxItems.count, 1)

        XCTAssertTrue(store.acceptCalendarInboxItem(id: "calendar-1", kind: .once, calendar: calendar))
        XCTAssertEqual(store.calendarInboxItems.count, 0)
        XCTAssertTrue(store.entries(for: .monday, kind: .once).contains {
            $0.title == "상담" && $0.calendarEventIdentifier == "calendar-1"
        })
        XCTAssertEqual(store.plannedMinutes(for: .monday), 60)
    }

    @MainActor
    func testCalendarInboxItemCanBecomeWeeklyPlan() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-weekly",
            title: "언어 스터디",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 18, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertTrue(store.canAcceptCalendarInboxItem(id: "calendar-weekly", calendar: calendar))
        XCTAssertTrue(store.acceptCalendarInboxItem(id: "calendar-weekly", kind: .weeklyPlan, calendar: calendar))
        XCTAssertTrue(store.entries(for: .monday, kind: .weeklyPlan).contains {
            $0.title == "언어 스터디" &&
            $0.date == nil &&
            $0.category == .language &&
            $0.calendarEventIdentifier == "calendar-weekly"
        })
        XCTAssertTrue(store.calendarInboxItems.isEmpty)
    }

    @MainActor
    func testCalendarInboxItemCanBecomeTimetableEntry() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-fixed",
            title: "정기 프로젝트",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 18, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertTrue(store.acceptCalendarInboxItem(id: "calendar-fixed", kind: .timetable, calendar: calendar))
        XCTAssertTrue(store.timetableBlocks(for: .monday).contains {
            $0.title == "정기 프로젝트" &&
            $0.category == .lab
        })
        XCTAssertEqual(store.plannedMinutes(for: .monday), 0)
        XCTAssertTrue(store.calendarInboxItems.isEmpty)
    }

    @MainActor
    func testIgnoredCalendarInboxItemDoesNotReturnAfterImport() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-ignore",
            title: "숨길 일정",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 18, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 19, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)
        store.ignoreCalendarInboxItem(id: "calendar-ignore")
        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertTrue(store.calendarInboxItems.isEmpty)
        XCTAssertTrue(store.ignoredCalendarEventIDs.contains("calendar-ignore"))
    }

    @MainActor
    func testConflictingCalendarInboxItemStaysPending() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-conflict",
            title: "겹치는 회의",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 30),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 13, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertFalse(store.canAcceptCalendarInboxItem(id: "calendar-conflict", calendar: calendar))
        XCTAssertFalse(store.acceptCalendarInboxItem(id: "calendar-conflict", kind: .once, calendar: calendar))
        XCTAssertEqual(store.calendarInboxItems.map(\.id), ["calendar-conflict"])
        XCTAssertFalse(store.entries(for: .monday, kind: .once).contains { $0.calendarEventIdentifier == "calendar-conflict" })
    }

    @MainActor
    func testConflictingCalendarInboxItemCanBeAdjustedIntoOncePlan() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-adjust-once",
            title: "겹치는 회의",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 30),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 13, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertFalse(store.canAcceptCalendarInboxItem(id: "calendar-adjust-once", calendar: calendar))
        XCTAssertTrue(store.acceptCalendarInboxItem(
            id: "calendar-adjust-once",
            kind: .once,
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "옮긴 회의",
            category: .other,
            calendar: calendar
        ))

        XCTAssertTrue(store.calendarInboxItems.isEmpty)
        XCTAssertTrue(store.entries(for: .monday, kind: .once).contains {
            $0.title == "옮긴 회의" &&
            $0.startMinute == TimeFormatter.minutes(18, 0) &&
            $0.endMinute == TimeFormatter.minutes(19, 0) &&
            $0.category == .other &&
            $0.calendarEventIdentifier == "calendar-adjust-once"
        })
    }

    @MainActor
    func testAdjustedCalendarInboxItemCanBecomeWeeklyPlan() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-adjust-weekly",
            title: "매주 회의",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 30),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 13, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertTrue(store.acceptCalendarInboxItem(
            id: "calendar-adjust-weekly",
            kind: .weeklyPlan,
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "매주 회의",
            category: .planned,
            calendar: calendar
        ))

        XCTAssertTrue(store.entries(for: .monday, kind: .weeklyPlan).contains {
            $0.title == "매주 회의" &&
            $0.date == nil &&
            $0.startMinute == TimeFormatter.minutes(18, 0) &&
            $0.endMinute == TimeFormatter.minutes(19, 0) &&
            $0.calendarEventIdentifier == "calendar-adjust-weekly"
        })
        XCTAssertTrue(store.calendarInboxItems.isEmpty)
    }

    @MainActor
    func testAdjustedCalendarInboxItemCanBecomeTimetableEntry() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-adjust-fixed",
            title: "고정 회의",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 30),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 13, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertTrue(store.acceptCalendarInboxItem(
            id: "calendar-adjust-fixed",
            kind: .timetable,
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "고정 회의",
            category: .classTime,
            calendar: calendar
        ))

        XCTAssertTrue(store.timetableBlocks(for: .monday).contains {
            $0.title == "고정 회의" &&
            $0.startMinute == TimeFormatter.minutes(18, 0) &&
            $0.endMinute == TimeFormatter.minutes(19, 0) &&
            $0.category == .classTime
        })
        XCTAssertEqual(store.plannedMinutes(for: .monday), 0)
        XCTAssertTrue(store.calendarInboxItems.isEmpty)
    }

    @MainActor
    func testAdjustedCalendarInboxItemRejectsStillConflictingTime() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        let snapshot = CalendarEventSnapshot(
            id: "calendar-adjust-conflict",
            title: "계속 겹치는 회의",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 18, hour: 12, minute: 30),
            endDate: try makeDate(year: 2026, month: 5, day: 18, hour: 13, minute: 0)
        )

        store.replaceCalendarInbox(with: [snapshot], calendar: calendar)

        XCTAssertFalse(store.acceptCalendarInboxItem(
            id: "calendar-adjust-conflict",
            kind: .once,
            day: .monday,
            startMinute: TimeFormatter.minutes(12, 30),
            endMinute: TimeFormatter.minutes(13, 0),
            title: "계속 겹치는 회의",
            category: .other,
            calendar: calendar
        ))
        XCTAssertEqual(store.calendarInboxItems.map(\.id), ["calendar-adjust-conflict"])
        XCTAssertFalse(store.entries(for: .monday, kind: .once).contains { $0.calendarEventIdentifier == "calendar-adjust-conflict" })
    }

    @MainActor
    func testLinkedCalendarPlanUpdatesWhenCalendarEventMoves() throws {
        let defaults = try makeTestDefaults()
        let store = ScheduleStore(
            now: try makeDate(year: 2026, month: 5, day: 18, hour: 9, minute: 0),
            defaults: defaults
        )
        XCTAssertNotNil(store.addPlanAndReturn(
            day: .monday,
            startMinute: TimeFormatter.minutes(18, 0),
            endMinute: TimeFormatter.minutes(19, 0),
            title: "상담",
            kind: .once,
            calendarEventIdentifier: "calendar-1"
        ))

        let moved = CalendarEventSnapshot(
            id: "calendar-1",
            title: "상담 변경",
            calendarTitle: "Google",
            startDate: try makeDate(year: 2026, month: 5, day: 19, hour: 20, minute: 0),
            endDate: try makeDate(year: 2026, month: 5, day: 19, hour: 20, minute: 30)
        )

        store.replaceCalendarInbox(with: [moved], calendar: calendar)

        XCTAssertTrue(store.entries(for: .tuesday, kind: .once).contains {
            $0.title == "상담 변경" &&
            $0.startMinute == TimeFormatter.minutes(20, 0) &&
            $0.endMinute == TimeFormatter.minutes(20, 30)
        })
        XCTAssertTrue(store.calendarInboxItems.isEmpty)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return try XCTUnwrap(components.date)
    }

    private func makeTestDefaults() throws -> UserDefaults {
        let suiteName = "JeongriTimeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
