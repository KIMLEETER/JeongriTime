import Foundation
import Combine

struct ScheduleBlockOccurrence: Identifiable, Hashable {
    let block: ScheduleBlock
    let date: Date
    let dayOffset: Int

    var id: String {
        "\(block.id)-\(dayOffset)"
    }
}

struct DayUsageStatistic: Identifiable, Hashable {
    let day: Weekday
    let freeMinutes: Int
    let plannedMinutes: Int
    let fixedMinutes: Int

    var id: Weekday { day }

    var schedulableMinutes: Int {
        freeMinutes + plannedMinutes
    }

    var usageRatio: Double {
        guard schedulableMinutes > 0 else {
            return 0
        }
        return Double(plannedMinutes) / Double(schedulableMinutes)
    }
}

struct WeeklyUsageStatistics {
    let dayStats: [DayUsageStatistic]
    let categoryMinutes: [ScheduleCategory: Int]
    let placeMinutes: [SchedulePlace: Int]

    var plannedMinutes: Int {
        dayStats.reduce(0) { $0 + $1.plannedMinutes }
    }

    var remainingFreeMinutes: Int {
        dayStats.reduce(0) { $0 + $1.freeMinutes }
    }

    var fixedMinutes: Int {
        dayStats.reduce(0) { $0 + $1.fixedMinutes }
    }

    var schedulableMinutes: Int {
        plannedMinutes + remainingFreeMinutes
    }

    var usageRatio: Double {
        guard schedulableMinutes > 0 else {
            return 0
        }
        return Double(plannedMinutes) / Double(schedulableMinutes)
    }

