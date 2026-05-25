import EventKit
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct CalendarEventSnapshot: Identifiable, Hashable {
    let id: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
}

struct CalendarSourceChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let typeName: String
    let calendars: [CalendarChoice]

    var calendarIDs: Set<String> {
        Set(calendars.map(\.id))
    }
}

struct CalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

enum CalendarBridgeError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case eventSaveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "캘린더 접근 권한이 없습니다."
        case .noWritableCalendar:
            return "새 일정을 저장할 기본 캘린더가 없습니다."
        case .eventSaveFailed:
            return "캘린더 일정을 저장하지 못했습니다."
        }
    }
}

@MainActor
final class CalendarBridge: ObservableObject {
    @Published private(set) var statusText = "확인 중"
    @Published private(set) var defaultCalendarTitle: String?
    @Published private(set) var availableCalendarSources: [CalendarSourceChoice] = []
    @Published private(set) var selectedCalendarIDs: Set<String>
    @Published private(set) var importedCalendarTitles: [String] = []
    @Published private(set) var showsAccessInstructions = false
    @Published var message: String?

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private let selectedCalendarIDsKey = "JeongriTime.selectedCalendarIDs"
    private let automaticCalendarSelectionKey = "JeongriTime.usesAutomaticCalendarSelection"
    private var usesAutomaticCalendarSelection: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedCalendarIDs = Set(defaults.stringArray(forKey: selectedCalendarIDsKey) ?? [])
        self.usesAutomaticCalendarSelection = defaults.object(forKey: automaticCalendarSelectionKey) as? Bool ?? true
        refreshStatus()
    }

    var availableCalendarCount: Int {
        availableCalendarSources.reduce(0) { $0 + $1.calendars.count }
    }

    var selectedCalendarCount: Int {
        selectedCalendarIDs.intersection(allAvailableCalendarIDs).count
    }

    var accessActionTitle: String {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.isFullAccess(status) {
            return "권한 확인"
        }
        return status == .notDetermined ? "캘린더 허용" : "해결 방법"
    }

    var accessActionSystemImage: String {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .notDetermined ? "checkmark.shield" : "gearshape"
    }

    func refreshStatus() {
        statusText = Self.statusText(for: EKEventStore.authorizationStatus(for: .event))
        defaultCalendarTitle = eventStore.defaultCalendarForNewEvents?.title
        refreshAvailableCalendars()
        if Self.isFullAccess(EKEventStore.authorizationStatus(for: .event)) {
            showsAccessInstructions = false
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            refreshStatus()
            message = granted ? "캘린더 접근을 허용했습니다." : "캘린더 접근이 허용되지 않았습니다."
            showsAccessInstructions = !granted
            return granted
        } catch {
            refreshStatus()
            message = "캘린더 권한 요청에 실패했습니다."
            showsAccessInstructions = true
            return false
        }
    }

    @discardableResult
    func requestAccessOrShowInstructions() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.isFullAccess(status) {
            refreshStatus()
            message = "캘린더 접근이 이미 허용되어 있습니다."
            showsAccessInstructions = false
            return true
        }

        if status == .notDetermined {
            let granted = await requestAccess()
            if !granted {
                message = Self.calendarSettingsInstruction()
                showsAccessInstructions = true
            }
            return granted
        }

        refreshStatus()
        showsAccessInstructions = true
        message = Self.calendarSettingsInstruction()
        return false
    }

    func openSystemCalendarSettings() {
        let openedSettings = openCalendarPrivacySettings()
        message = openedSettings ? "시스템 설정을 열었습니다. 캘린더 권한을 켠 뒤 정리시간으로 돌아와 다시 확인하세요." : Self.calendarSettingsInstruction()
    }

    func setCalendarSelection(calendarID: String, isSelected: Bool) {
        usesAutomaticCalendarSelection = false
        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
        persistCalendarSelection()
    }

    func setSourceSelection(sourceID: String, isSelected: Bool) {
        guard let source = availableCalendarSources.first(where: { $0.id == sourceID }) else {
            return
        }

        usesAutomaticCalendarSelection = false
        if isSelected {
            selectedCalendarIDs.formUnion(source.calendarIDs)
        } else {
            selectedCalendarIDs.subtract(source.calendarIDs)
        }
        persistCalendarSelection()
    }

    func selectAllCalendars() {
        usesAutomaticCalendarSelection = true
        selectedCalendarIDs = allAvailableCalendarIDs
        persistCalendarSelection()
        message = "모든 캘린더를 가져오도록 했습니다."
    }

    func clearCalendarSelection() {
        usesAutomaticCalendarSelection = false
        selectedCalendarIDs.removeAll()
        persistCalendarSelection()
        message = "가져올 캘린더 선택을 모두 해제했습니다."
    }

    func importCurrentWeek(into store: ScheduleStore, calendar: Calendar = .autoupdatingCurrent) async {
        guard await ensureFullAccess() else {
            message = "캘린더 권한이 필요합니다."
            return
        }

        refreshAvailableCalendars()
        let selectedCalendars = selectedEventCalendars()
        guard !selectedCalendars.isEmpty else {
            message = "가져올 캘린더를 먼저 선택하세요."
            return
        }

        let interval = store.currentWeekInterval(calendar: calendar)
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: selectedCalendars
        )

        let snapshots = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .compactMap { event -> CalendarEventSnapshot? in
                guard let eventID = event.eventIdentifier,
                      event.endDate > event.startDate
                else {
                    return nil
                }

                let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarEventSnapshot(
                    id: eventID,
                    title: title.isEmpty ? "캘린더 일정" : title,
                    calendarTitle: event.calendar?.title ?? "캘린더",
                    startDate: event.startDate,
                    endDate: event.endDate
                )
            }
            .sorted { $0.startDate < $1.startDate }

        importedCalendarTitles = Array(Set(snapshots.map(\.calendarTitle))).sorted()
        store.replaceCalendarInbox(with: snapshots, calendar: calendar)

        let count = store.calendarInboxItems.count
        message = count == 0 ? "처리할 새 캘린더 일정이 없습니다." : "\(count)개의 새 캘린더 일정이 처리 대기 중입니다."
        refreshStatus()
    }

    func createEvent(for plan: PlannedBlock, date: Date, calendar: Calendar = .autoupdatingCurrent) async throws -> String {
        guard await ensureFullAccess() else {
            throw CalendarBridgeError.accessDenied
        }
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarBridgeError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        event.title = plan.title
        event.startDate = dateForMinute(plan.startMinute, on: date, calendar: calendar)
        event.endDate = dateForMinute(plan.endMinute, on: date, calendar: calendar)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            refreshStatus()
            guard let eventID = event.eventIdentifier else {
                throw CalendarBridgeError.eventSaveFailed
            }
            message = "기본 캘린더에 일정을 추가했습니다."
            return eventID
        } catch {
            message = "캘린더에 일정을 추가하지 못했습니다."
            throw error
        }
    }

    private func ensureFullAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.isFullAccess(status) {
            refreshAvailableCalendars()
            return true
        }
        if status == .notDetermined {
            return await requestAccess()
        }
        refreshStatus()
        return false
    }

    @discardableResult
    private func openCalendarPrivacySettings() -> Bool {
        #if os(macOS)
        let urls = [
            URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            URL(fileURLWithPath: "/System/Applications/System Preferences.app")
        ]

        for url in urls where NSWorkspace.shared.open(url) {
            return true
        }
        return false
        #elseif os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
        #else
        return false
        #endif
    }

    private func dateForMinute(_ minute: Int, on date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
    }

    private var allAvailableCalendarIDs: Set<String> {
        Set(availableCalendarSources.flatMap { $0.calendars.map(\.id) })
    }

    private func refreshAvailableCalendars() {
        guard Self.isFullAccess(EKEventStore.authorizationStatus(for: .event)) else {
            availableCalendarSources = []
            return
        }

        eventStore.refreshSourcesIfNecessary()
        let sources = eventStore.sources
            .compactMap { source -> CalendarSourceChoice? in
                let calendars = source.calendars(for: .event)
                    .map {
                        CalendarChoice(
                            id: $0.calendarIdentifier,
                            title: $0.title
                        )
                    }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

                guard !calendars.isEmpty else {
                    return nil
                }

                return CalendarSourceChoice(
                    id: source.sourceIdentifier,
                    title: source.title.isEmpty ? "캘린더 계정" : source.title,
                    typeName: Self.sourceTypeText(for: source.sourceType),
                    calendars: calendars
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        availableCalendarSources = sources

        let availableIDs = allAvailableCalendarIDs
        if usesAutomaticCalendarSelection {
            selectedCalendarIDs = availableIDs
            persistCalendarSelection()
            return
        }

        let retainedIDs = selectedCalendarIDs.intersection(availableIDs)
        if retainedIDs != selectedCalendarIDs {
            selectedCalendarIDs = retainedIDs
            persistCalendarSelection()
        }
    }

    private func selectedEventCalendars() -> [EKCalendar] {
        eventStore.refreshSourcesIfNecessary()
        let selectedIDs = selectedCalendarIDs
        return eventStore.calendars(for: .event)
            .filter { selectedIDs.contains($0.calendarIdentifier) }
    }

    private func persistCalendarSelection() {
        defaults.set(Array(selectedCalendarIDs).sorted(), forKey: selectedCalendarIDsKey)
        defaults.set(usesAutomaticCalendarSelection, forKey: automaticCalendarSelectionKey)
    }

    private static func isFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess || isLegacyAuthorized(status)
    }

    private static func isLegacyAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        status.rawValue == 3
    }

    private static func sourceTypeText(for type: EKSourceType) -> String {
        switch type {
        case .local:
            return "이 기기"
        case .exchange:
            return "Exchange"
        case .calDAV:
            return "계정"
        case .mobileMe:
            return "iCloud"
        case .subscribed:
            return "구독"
        case .birthdays:
            return "생일"
        @unknown default:
            return "캘린더"
        }
    }

    private static func statusText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess:
            return "허용됨"
        case .writeOnly:
            return "쓰기만 허용"
        case .denied:
            return "거부됨"
        case .restricted:
            return "제한됨"
        case .notDetermined:
            return "확인 필요"
        default:
            return isLegacyAuthorized(status) ? "허용됨" : "확인 필요"
        }
    }

    private static func calendarSettingsInstruction() -> String {
        #if os(macOS)
        return "macOS에서는 거부된 권한창을 앱이 다시 띄울 수 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 캘린더에서 정리시간을 허용하세요."
        #elseif os(iOS)
        return "설정 > 정리시간 > 캘린더에서 전체 접근을 허용하세요."
        #else
        return "이 기기의 설정에서 정리시간 캘린더 접근을 허용하세요."
        #endif
    }
}
