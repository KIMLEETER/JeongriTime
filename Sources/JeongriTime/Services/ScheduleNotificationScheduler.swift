import Foundation
import UserNotifications

struct ScheduleNotificationCandidate: Identifiable, Hashable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

enum ScheduleNotificationScheduler {
    private static let identifierPrefix = "jeongritime.schedule."
    private static let maximumScheduledNotifications = 64

    @MainActor
    static func candidates(from store: ScheduleStore, calendar: Calendar = .autoupdatingCurrent) -> [ScheduleNotificationCandidate] {
        let startOfToday = calendar.startOfDay(for: store.now)
        let currentWeekday = calendar.component(.weekday, from: startOfToday)
        let remainingOffsetsInThisWeek = 0...max(0, 7 - currentWeekday)

        let scheduledCandidates = remainingOffsetsInThisWeek.flatMap { offset -> [ScheduleNotificationCandidate] in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                return []
            }

            let day = Weekday.from(date: date, calendar: calendar)
            return store.blocks(for: day).flatMap { block in
                candidates(for: block, on: date, now: store.now, calendar: calendar)
            }
        }

        return Array(scheduledCandidates.sorted { $0.fireDate < $1.fireDate }.prefix(maximumScheduledNotifications))
    }

    private static func candidates(
        for block: ScheduleBlock,
        on date: Date,
        now: Date,
        calendar: Calendar
    ) -> [ScheduleNotificationCandidate] {
        guard !block.isFree else {
            return []
        }

        var output: [ScheduleNotificationCandidate] = []
        let dayStart = calendar.startOfDay(for: date)

        func append(idSuffix: String, minute: Int, title: String, body: String) {
            guard minute >= 0, minute <= 24 * 60,
                  let fireDate = calendar.date(byAdding: .minute, value: minute, to: dayStart),
                  fireDate > now
            else {
                return
            }

            output.append(
                ScheduleNotificationCandidate(
                    id: "\(identifierPrefix)\(block.id).\(idSuffix)",
                    fireDate: fireDate,
                    title: title,
                    body: body
                )
            )
        }

        if block.displayCategory == .sleep {
            if block.startMinute > 0 {
                append(
                    idSuffix: "sleep-start-30",
                    minute: block.startMinute - 30,
                    title: "곧 취침 시간",
                    body: "30분 뒤 \(block.title)이 시작됩니다."
                )
            }

            if block.endMinute < 24 * 60 {
                append(
                    idSuffix: "sleep-end",
                    minute: block.endMinute,
                    title: "기상 시간",
                    body: "\(block.title)이 끝났습니다. 다음 블록을 확인하세요."
                )
            }

            return output
        }

        switch block.displayCategory {
        case .movement:
            append(
                idSuffix: "before-10",
                minute: block.startMinute - 10,
                title: "곧 이동",
                body: "10분 뒤 \(block.title)이 시작됩니다."
            )
        case .classTime, .chapel, .language:
            append(
                idSuffix: "before-10",
                minute: block.startMinute - 10,
                title: "곧 \(block.displayCategory.displayName)",
                body: "10분 뒤 \(block.title)이 시작됩니다."
            )
        case .lab, .church, .club, .preparation, .planned, .meal, .other:
            append(
                idSuffix: "start",
                minute: block.startMinute,
                title: "\(block.title) 시작",
                body: "\(block.intervalText) · \(block.durationText)"
            )
        case .free, .sleep:
            break
        }

        return output
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    static func authorizationStatusText() async -> String {
        switch await authorizationStatus() {
        case .notDetermined:
            return "아직 허용하지 않음"
        case .denied:
            return "거부됨"
        case .authorized:
            return "허용됨"
        case .provisional:
            return "임시 허용"
        #if os(iOS)
        case .ephemeral:
            return "일시 허용"
        #endif
        @unknown default:
            return "알 수 없음"
        }
    }

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    @MainActor
    @discardableResult
    static func synchronize(store: ScheduleStore) async throws -> Int {
        let candidates = candidates(from: store)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existingIDs)

        for candidate in candidates {
            try await center.add(request(from: candidate))
        }

        return candidates.count
    }

    @MainActor
    static func synchronizeIfAuthorized(store: ScheduleStore) async {
        let status = await authorizationStatus()
        guard isSchedulingAllowed(status) else {
            return
        }

        _ = try? await synchronize(store: store)
    }

    private static func isSchedulingAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional:
            return true
        #if os(iOS)
        case .ephemeral:
            return true
        #endif
        default:
            return false
        }
    }

    private static func request(from candidate: ScheduleNotificationCandidate) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        content.categoryIdentifier = "schedule-transition"

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
    }
}