    var topFreeDay: DayUsageStatistic? {
        dayStats.max { lhs, rhs in
            lhs.freeMinutes < rhs.freeMinutes
        }
    }
}

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var selectedSection: AppSection = .dashboard
    @Published var selectedDay: Weekday
    @Published var now: Date
    @Published private(set) var resolvedMissingIDs: Set<String>
    @Published private(set) var plannedBlocks: [PlannedBlock]
    @Published private(set) var deletedBaseBlockIDs: Set<String>
    @Published private(set) var deletedPlanIDs: Set<String>
    @Published private(set) var calendarInboxItems: [CalendarInboxItem]
    @Published private(set) var ignoredCalendarEventIDs: Set<String>
    @Published var iCloudSyncEnabled: Bool
    @Published private(set) var cloudSyncStatus: String
    @Published private(set) var lastCloudSyncDate: Date?

    let engine: ScheduleEngine

    private let resolvedKey = "JeongriTime.resolvedMissingIDs"
    private let plannedKey = "JeongriTime.plannedBlocks"
    private let deletedBaseKey = "JeongriTime.deletedBaseBlockIDs"
    private let deletedPlanKey = "JeongriTime.deletedPlanIDs"
    private let calendarInboxKey = "JeongriTime.calendarInboxItems"
    private let ignoredCalendarKey = "JeongriTime.ignoredCalendarEventIDs"
    private let iCloudSyncEnabledKey = "JeongriTime.iCloudSyncEnabled"
    private let lastCloudSyncDateKey = "JeongriTime.lastCloudSyncDate"
    private let defaults: UserDefaults
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var applyingCloudValues = false

    init(engine: ScheduleEngine = ScheduleEngine(), now: Date = Date(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.now = now
        self.defaults = defaults
        self.selectedDay = Weekday.from(date: now)
        self.resolvedMissingIDs = Set(defaults.stringArray(forKey: resolvedKey) ?? [])
        self.plannedBlocks = Self.loadPlannedBlocks(key: plannedKey, defaults: defaults)
        self.deletedBaseBlockIDs = Set(defaults.stringArray(forKey: deletedBaseKey) ?? [])
        self.deletedPlanIDs = Set(defaults.stringArray(forKey: deletedPlanKey) ?? [])
        self.calendarInboxItems = Self.loadCalendarInboxItems(key: calendarInboxKey, defaults: defaults)
        self.ignoredCalendarEventIDs = Set(defaults.stringArray(forKey: ignoredCalendarKey) ?? [])
        let syncEnabled = defaults.object(forKey: iCloudSyncEnabledKey) as? Bool ?? false
        self.iCloudSyncEnabled = syncEnabled
        self.lastCloudSyncDate = defaults.object(forKey: lastCloudSyncDateKey) as? Date
        self.cloudSyncStatus = syncEnabled ? "대기 중" : "꺼짐"

        self.cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCloudValues()
            }
        }

        if syncEnabled {
            synchronizeWithICloud()
        }
    }

    func updateNow(_ date: Date) {
        now = date
    }

    func makeSyncSnapshot() -> ScheduleSyncSnapshot {
        ScheduleSyncSnapshot(
            plannedBlocks: plannedBlocks,
            deletedBaseBlockIDs: deletedBaseBlockIDs,
            deletedPlanIDs: deletedPlanIDs,
            resolvedMissingIDs: resolvedMissingIDs,
            calendarInboxItems: calendarInboxItems,
            ignoredCalendarEventIDs: ignoredCalendarEventIDs
        )
    }

    var unresolvedMissingCount: Int {
        Weekday.allCases.reduce(0) { total, day in
            total + engine.missingItems(for: day).filter { !resolvedMissingIDs.contains($0.id) }.count
        }
    }

    var checkNeededCount: Int {
        unresolvedMissingCount + calendarInboxItems.count
    }

    func applySyncSnapshot(_ snapshot: ScheduleSyncSnapshot) {
        let mergedDeletedPlanIDs = deletedPlanIDs.union(snapshot.deletedPlanIDs)
        let mergedIgnoredCalendarIDs = ignoredCalendarEventIDs.union(snapshot.ignoredCalendarEventIDs)

        plannedBlocks = Self.mergePlans(local: plannedBlocks, remote: snapshot.plannedBlocks)
            .filter { !mergedDeletedPlanIDs.contains($0.id) }
        deletedBaseBlockIDs.formUnion(snapshot.deletedBaseBlockIDs)
        deletedPlanIDs = mergedDeletedPlanIDs
        resolvedMissingIDs.formUnion(snapshot.resolvedMissingIDs)
        ignoredCalendarEventIDs = mergedIgnoredCalendarIDs

        let inboxByID = Dictionary(grouping: calendarInboxItems + snapshot.calendarInboxItems) { $0.id }
        calendarInboxItems = inboxByID.compactMap { _, items in
            items.sorted { $0.importedAt > $1.importedAt }.first
        }
        .filter { !mergedIgnoredCalendarIDs.contains($0.calendarEventIdentifier) }
        .sorted { $0.startDate < $1.startDate }

        persistAllLocal()
    }

    func blocks(for day: Weekday) -> [ScheduleBlock] {
        let scheduleChanges = activeScheduleChanges(for: day)
        let plans = scheduleChanges.filter { !$0.isTodayCancellation }
        return SchedulePlanner.merge(
            baseBlocks: baseBlocks(for: day, temporarilyHidingBlockIDs: todayHiddenSourceIDs(for: day, in: scheduleChanges)),
            plannedBlocks: plans
        )
    }

    func baseBlocks(for day: Weekday) -> [ScheduleBlock] {
        baseBlocks(for: day, excludingBaseBlockID: nil, temporarilyHidingBlockIDs: [])
    }

    private func baseBlocks(
        for day: Weekday,
        excludingBaseBlockID: String? = nil,
        temporarilyHidingBlockIDs: Set<String> = []
    ) -> [ScheduleBlock] {
        let hiddenBaseIDs = permanentHiddenBaseIDs.union(temporarilyHidingBlockIDs)
        let fixed = engine.fixedBlocks.filter { !hiddenBaseIDs.contains($0.id) } + plannedBlocks
            .filter { $0.day == day && $0.isTimetableEntry && !temporarilyHidingBlockIDs.contains($0.id) }
            .map { timetableBlock(from: $0) }
        let editableFixed = fixed.filter { block in
            excludingBaseBlockID == nil || block.id != excludingBaseBlockID
        }

        return ScheduleEngine(fixedBlocks: editableFixed, missingItems: engine.missingItems)
            .blocks(for: day)
    }

    func timetableBlocks(for day: Weekday) -> [ScheduleBlock] {
        let customBlocks = plannedBlocks
            .filter { $0.day == day && $0.isTimetableEntry }
            .map { timetableBlock(from: $0) }

        return (engine.fixedBlocks.filter { $0.day == day && !permanentHiddenBaseIDs.contains($0.id) } + customBlocks)
            .sorted { $0.startMinute < $1.startMinute }
    }

    func entries(for day: Weekday, kind: ScheduleEntryKind) -> [PlannedBlock] {
        plannedBlocks
            .filter { entry in
                entry.day == day &&
                !entry.isTodayCancellation &&
                entry.kind == kind &&
                (kind != .once || isInCurrentWeek(entry))
            }
            .sorted { $0.startMinute < $1.startMinute }
    }

    func todayCancellations(for day: Weekday) -> [PlannedBlock] {
        plannedBlocks
            .filter { entry in
                entry.day == day &&
                entry.isTodayCancellation &&
                entry.kind == .once &&
                isInCurrentWeek(entry)
            }
            .sorted { $0.startMinute < $1.startMinute }
    }

    func currentBlock(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> ScheduleBlock {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return blocks(for: day).first { $0.contains(minute: minute) }
            ?? engine.currentBlock(at: date, calendar: calendar)
    }

    func nextBlock(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> ScheduleBlock? {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return blocks(for: day).first { $0.startMinute > minute }
    }

    func nextBlockOccurrence(
        after date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        maxDayOffset: Int = 7
    ) -> ScheduleBlockOccurrence? {
        let startOfToday = calendar.startOfDay(for: date)
        let currentMinute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))

        for dayOffset in 0...maxDayOffset {
            guard let occurrenceDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                continue
            }

            let day = Weekday.from(date: occurrenceDate, calendar: calendar)
            let candidate = blocks(for: day).first { block in
                guard !block.isFree else {
                    return false
                }
                return dayOffset == 0 ? block.startMinute > currentMinute : block.endMinute > 0
            }

            if let candidate {
                return ScheduleBlockOccurrence(block: candidate, date: occurrenceDate, dayOffset: dayOffset)
            }
        }

        return nil
    }

    func freeBlocks(for day: Weekday) -> [ScheduleBlock] {
        blocks(for: day).filter(\.isFree)
    }

    func freeMinutes(for day: Weekday) -> Int {
        freeBlocks(for: day).reduce(0) { $0 + $1.durationMinutes }
    }

    func plannedMinutes(for day: Weekday) -> Int {
        blocks(for: day)
            .filter(\.isPlanned)
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func fixedMinutes(for day: Weekday) -> Int {
        24 * 60 - freeMinutes(for: day) - plannedMinutes(for: day)
    }

    func categoryMinutes(for day: Weekday, matching categories: Set<ScheduleCategory>) -> Int {
        blocks(for: day)
            .filter { categories.contains($0.category) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func weeklyUsageStatistics() -> WeeklyUsageStatistics {
        var dayStats: [DayUsageStatistic] = []
        var categoryMinutes: [ScheduleCategory: Int] = [:]
        var placeMinutes: [SchedulePlace: Int] = [:]

        for day in Weekday.allCases {
            let blocks = blocks(for: day)
            let free = blocks
                .filter(\.isFree)
                .reduce(0) { $0 + $1.durationMinutes }
            let plannedBlocks = blocks.filter(\.isPlanned)
            let planned = plannedBlocks.reduce(0) { $0 + $1.durationMinutes }
            let fixed = max(0, 24 * 60 - free - planned)

            dayStats.append(
                DayUsageStatistic(
                    day: day,
                    freeMinutes: free,
                    plannedMinutes: planned,
                    fixedMinutes: fixed
                )
            )

            for block in plannedBlocks {
                categoryMinutes[block.displayCategory, default: 0] += block.durationMinutes
                placeMinutes[block.displayPlace, default: 0] += block.durationMinutes
            }
        }

        return WeeklyUsageStatistics(
            dayStats: dayStats,
            categoryMinutes: categoryMinutes,
            placeMinutes: placeMinutes
        )
    }

    func remainingFreeMinutes(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let day = Weekday.from(date: date, calendar: calendar)
        let minute = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: date, calendar: calendar))
        return freeBlocks(for: day)
            .reduce(0) { total, block in
                total + block.clippedDuration(from: minute)
            }
    }

    @discardableResult
    func addPlan(
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        kind: ScheduleEntryKind = .once,
        category: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        sourceBlockID: String? = nil
    ) -> Bool {
        addPlanAndReturn(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            title: title,
            kind: kind,
            category: category,
            place: place,
            sourceBlockID: sourceBlockID
        ) != nil
    }

    @discardableResult
    func addPlanAndReturn(
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        kind: ScheduleEntryKind = .once,
        category: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        sourceBlockID: String? = nil,
        calendarEventIdentifier: String? = nil
    ) -> PlannedBlock? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              canPlaceEntry(day: day, startMinute: startMinute, endMinute: endMinute, sourceBlockID: sourceBlockID)
        else {
            return nil
        }

        let entry = appendEntry(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            title: trimmed,
            kind: kind,
            category: category ?? ScheduleCategory.infer(from: trimmed),
            place: place,
            sourceBlockID: sourceBlockID,
            calendarEventIdentifier: calendarEventIdentifier
        )
        persistPlannedBlocks()
        return entry
    }

    @discardableResult
    func saveTodayOverride(
        sourceBlockID: String,
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        category: ScheduleCategory,
        place: SchedulePlace? = nil
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let existingOverrideIDs = Set(plannedBlocks.filter {
            $0.day == day &&
            $0.kind == .once &&
            $0.sourceBlockID == sourceBlockID &&
            isInCurrentWeek($0)
        }.map(\.id))
        let activeWithoutExistingOverrides = activeScheduleChanges(for: day).filter { !existingOverrideIDs.contains($0.id) }
        let hiddenSources = todayHiddenSourceIDs(for: day, in: activeWithoutExistingOverrides).union([sourceBlockID])

        guard SchedulePlanner.canPlan(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            baseBlocks: baseBlocks(
                for: day,
                excludingBaseBlockID: sourceBlockID,
                temporarilyHidingBlockIDs: hiddenSources
            ),
            plannedBlocks: activeWithoutExistingOverrides.filter { !$0.isTodayCancellation }
        ) else {
            return false
        }

        if !existingOverrideIDs.isEmpty {
            plannedBlocks.removeAll { existingOverrideIDs.contains($0.id) }
            deletedPlanIDs.formUnion(existingOverrideIDs)
            persistDeletedPlanIDs()
        }

        appendEntry(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            title: trimmed,
            kind: .once,
            category: category,
            place: place,
            sourceBlockID: sourceBlockID
        )
        persistPlannedBlocks()
        return true
    }

    @discardableResult
    func hideTimetableBlockForToday(sourceBlockID: String, day: Weekday) -> Bool {
        guard let source = timetableBlocks(for: day).first(where: { $0.id == sourceBlockID }) else {
            return false
        }

        let existingChangeIDs = Set(plannedBlocks.filter {
            $0.day == day &&
            $0.kind == .once &&
            $0.sourceBlockID == sourceBlockID &&
            isInCurrentWeek($0)
        }.map(\.id))

        if !existingChangeIDs.isEmpty {
            plannedBlocks.removeAll { existingChangeIDs.contains($0.id) }
            deletedPlanIDs.formUnion(existingChangeIDs)
            persistDeletedPlanIDs()
        }

        appendEntry(
            day: day,
            startMinute: source.startMinute,
            endMinute: source.endMinute,
            title: source.title,
            kind: .once,
            category: source.displayCategory,
            place: source.displayPlace,
            sourceBlockID: source.id,
            isTodayCancellation: true
        )
        persistPlannedBlocks()
        return true
    }

    @discardableResult
    func hideAllTimetableBlocksForToday(day: Weekday) -> Int {
        timetableBlocks(for: day).reduce(0) { count, block in
            count + (hideTimetableBlockForToday(sourceBlockID: block.id, day: day) ? 1 : 0)
        }
    }

    func restoreTodayCancellation(id: String) {
        guard plannedBlocks.contains(where: { $0.id == id && $0.isTodayCancellation }) else {
            return
        }
        deletePlan(id: id)
    }

    @discardableResult
    func restoreAllTodayCancellations(day: Weekday) -> Int {
        let ids = todayCancellations(for: day).map(\.id)
        ids.forEach { restoreTodayCancellation(id: $0) }
        return ids.count
    }

    @discardableResult
    func addSleepSchedule(day: Weekday, startMinute: Int, endMinute: Int, title: String = "수면") -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmed.isEmpty ? "수면" : trimmed

        if startMinute < endMinute {
            return addPlan(
                day: day,
                startMinute: startMinute,
                endMinute: endMinute,
                title: safeTitle,
                kind: .timetable,
                category: .sleep
            )
        }

        let nextDay = day.next
        guard canPlaceEntry(day: day, startMinute: startMinute, endMinute: 24 * 60, sourceBlockID: nil),
              canPlaceEntry(day: nextDay, startMinute: 0, endMinute: endMinute, sourceBlockID: nil)
        else {
            return false
        }

        appendEntry(day: day, startMinute: startMinute, endMinute: 24 * 60, title: safeTitle, kind: .timetable, category: .sleep)
        appendEntry(day: nextDay, startMinute: 0, endMinute: endMinute, title: safeTitle, kind: .timetable, category: .sleep)
        persistPlannedBlocks()
        return true
    }

    func deletePlan(id: String) {
        plannedBlocks.removeAll { $0.id == id }
        deletedPlanIDs.insert(id)
        persistPlannedBlocks()
        persistDeletedPlanIDs()
    }

    func deleteTimetableBlock(id: String) {
        if let entry = plannedBlocks.first(where: { $0.id == id && $0.isTimetableEntry }) {
            if let sourceBlockID = entry.sourceBlockID {
                deletedBaseBlockIDs.insert(sourceBlockID)
                persistDeletedBaseBlocks()
            }
            deletePlan(id: id)
            return
        }

        if engine.fixedBlocks.contains(where: { $0.id == id }) {
            deletedBaseBlockIDs.insert(id)
            persistDeletedBaseBlocks()
        }
    }

    @discardableResult
    func saveTimetableBlock(
        originalID: String,
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        category: ScheduleCategory,
        place: SchedulePlace? = nil
    ) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let existingEntry = plannedBlocks.first { $0.id == originalID && $0.isTimetableEntry }
        let baseSourceID = existingEntry?.sourceBlockID
            ?? engine.fixedBlocks.first(where: { $0.id == originalID })?.id
        let excludingID = existingEntry?.id ?? baseSourceID

        guard canPlaceEntry(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            sourceBlockID: excludingID
        ) else {
            return false
        }

        if let index = plannedBlocks.firstIndex(where: { $0.id == originalID && $0.isTimetableEntry }) {
            plannedBlocks[index] = PlannedBlock(
                id: originalID,
                day: day,
                startMinute: startMinute,
                endMinute: endMinute,
                title: trimmed,
                kind: .timetable,
                category: category,
                place: place,
                sourceBlockID: plannedBlocks[index].sourceBlockID,
                calendarEventIdentifier: plannedBlocks[index].calendarEventIdentifier,
                isTodayCancellation: plannedBlocks[index].isTodayCancellation
            )
        } else {
            if let baseSourceID {
                plannedBlocks.removeAll { $0.sourceBlockID == baseSourceID }
                deletedBaseBlockIDs.remove(baseSourceID)
                persistDeletedBaseBlocks()
            }

            appendEntry(
                day: day,
                startMinute: startMinute,
                endMinute: endMinute,
                title: trimmed,
                kind: .timetable,
                category: category,
                place: place,
                sourceBlockID: baseSourceID
            )
        }

        persistPlannedBlocks()
        return true
    }

    func setMissingResolved(_ item: MissingInfoItem, resolved: Bool) {
        if resolved {
            resolvedMissingIDs.insert(item.id)
        } else {
            resolvedMissingIDs.remove(item.id)
        }
        persistResolvedMissingIDs()
    }

    func isResolved(_ item: MissingInfoItem) -> Bool {
        resolvedMissingIDs.contains(item.id)
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        iCloudSyncEnabled = enabled
        defaults.set(enabled, forKey: iCloudSyncEnabledKey)
        cloudSyncStatus = enabled ? "대기 중" : "꺼짐"

        if enabled {
            synchronizeWithICloud()
        }
    }

    func synchronizeWithICloud() {
        guard iCloudSyncEnabled else {
            cloudSyncStatus = "꺼짐"
            return
        }

        cloudSyncStatus = "동기화 중"
        cloudStore.synchronize()
        applyCloudValues()
    }

    func linkCalendarEvent(planID: String, eventIdentifier: String) {
        guard let index = plannedBlocks.firstIndex(where: { $0.id == planID }) else {
            return
        }

        let entry = plannedBlocks[index]
        plannedBlocks[index] = PlannedBlock(
            id: entry.id,
            day: entry.day,
            date: entry.date,
            startMinute: entry.startMinute,
            endMinute: entry.endMinute,
            title: entry.title,
            kind: entry.kind,
            category: entry.category,
            place: entry.place,
            sourceBlockID: entry.sourceBlockID,
            calendarEventIdentifier: eventIdentifier,
            isTodayCancellation: entry.isTodayCancellation
        )
        persistPlannedBlocks()
    }

    func calendarInboxItems(for day: Weekday, calendar: Calendar = .autoupdatingCurrent) -> [CalendarInboxItem] {
        calendarInboxItems
            .filter { $0.day(calendar: calendar) == day }
            .sorted { $0.startDate < $1.startDate }
    }

    func canAcceptCalendarInboxItem(
        id: String,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let item = calendarInboxItems.first(where: { $0.id == id }) else {
            return false
        }

        let placement = calendarInboxPlacement(for: item, calendar: calendar)
        return canPlaceEntry(
            day: placement.day,
            startMinute: placement.start,
            endMinute: placement.end,
            sourceBlockID: nil
        )
    }

    func calendarInboxTodayOverrideSource(
        id: String,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleBlock? {
        guard let item = calendarInboxItems.first(where: { $0.id == id }) else {
            return nil
        }

        let placement = calendarInboxPlacement(for: item, calendar: calendar)
        return todayOverrideSource(
            day: placement.day,
            startMinute: placement.start,
            endMinute: placement.end
        )
    }

    func replaceCalendarInbox(with snapshots: [CalendarEventSnapshot], calendar: Calendar = .autoupdatingCurrent) {
        updateLinkedPlans(from: snapshots, calendar: calendar)

        let linkedEventIDs = Set(plannedBlocks.compactMap(\.calendarEventIdentifier))
        let knownEventIDs = linkedEventIDs.union(ignoredCalendarEventIDs)
        calendarInboxItems = snapshots
            .filter { !knownEventIDs.contains($0.id) }
            .map {
                CalendarInboxItem(
                    calendarEventIdentifier: $0.id,
                    calendarTitle: $0.calendarTitle,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            }
            .sorted { $0.startDate < $1.startDate }
        persistCalendarInboxItems()
    }

    @discardableResult
    func acceptCalendarInboxItem(
        id: String,
        kind: ScheduleEntryKind,
        category: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let item = calendarInboxItems.first(where: { $0.id == id }) else {
            return false
        }

        let placement = calendarInboxPlacement(for: item, calendar: calendar)
        let inferredCategory = category ?? ScheduleCategory.infer(from: item.title)

        guard canPlaceEntry(
            day: placement.day,
            startMinute: placement.start,
            endMinute: placement.end,
            sourceBlockID: nil
        ) else {
            return false
        }

        plannedBlocks.append(
            PlannedBlock(
                day: placement.day,
                date: kind == .once ? item.startDate : nil,
                startMinute: placement.start,
                endMinute: placement.end,
                title: item.title,
                kind: kind,
                category: inferredCategory,
                place: place,
                calendarEventIdentifier: item.calendarEventIdentifier
            )
        )
        calendarInboxItems.removeAll { $0.id == id }
        persistPlannedBlocks()
        persistCalendarInboxItems()
        return true
    }

    @discardableResult
    func acceptCalendarInboxItemAsTodayOverride(
        id: String,
        category: ScheduleCategory? = nil,
        place: SchedulePlace? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let item = calendarInboxItems.first(where: { $0.id == id }) else {
            return false
        }

        let placement = calendarInboxPlacement(for: item, calendar: calendar)
        guard let source = todayOverrideSource(
            day: placement.day,
            startMinute: placement.start,
            endMinute: placement.end
        ) else {
            return false
        }

        let inferredCategory = category ?? ScheduleCategory.infer(from: item.title)
        let existingOverrideIDs = Set(plannedBlocks.filter {
            $0.day == placement.day &&
            $0.kind == .once &&
            $0.sourceBlockID == source.id &&
            isInCurrentWeek($0)
        }.map(\.id))
        let activeWithoutExistingOverrides = activeScheduleChanges(for: placement.day).filter { !existingOverrideIDs.contains($0.id) }
        let hiddenSources = todayHiddenSourceIDs(for: placement.day, in: activeWithoutExistingOverrides).union([source.id])

        guard SchedulePlanner.canPlan(
            day: placement.day,
            startMinute: placement.start,
            endMinute: placement.end,
            baseBlocks: baseBlocks(
                for: placement.day,
                excludingBaseBlockID: source.id,
                temporarilyHidingBlockIDs: hiddenSources
            ),
            plannedBlocks: activeWithoutExistingOverrides.filter { !$0.isTodayCancellation }
        ) else {
            return false
        }

        if !existingOverrideIDs.isEmpty {
            plannedBlocks.removeAll { existingOverrideIDs.contains($0.id) }
            deletedPlanIDs.formUnion(existingOverrideIDs)
            persistDeletedPlanIDs()
        }

        plannedBlocks.append(
            PlannedBlock(
                day: placement.day,
                date: item.startDate,
                startMinute: placement.start,
                endMinute: placement.end,
                title: item.title,
                kind: .once,
                category: inferredCategory,
                place: place,
                sourceBlockID: source.id,
                calendarEventIdentifier: item.calendarEventIdentifier
            )
        )
        calendarInboxItems.removeAll { $0.id == id }
        persistPlannedBlocks()
        persistCalendarInboxItems()
        return true
    }

    @discardableResult
    func acceptCalendarInboxItem(
        id: String,
        kind: ScheduleEntryKind,
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        category: ScheduleCategory,
        place: SchedulePlace? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let item = calendarInboxItems.first(where: { $0.id == id }) else {
            return false
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              canPlaceEntry(day: day, startMinute: startMinute, endMinute: endMinute, sourceBlockID: nil)
        else {
            return false
        }

        plannedBlocks.append(
            PlannedBlock(
                day: day,
                date: adjustedDate(for: item, day: day, kind: kind, calendar: calendar),
                startMinute: startMinute,
                endMinute: endMinute,
                title: trimmed,
                kind: kind,
                category: category,
                place: place,
                calendarEventIdentifier: item.calendarEventIdentifier
            )
        )
        calendarInboxItems.removeAll { $0.id == id }
        persistPlannedBlocks()
        persistCalendarInboxItems()
        return true
    }

    private func calendarInboxPlacement(
        for item: CalendarInboxItem,
        calendar: Calendar
    ) -> (day: Weekday, start: Int, end: Int) {
        let day = item.day(calendar: calendar)
        let start = item.startMinute(calendar: calendar)
        let end = min(24 * 60, max(start + 5, item.endMinute(calendar: calendar)))
        return (day, start, end)
    }

    private func todayOverrideSource(day: Weekday, startMinute: Int, endMinute: Int) -> ScheduleBlock? {
        timetableBlocks(for: day)
            .filter { block in
                block.startMinute < endMinute && startMinute < block.endMinute
            }
            .max { lhs, rhs in
                overlapMinutes(lhs, startMinute: startMinute, endMinute: endMinute) <
                    overlapMinutes(rhs, startMinute: startMinute, endMinute: endMinute)
            }
    }

    private func overlapMinutes(_ block: ScheduleBlock, startMinute: Int, endMinute: Int) -> Int {
        max(0, min(block.endMinute, endMinute) - max(block.startMinute, startMinute))
    }

    private func adjustedDate(
        for item: CalendarInboxItem,
        day: Weekday,
        kind: ScheduleEntryKind,
        calendar: Calendar
    ) -> Date? {
        guard kind == .once else {
            return nil
        }
        if item.day(calendar: calendar) == day {
            return item.startDate
        }
        return date(for: day, calendar: calendar)
    }

    func ignoreCalendarInboxItem(id: String) {
        ignoredCalendarEventIDs.insert(id)
        calendarInboxItems.removeAll { $0.id == id }
        persistIgnoredCalendarEventIDs()
        persistCalendarInboxItems()
    }

    private static func loadPlannedBlocks(key: String, defaults: UserDefaults) -> [PlannedBlock] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PlannedBlock].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func loadCalendarInboxItems(key: String, defaults: UserDefaults) -> [CalendarInboxItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CalendarInboxItem].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func persistPlannedBlocks() {
        let sorted = plannedBlocks.sorted {
            if $0.day.calendarWeekday != $1.day.calendarWeekday {
                return $0.day.calendarWeekday < $1.day.calendarWeekday
            }
            return $0.startMinute < $1.startMinute
        }
        plannedBlocks = sorted.filter { !deletedPlanIDs.contains($0.id) }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: plannedKey)
        }
        pushCloudSnapshot()
    }

    private func persistDeletedBaseBlocks() {
        defaults.set(Array(deletedBaseBlockIDs).sorted(), forKey: deletedBaseKey)
        pushCloudSnapshot()
    }

    private func persistDeletedPlanIDs() {
        defaults.set(Array(deletedPlanIDs).sorted(), forKey: deletedPlanKey)
        pushCloudSnapshot()
    }

    private func persistResolvedMissingIDs() {
        defaults.set(Array(resolvedMissingIDs).sorted(), forKey: resolvedKey)
        pushCloudSnapshot()
    }

    private func persistCalendarInboxItems() {
        if let data = try? JSONEncoder().encode(calendarInboxItems) {
            defaults.set(data, forKey: calendarInboxKey)
        }
        pushCloudSnapshot()
    }

    private func persistIgnoredCalendarEventIDs() {
        defaults.set(Array(ignoredCalendarEventIDs).sorted(), forKey: ignoredCalendarKey)
        pushCloudSnapshot()
    }

    private func persistAllLocal() {
        if let data = try? JSONEncoder().encode(plannedBlocks) {
            defaults.set(data, forKey: plannedKey)
        }
        if let data = try? JSONEncoder().encode(calendarInboxItems) {
            defaults.set(data, forKey: calendarInboxKey)
        }
        defaults.set(Array(resolvedMissingIDs).sorted(), forKey: resolvedKey)
        defaults.set(Array(deletedBaseBlockIDs).sorted(), forKey: deletedBaseKey)
        defaults.set(Array(deletedPlanIDs).sorted(), forKey: deletedPlanKey)
        defaults.set(Array(ignoredCalendarEventIDs).sorted(), forKey: ignoredCalendarKey)
        defaults.set(lastCloudSyncDate, forKey: lastCloudSyncDateKey)
    }

    private func pushCloudSnapshot() {
        guard iCloudSyncEnabled, !applyingCloudValues else {
            return
        }

        if let data = try? JSONEncoder().encode(plannedBlocks) {
            cloudStore.set(data, forKey: plannedKey)
        }
        if let data = try? JSONEncoder().encode(calendarInboxItems) {
            cloudStore.set(data, forKey: calendarInboxKey)
        }
        cloudStore.set(Array(resolvedMissingIDs).sorted(), forKey: resolvedKey)
        cloudStore.set(Array(deletedBaseBlockIDs).sorted(), forKey: deletedBaseKey)
        cloudStore.set(Array(deletedPlanIDs).sorted(), forKey: deletedPlanKey)
        cloudStore.set(Array(ignoredCalendarEventIDs).sorted(), forKey: ignoredCalendarKey)
        cloudStore.synchronize()

        lastCloudSyncDate = Date()
        defaults.set(lastCloudSyncDate, forKey: lastCloudSyncDateKey)
        cloudSyncStatus = "동기화됨"
    }

    private func applyCloudValues() {
        guard iCloudSyncEnabled else {
            return
        }

        applyingCloudValues = true
        let remoteDeletedPlanIDs = Self.cloudStringSet(key: deletedPlanKey, cloudStore: cloudStore)
        let mergedDeletedPlanIDs = deletedPlanIDs.union(remoteDeletedPlanIDs)

        if let remotePlans = Self.decodeCloud([PlannedBlock].self, key: plannedKey, cloudStore: cloudStore) {
            plannedBlocks = Self.mergePlans(local: plannedBlocks, remote: remotePlans)
                .filter { !mergedDeletedPlanIDs.contains($0.id) }
        } else {
            plannedBlocks = plannedBlocks.filter { !mergedDeletedPlanIDs.contains($0.id) }
        }

        if let remoteInbox = Self.decodeCloud([CalendarInboxItem].self, key: calendarInboxKey, cloudStore: cloudStore) {
            let byID = Dictionary(grouping: calendarInboxItems + remoteInbox) { $0.id }
            calendarInboxItems = byID.compactMap { _, items in
                items.sorted { $0.importedAt > $1.importedAt }.first
            }
            .sorted { $0.startDate < $1.startDate }
        }

        resolvedMissingIDs.formUnion(Self.cloudStringSet(key: resolvedKey, cloudStore: cloudStore))
        deletedBaseBlockIDs.formUnion(Self.cloudStringSet(key: deletedBaseKey, cloudStore: cloudStore))
        deletedPlanIDs = mergedDeletedPlanIDs
        ignoredCalendarEventIDs.formUnion(Self.cloudStringSet(key: ignoredCalendarKey, cloudStore: cloudStore))
        calendarInboxItems.removeAll { ignoredCalendarEventIDs.contains($0.calendarEventIdentifier) }

        lastCloudSyncDate = Date()
        cloudSyncStatus = "동기화됨"
        persistAllLocal()
        applyingCloudValues = false
        pushCloudSnapshot()
    }

    private static func decodeCloud<T: Decodable>(
        _ type: T.Type,
        key: String,
        cloudStore: NSUbiquitousKeyValueStore
    ) -> T? {
        guard let data = cloudStore.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func cloudStringSet(key: String, cloudStore: NSUbiquitousKeyValueStore) -> Set<String> {
        Set((cloudStore.object(forKey: key) as? [String]) ?? [])
    }

    private static func mergePlans(local: [PlannedBlock], remote: [PlannedBlock]) -> [PlannedBlock] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for plan in remote {
            byID[plan.id] = plan
        }
        return byID.values.sorted {
            if $0.day.calendarWeekday != $1.day.calendarWeekday {
                return $0.day.calendarWeekday < $1.day.calendarWeekday
            }
            return $0.startMinute < $1.startMinute
        }
    }

    private func updateLinkedPlans(from snapshots: [CalendarEventSnapshot], calendar: Calendar) {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        var changed = false

        plannedBlocks = plannedBlocks.map { entry in
            guard let eventID = entry.calendarEventIdentifier,
                  let snapshot = snapshotsByID[eventID]
            else {
                return entry
            }

            let day = Weekday.from(date: snapshot.startDate, calendar: calendar)
            let start = TimeFormatter.floorToFive(TimeFormatter.minuteOfDay(from: snapshot.startDate, calendar: calendar))
            let rawEnd: Int
            if calendar.isDate(snapshot.startDate, inSameDayAs: snapshot.endDate) {
                rawEnd = TimeFormatter.ceilToFive(TimeFormatter.minuteOfDay(from: snapshot.endDate, calendar: calendar))
            } else {
                rawEnd = 24 * 60
            }
            let end = min(24 * 60, max(start + 5, rawEnd))

            guard entry.title != snapshot.title ||
                    entry.day != day ||
                    entry.startMinute != start ||
                    entry.endMinute != end
            else {
                return entry
            }

            changed = true
            return PlannedBlock(
                id: entry.id,
                day: day,
                date: entry.kind == .once ? snapshot.startDate : entry.date,
                startMinute: start,
                endMinute: end,
                title: snapshot.title,
                kind: entry.kind,
                category: entry.category,
                place: entry.place,
                sourceBlockID: entry.sourceBlockID,
                calendarEventIdentifier: eventID,
                isTodayCancellation: entry.isTodayCancellation
            )
        }

        if changed {
            persistPlannedBlocks()
        }
    }

    private func canPlaceEntry(day: Weekday, startMinute: Int, endMinute: Int, sourceBlockID: String?) -> Bool {
        let scheduleChanges = activeScheduleChanges(for: day)
        let plans = scheduleChanges.filter { !$0.isTodayCancellation }
        let hiddenSources = todayHiddenSourceIDs(for: day, in: scheduleChanges)

        return SchedulePlanner.canPlan(
            day: day,
            startMinute: startMinute,
            endMinute: endMinute,
            baseBlocks: baseBlocks(
                for: day,
                excludingBaseBlockID: sourceBlockID,
                temporarilyHidingBlockIDs: sourceBlockID.map { hiddenSources.union([$0]) } ?? hiddenSources
            ),
            plannedBlocks: plans
        )
    }

    @discardableResult
    private func appendEntry(
        day: Weekday,
        startMinute: Int,
        endMinute: Int,
        title: String,
        kind: ScheduleEntryKind,
        category: ScheduleCategory,
        place: SchedulePlace? = nil,
        sourceBlockID: String? = nil,
        calendarEventIdentifier: String? = nil,
        isTodayCancellation: Bool = false
    ) -> PlannedBlock {
        let entry = PlannedBlock(
            day: day,
            date: kind == .once ? date(for: day) : nil,
            startMinute: startMinute,
            endMinute: endMinute,
            title: title,
            kind: kind,
            category: category,
            place: place,
            sourceBlockID: sourceBlockID,
            calendarEventIdentifier: calendarEventIdentifier,
            isTodayCancellation: isTodayCancellation
        )
        plannedBlocks.append(entry)
        return entry
    }

    func date(for day: Weekday, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        let sunday = calendar.date(byAdding: .day, value: 1 - currentWeekday, to: startOfToday) ?? startOfToday
        return calendar.date(byAdding: .day, value: day.calendarWeekday - 1, to: sunday) ?? startOfToday
    }

    func currentWeekInterval(calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        let start = date(for: .sunday, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func activeScheduleChanges(for day: Weekday) -> [PlannedBlock] {
        plannedBlocks.filter { entry in
            guard entry.day == day else {
                return false
            }

            switch entry.kind {
            case .once:
                return isInCurrentWeek(entry)
            case .weeklyPlan:
                return true
            case .timetable:
                return false
            }
        }
    }

    private var permanentHiddenBaseIDs: Set<String> {
        Set(plannedBlocks.filter(\.isTimetableEntry).compactMap(\.sourceBlockID))
            .union(deletedBaseBlockIDs)
    }

    private func todayHiddenSourceIDs(for day: Weekday, in plans: [PlannedBlock]) -> Set<String> {
        Set(plans.filter {
            $0.day == day &&
            $0.kind == .once &&
            $0.sourceBlockID != nil &&
            isInCurrentWeek($0)
        }.compactMap(\.sourceBlockID))
    }

    private func isInCurrentWeek(_ entry: PlannedBlock, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let entryDate = entry.date else {
            return false
        }
        return calendar.isDate(entryDate, inSameDayAs: date(for: entry.day, calendar: calendar))
    }

    private func timetableBlock(from entry: PlannedBlock) -> ScheduleBlock {
        ScheduleBlock(
            id: entry.id,
            day: entry.day,
            startMinute: entry.startMinute,
            endMinute: entry.endMinute,
            title: entry.title,
            category: entry.category,
            place: entry.place,
            note: entry.sourceBlockID == nil ? "시간표에 추가됨" : "시간표에서 수정됨"
        )
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "오늘"
    case timeline = "빈시간"
    case week = "주간"
    case schedule = "시간표"
    case statistics = "통계"
    case missing = "확인"
    case settings = "설정"

    var id: String { rawValue }

    static var primarySections: [AppSection] {
        [.dashboard, .schedule, .statistics, .settings]
    }

    var symbolName: String {
        switch self {
        case .dashboard: "clock.badge.checkmark"
        case .timeline: "list.bullet.rectangle"
        case .week: "calendar"
        case .schedule: "calendar.badge.plus"
        case .statistics: "chart.bar.xaxis"
        case .missing: "exclamationmark.circle"
        case .settings: "gearshape"
        }
    }
}
