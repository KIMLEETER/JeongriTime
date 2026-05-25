import SwiftUI

struct ScheduleHubView: View {
    @State private var mode: ScheduleHubMode = .free

    var body: some View {
        VStack(spacing: 0) {
            ScheduleHubHeader(mode: $mode)

            Group {
                switch mode {
                case .free:
                    DayTimelineView(showsTitle: false)
                case .week:
                    WeekPlannerView(showsTitle: false)
                case .management:
                    TimetableSettingsView(showsTitle: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("시간표")
    }
}

private enum ScheduleHubMode: String, CaseIterable, Identifiable {
    case free = "빈시간"
    case week = "주간"
    case management = "관리"

    var id: String { rawValue }
}

private struct ScheduleHubHeader: View {
    @Binding var mode: ScheduleHubMode

    var body: some View {
        #if os(macOS)
        HStack(alignment: .center, spacing: 16) {
            Text("시간표")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            ScheduleHubModeSelector(mode: $mode)
                .frame(width: 300)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 4)
        .background(AppTheme.background)
        #else
        ScheduleHubModeSelector(mode: $mode)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(AppTheme.background)
        #endif
    }
}

private struct ScheduleHubModeSelector: View {
    @Binding var mode: ScheduleHubMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleHubMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mode == item ? AppTheme.ink : AppTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(mode == item ? AppTheme.panel : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .decorativeStroke(
                    RoundedRectangle(cornerRadius: 7, style: .continuous),
                    color: mode == item ? AppTheme.line : Color.clear
                )
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(mode == item ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .decorativeStroke(
            RoundedRectangle(cornerRadius: 9, style: .continuous),
            color: AppTheme.line.opacity(0.75)
        )
    }
}

struct WeekPlannerView: View {
    @EnvironmentObject private var store: ScheduleStore
    private let showsTitle: Bool

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
    }

    var body: some View {
        ResponsiveScroll(maximumWidth: 1120) { width in
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                if showsTitle {
                    Text("주간")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
                #endif

                LazyVGrid(columns: summaryColumns(for: width), spacing: 12) {
                    ForEach(Weekday.allCases) { day in
                        DaySummaryPanel(day: day)
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        if width < 680 {
                            Text("요일별 블록")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            DaySelector(selection: $store.selectedDay)
                        } else {
                            HStack {
                                Text("요일별 블록")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)

                                Spacer()

                                DaySelector(selection: $store.selectedDay)
                                    .frame(maxWidth: 360)
                            }
                        }

                        ForEach(store.blocks(for: store.selectedDay)) { block in
                            CompactBlockRow(block: block)
                        }
                    }
                }
            }
        }
        .navigationTitle(showsTitle ? "주간" : "시간표")
    }

    private func summaryColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        if width >= 1030 {
            count = 4
        } else if width >= 720 {
            count = 3
        } else if width >= 460 {
            count = 2
        } else {
            count = 1
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

private struct DaySummaryPanel: View {
    @EnvironmentObject private var store: ScheduleStore
    let day: Weekday

    var body: some View {
        let free = store.freeMinutes(for: day)
        let planned = store.plannedMinutes(for: day)
        let fixed = store.fixedMinutes(for: day)
        let missing = store.engine.missingItems(for: day)
            .filter { !store.resolvedMissingIDs.contains($0.id) }
            .count

        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(day.longName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if missing > 0 {
                        Label("\(missing)", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }

                DayBalanceBar(free: free, planned: planned, fixed: fixed)

                VStack(spacing: 8) {
                    summaryRow("빈 시간", TimeFormatter.compactDuration(free), color: .green)
                    summaryRow("계획한 시간", TimeFormatter.compactDuration(planned), color: ScheduleCategory.planned.tint)
                    summaryRow("이미 쓰는 시간", TimeFormatter.compactDuration(fixed), color: AppTheme.focus)
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct DayBalanceBar: View {
    let free: Int
    let planned: Int
    let fixed: Int

    var body: some View {
        GeometryReader { proxy in
            let total = max(free + planned + fixed, 1)
            HStack(spacing: 2) {
                segment(width: proxy.size.width, minutes: fixed, total: total, color: AppTheme.focus.opacity(0.65))
                segment(width: proxy.size.width, minutes: planned, total: total, color: ScheduleCategory.planned.tint)
                segment(width: proxy.size.width, minutes: free, total: total, color: .green)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private func segment(width: CGFloat, minutes: Int, total: Int, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(minutes == 0 ? 0 : 4, width * CGFloat(minutes) / CGFloat(total)))
    }
}

struct StatisticsView: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        let stats = store.weeklyUsageStatistics()

        ResponsiveScroll(maximumWidth: 980) { width in
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                Text("통계")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                #endif

                UsageOverviewCard(stats: stats)

                LazyVGrid(columns: metricColumns(for: width), spacing: 12) {
                    MetricTile(
                        title: "이번 주 계획한 빈시간",
                        value: TimeFormatter.compactDuration(stats.plannedMinutes),
                        symbolName: "calendar.badge.checkmark",
                        tint: ScheduleCategory.planned.tint
                    )

                    MetricTile(
                        title: "이번 주 남은 빈시간",
                        value: TimeFormatter.compactDuration(stats.remainingFreeMinutes),
                        symbolName: "sparkles",
                        tint: AppTheme.free
                    )

                    MetricTile(
                        title: "가장 많이 비는 요일",
                        value: topFreeDayText(stats),
                        symbolName: "calendar",
                        tint: AppTheme.focus
                    )
                }

                DayUsageStatisticsSection(stats: stats)

                LazyVGrid(columns: breakdownColumns(for: width), spacing: 12) {
                    StatisticsBreakdownSection(
                        title: "무엇으로 채웠나",
                        rows: categoryRows(from: stats),
                        emptyText: "아직 계획으로 채운 빈 시간이 없습니다."
                    )

                    StatisticsBreakdownSection(
                        title: "어디에서 채웠나",
                        rows: placeRows(from: stats),
                        emptyText: "장소가 지정된 계획이 없습니다."
                    )
                }
            }
        }
        .navigationTitle("통계")
    }

    private func metricColumns(for width: CGFloat) -> [GridItem] {
        let count = width >= 760 ? 3 : (width >= 500 ? 2 : 1)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private func breakdownColumns(for width: CGFloat) -> [GridItem] {
        let count = width >= 760 ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private func topFreeDayText(_ stats: WeeklyUsageStatistics) -> String {
        guard let day = stats.topFreeDay else {
            return "없음"
        }
        return "\(day.day.rawValue) \(TimeFormatter.compactDuration(day.freeMinutes))"
    }

    private func categoryRows(from stats: WeeklyUsageStatistics) -> [StatisticsBreakdownRowData] {
        ScheduleCategory.allCases.compactMap { category in
            let minutes = stats.categoryMinutes[category, default: 0]
            guard minutes > 0 else {
                return nil
            }
            return StatisticsBreakdownRowData(
                id: category.id,
                title: category.displayName,
                minutes: minutes,
                symbolName: category.symbolName,
                tint: category.tint
            )
        }
        .sorted { $0.minutes > $1.minutes }
    }

    private func placeRows(from stats: WeeklyUsageStatistics) -> [StatisticsBreakdownRowData] {
        SchedulePlace.allCases.compactMap { place in
            let minutes = stats.placeMinutes[place, default: 0]
            guard minutes > 0 else {
                return nil
            }
            return StatisticsBreakdownRowData(
                id: place.id,
                title: place.rawValue,
                minutes: minutes,
                symbolName: place.symbolName,
                tint: place.tint
            )
        }
        .sorted { $0.minutes > $1.minutes }
    }
}

private struct UsageOverviewCard: View {
    let stats: WeeklyUsageStatistics

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("빈시간 사용률")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)

                        Text("계획으로 채운 빈시간 기준")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }

                    Spacer()

                    Text(percentText(stats.usageRatio))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(ScheduleCategory.planned.tint)
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    let plannedWidth = proxy.size.width * CGFloat(stats.usageRatio)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.secondaryBackground)

                        Capsule()
                            .fill(ScheduleCategory.planned.tint)
                            .frame(width: plannedWidth)
                    }
                }
                .frame(height: 14)

                HStack {
                    Label(TimeFormatter.duration(stats.plannedMinutes), systemImage: "checkmark.circle")
                        .foregroundStyle(ScheduleCategory.planned.tint)

                    Spacer()

                    Label(TimeFormatter.duration(stats.remainingFreeMinutes), systemImage: "sparkles")
                        .foregroundStyle(AppTheme.free)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct DayUsageStatisticsSection: View {
    let stats: WeeklyUsageStatistics

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("요일별 빈시간")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                VStack(spacing: 10) {
                    ForEach(stats.dayStats) { day in
                        DayUsageStatisticsRow(day: day)
                    }
                }
            }
        }
    }
}

private struct DayUsageStatisticsRow: View {
    let day: DayUsageStatistic

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(day.day.rawValue)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                DayUsageBar(day: day)

                HStack(spacing: 10) {
                    Text("계획 \(TimeFormatter.compactDuration(day.plannedMinutes))")
                        .foregroundStyle(ScheduleCategory.planned.tint)
                    Text("남음 \(TimeFormatter.compactDuration(day.freeMinutes))")
                        .foregroundStyle(AppTheme.muted)
                }
                .font(.caption.monospacedDigit())
            }

            Text(percentText(day.usageRatio))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .frame(width: 46, alignment: .trailing)
        }
    }
}

private struct DayUsageBar: View {
    let day: DayUsageStatistic

    var body: some View {
        GeometryReader { proxy in
            let total = max(day.schedulableMinutes, 1)
            HStack(spacing: 2) {
                segment(width: proxy.size.width, minutes: day.plannedMinutes, total: total, color: ScheduleCategory.planned.tint)
                segment(width: proxy.size.width, minutes: day.freeMinutes, total: total, color: AppTheme.free.opacity(0.55))
            }
        }
        .frame(height: 10)
        .background(AppTheme.secondaryBackground)
        .clipShape(Capsule())
    }

    private func segment(width: CGFloat, minutes: Int, total: Int, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(minutes == 0 ? 0 : 4, width * CGFloat(minutes) / CGFloat(total)))
    }
}

private struct StatisticsBreakdownSection: View {
    let title: String
    let rows: [StatisticsBreakdownRowData]
    let emptyText: String

    private var maxMinutes: Int {
        max(rows.map(\.minutes).max() ?? 1, 1)
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                if rows.isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in
                            StatisticsBreakdownRow(row: row, maxMinutes: maxMinutes)
                        }
                    }
                }
            }
        }
    }
}

private struct StatisticsBreakdownRowData: Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let symbolName: String
    let tint: Color
}

private struct StatisticsBreakdownRow: View {
    let row: StatisticsBreakdownRowData
    let maxMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: row.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(row.tint)
                    .frame(width: 18, height: 18)

                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Spacer()

                Text(TimeFormatter.compactDuration(row.minutes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(row.tint.opacity(0.20))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(row.tint)
                            .frame(width: proxy.size.width * CGFloat(row.minutes) / CGFloat(maxMinutes))
                    }
            }
            .frame(height: 8)
        }
    }
}

private func percentText(_ ratio: Double) -> String {
    "\(Int((ratio * 100).rounded()))%"
}

private enum TimetableSettingsSheet: Identifiable {
    case editTimetable(ScheduleBlock)
    case todayOverride(ScheduleBlock)

    var id: String {
        switch self {
        case .editTimetable(let block):
            return "edit-\(block.id)"
        case .todayOverride(let block):
            return "today-\(block.id)"
        }
    }
}

struct TimetableSettingsView: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var activeSheet: TimetableSettingsSheet?
    @State private var sleepStart = TimeFormatter.minutes(22, 0)
    @State private var sleepEnd = TimeFormatter.minutes(8, 0)
    @State private var message: String?
    private let showsTitle: Bool

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
    }

    var body: some View {
        ResponsiveScroll(maximumWidth: 980) { _ in
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                if showsTitle {
                    Text("시간표")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
                #endif

                DaySelector(selection: $store.selectedDay)

                sleepSection
                timetableSection
                weeklyPlanSection
                oncePlanSection
            }
        }
        .navigationTitle("시간표")
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editTimetable(let block):
                TimetableEditorSheet(block: block)
                    .environmentObject(store)
            case .todayOverride(let block):
                TodayOverrideEditorSheet(block: block)
                    .environmentObject(store)
            }
        }
    }

    private var sleepSection: some View {
        ManagementSection(title: "수면 시간", count: nil) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    TimePickerRow(title: "취침", minute: $sleepStart)
                    TimePickerRow(title: "기상", minute: $sleepEnd)
                }

                HStack {
                    Text(sleepDurationText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ScheduleCategory.sleep.tint)

                    Spacer()

                    Button {
                        if store.addSleepSchedule(
                            day: store.selectedDay,
                            startMinute: sleepStart,
                            endMinute: sleepEnd,
                            title: "수면"
                        ) {
                            message = "수면 시간을 시간표에 추가했습니다."
                        } else {
                            message = "겹치는 일정이 있어 수면 시간을 추가하지 못했습니다."
                        }
                    } label: {
                        Label("수면 추가", systemImage: ScheduleCategory.sleep.symbolName)
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.sleep.tint, isProminent: true))
                }

                if let message {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var timetableSection: some View {
        let blocks = store.timetableBlocks(for: store.selectedDay)

        return ManagementSection(title: "고정 시간표", count: blocks.count) {
            if blocks.isEmpty {
                EmptyManagementRow(text: "고정된 시간이 없습니다.")
            } else {
                ForEach(blocks) { block in
                    ManagedScheduleRow(
                        title: block.title,
                        interval: block.intervalText,
                        duration: block.durationText,
                        badge: block.displayCategory.displayName,
                        tint: block.displayCategory.tint,
                        canEdit: true,
                        canAdjustToday: true,
                        canDelete: true,
                        onEdit: { activeSheet = .editTimetable(block) },
                        onAdjustToday: { activeSheet = .todayOverride(block) }
                    ) {
                        store.deleteTimetableBlock(id: block.id)
                    }
                }
            }
        }
    }

    private var weeklyPlanSection: some View {
        let entries = store.entries(for: store.selectedDay, kind: .weeklyPlan)

        return ManagementSection(title: "반복 계획", count: entries.count) {
            if entries.isEmpty {
                EmptyManagementRow(text: "반복 계획이 없습니다.")
            } else {
                ForEach(entries) { entry in
                    ManagedScheduleRow(
                        title: entry.title,
                        interval: "\(TimeFormatter.clock(entry.startMinute))-\(TimeFormatter.clock(entry.endMinute))",
                        duration: TimeFormatter.duration(entry.durationMinutes),
                        badge: entry.sourceBlockID == nil ? entry.kindText : "오늘만 조정",
                        tint: entry.category.tint,
                        canEdit: false,
                        canDelete: true
                    ) {
                        store.deletePlan(id: entry.id)
                    }
                }
            }
        }
    }

    private var oncePlanSection: some View {
        let entries = store.entries(for: store.selectedDay, kind: .once)

        return ManagementSection(title: "이번 주 계획", count: entries.count) {
            if entries.isEmpty {
                EmptyManagementRow(text: "이번 주 계획이 없습니다.")
            } else {
                ForEach(entries) { entry in
                    ManagedScheduleRow(
                        title: entry.title,
                        interval: "\(TimeFormatter.clock(entry.startMinute))-\(TimeFormatter.clock(entry.endMinute))",
                        duration: TimeFormatter.duration(entry.durationMinutes),
                        badge: entry.kindText,
                        tint: entry.category.tint,
                        canEdit: false,
                        canDelete: true
                    ) {
                        store.deletePlan(id: entry.id)
                    }
                }
            }
        }
    }

    private var sleepDurationText: String {
        if sleepStart < sleepEnd {
            return TimeFormatter.duration(sleepEnd - sleepStart)
        }
        return TimeFormatter.duration((24 * 60 - sleepStart) + sleepEnd)
    }

}

struct AppSettingsView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var driveSync: GoogleDriveSyncService
    @Environment(\.openURL) private var openURL
    @StateObject private var calendarBridge = CalendarBridge()
    @State private var googleClientID = ""
    @State private var showGoogleAdvanced = false
    @State private var notificationStatus = "확인 중"
    @State private var notificationMessage: String?

    private var settingButtonColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: 10)]
    }

    var body: some View {
        ResponsiveScroll(maximumWidth: 980) { _ in
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                Text("설정")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                #endif

                googleDriveSyncSection
                calendarSection
                notificationSection
                missingInfoSection
                deviceValidationSection
            }
        }
        .navigationTitle("설정")
        .task {
            googleClientID = driveSync.clientID
            showGoogleAdvanced = driveSync.clientID.isEmpty
            await refreshNotificationStatus()
        }
    }

    private var googleDriveSyncSection: some View {
        ManagementSection(title: "Google 동기화", count: nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Drive")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(googleDriveDetailText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(driveSync.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !driveSync.isConfigured {
                    EmptyManagementRow(text: "이 개발 빌드는 Google OAuth 앱 등록값이 한 번 필요합니다. 정식 앱처럼 만들 때는 이 값을 앱에 내장해서 Google 로그인만 보이게 할 수 있습니다.")
                }

                StatusMetricGrid(metrics: googleDriveMetrics)

                LazyVGrid(columns: settingButtonColumns, alignment: .leading, spacing: 10) {
                    Button {
                        Task { await driveSync.signInWithGoogle() }
                    } label: {
                        Label("Google 로그인", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                    .disabled(!driveSync.isConfigured)

                    Button {
                        Task { await driveSync.synchronize(store: store) }
                    } label: {
                        Label("동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.planned.tint))
                    .disabled(!driveSync.isConfigured || !driveSync.isAuthorized || driveSync.isSynchronizing)

                    if driveSync.isAuthorized {
                        Button {
                            driveSync.signOut()
                        } label: {
                            Label("연결 해제", systemImage: "xmark.circle")
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
                    }
                }

                if let lastSyncDate = driveSync.lastSyncDate {
                    Text("마지막 동기화 \(lastSyncDate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }

                DisclosureGroup("고급 Google 설정", isExpanded: $showGoogleAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Google OAuth Client ID", text: $googleClientID)
                            .textFieldStyle(.plain)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .background(AppTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)

                        LazyVGrid(columns: settingButtonColumns, alignment: .leading, spacing: 10) {
                            Button {
                                driveSync.saveClientID(googleClientID)
                            } label: {
                                Label("저장", systemImage: "key")
                            }
                            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))

                            Button {
                                Task { await driveSync.requestDeviceCode() }
                            } label: {
                                Label("코드로 로그인", systemImage: "number.square")
                            }
                            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
                            .disabled(!driveSync.isConfigured)
                        }

                        if let redirectURI = driveSync.redirectURIText {
                            Text("리디렉트 URI \(redirectURI)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

                if let userCode = driveSync.userCode, let verificationURL = driveSync.verificationURL {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(userCode)
                                .font(.title3.weight(.bold).monospaced())
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Button {
                                openURL(verificationURL)
                            } label: {
                                Label("Google 열기", systemImage: "safari")
                            }
                            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent))

                            Button {
                                Task { await driveSync.pollForToken() }
                            } label: {
                                Label("승인 확인", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.planned.tint, isProminent: true))
                        }

                        Text(verificationURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                    .padding(11)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let driveMessage = driveSync.message {
                    Text(driveMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var calendarSection: some View {
        let pendingCount = store.calendarInboxItems.count

        return ManagementSection(title: "캘린더 연결", count: pendingCount) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ScheduleCategory.classTime.tint)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple/Google 캘린더")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(calendarDetailText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(calendarBridge.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                LazyVGrid(columns: settingButtonColumns, alignment: .leading, spacing: 10) {
                    Button {
                        Task { await calendarBridge.requestAccessOrShowInstructions() }
                    } label: {
                        Label(calendarBridge.accessActionTitle, systemImage: calendarBridge.accessActionSystemImage)
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.classTime.tint))

                    Button {
                        Task { await calendarBridge.importCurrentWeek(into: store) }
                    } label: {
                        Label("캘린더 가져오기", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                }

                StatusMetricGrid(metrics: calendarMetrics)

                if calendarBridge.showsAccessInstructions {
                    CalendarAccessGuideView(
                        onOpenSettings: {
                            calendarBridge.openSystemCalendarSettings()
                        },
                        onRefresh: {
                            calendarBridge.refreshStatus()
                        }
                    )
                }

                CalendarSourceSelectionView(
                    sources: calendarBridge.availableCalendarSources,
                    selectedIDs: calendarBridge.selectedCalendarIDs,
                    selectedCount: calendarBridge.selectedCalendarCount,
                    totalCount: calendarBridge.availableCalendarCount,
                    onToggleCalendar: { calendarID, isSelected in
                        calendarBridge.setCalendarSelection(calendarID: calendarID, isSelected: isSelected)
                    },
                    onToggleSource: { sourceID, isSelected in
                        calendarBridge.setSourceSelection(sourceID: sourceID, isSelected: isSelected)
                    },
                    onSelectAll: {
                        calendarBridge.selectAllCalendars()
                    },
                    onClear: {
                        calendarBridge.clearCalendarSelection()
                    }
                )

                if let defaultCalendarTitle = calendarBridge.defaultCalendarTitle {
                    Text("새 계획은 기본 캘린더 \(defaultCalendarTitle)에 추가됩니다.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }

                if let bridgeMessage = calendarBridge.message {
                    Text(bridgeMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }

                if pendingCount == 0 {
                    EmptyManagementRow(text: "처리할 새 캘린더 일정이 없습니다.")
                } else {
                    Button {
                        store.selectedSection = .missing
                    } label: {
                        SettingsNavigationRow(
                            systemImage: "tray.full",
                            title: "확인 필요로 이동",
                            detail: "\(pendingCount)개의 새 일정을 오늘만 조정, 이번만, 매주, 시간표 중 하나로 정리합니다.",
                            tint: ScheduleCategory.classTime.tint
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notificationSection: some View {
        let count = ScheduleNotificationScheduler.candidates(from: store).count

        return ManagementSection(title: "알림", count: count) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("전환 시점 알림")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("이번 주 남은 시간표에서 이동, 수업, 업무, 수면 전환을 이 기기의 로컬 알림으로 예약합니다.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(notificationStatus)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                LazyVGrid(columns: settingButtonColumns, alignment: .leading, spacing: 10) {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        Label("알림 허용", systemImage: "bell")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent))

                    Button {
                        Task { await synchronizeNotifications() }
                    } label: {
                        Label("동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.planned.tint, isProminent: true))
                }

                if let notificationMessage {
                    Text(notificationMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await ScheduleNotificationScheduler.authorizationStatusText()
    }

    private func requestNotifications() async {
        do {
            if try await ScheduleNotificationScheduler.requestAuthorization() {
                await synchronizeNotifications()
            } else {
                notificationMessage = "알림 권한이 허용되지 않았습니다."
            }
        } catch {
            notificationMessage = "알림 권한 요청에 실패했습니다."
        }
        await refreshNotificationStatus()
    }

    private func synchronizeNotifications() async {
        do {
            let count = try await ScheduleNotificationScheduler.synchronize(store: store)
            notificationMessage = "\(count)개의 전환 알림을 이 기기에 예약했습니다."
        } catch {
            notificationMessage = "알림 예약에 실패했습니다."
        }
        await refreshNotificationStatus()
    }

    private var missingInfoSection: some View {
        ManagementSection(title: "확인 필요", count: store.checkNeededCount) {
            #if os(macOS)
            Button {
                store.selectedSection = .missing
            } label: {
                SettingsNavigationRow(
                    systemImage: "exclamationmark.circle",
                    title: "확인 필요",
                    detail: "캘린더에서 들어온 새 일정과 아직 정하지 않은 항목을 봅니다.",
                    tint: AppTheme.focus
                )
            }
            .buttonStyle(.plain)
            #else
            NavigationLink {
                MissingInfoView()
                    .environmentObject(store)
            } label: {
                SettingsNavigationRow(
                    systemImage: "exclamationmark.circle",
                    title: "확인 필요",
                    detail: "캘린더에서 들어온 새 일정과 아직 정하지 않은 항목을 봅니다.",
                    tint: AppTheme.focus
                )
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private var deviceValidationSection: some View {
        ManagementSection(title: "연동 점검", count: nil) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(validationItems) { item in
                    ValidationChecklistRow(item: item)
                }
            }
        }
    }

    private var googleDriveDetailText: String {
        "계획, 시간표, 확인 상태를 Google Drive로 맞춥니다."
    }

    private var calendarDetailText: String {
        "선택한 Apple/Google 캘린더의 새 일정을 가져와 확인 필요에 모읍니다."
    }

    private var googleDriveMetrics: [StatusMetric] {
        var metrics = [
            StatusMetric(title: "로그인", value: driveSync.isAuthorized ? "완료" : (driveSync.isConfigured ? "필요" : "설정 필요")),
            StatusMetric(title: "상태", value: driveSync.isSynchronizing ? "진행 중" : driveSync.statusText),
            StatusMetric(title: "마지막", value: lastDriveSyncText),
            StatusMetric(title: "확인 필요", value: "\(store.calendarInboxItems.count)개")
        ]

        if let driveMessage = driveSync.message, driveSync.statusText == "동기화 실패" {
            metrics.append(StatusMetric(title: "실패 사유", value: driveMessage))
        }

        return metrics
    }

    private var calendarMetrics: [StatusMetric] {
        [
            StatusMetric(title: "권한", value: calendarBridge.statusText),
            StatusMetric(title: "선택", value: "\(calendarBridge.selectedCalendarCount)/\(calendarBridge.availableCalendarCount)개"),
            StatusMetric(title: "새 일정", value: "\(store.calendarInboxItems.count)개"),
            StatusMetric(title: "시간 겹침", value: "\(calendarConflictCount)개"),
            StatusMetric(title: "가져오기", value: calendarImportText)
        ]
    }

    private var calendarConflictCount: Int {
        store.calendarInboxItems.filter { !store.canAcceptCalendarInboxItem(id: $0.id) }.count
    }

    private var calendarImportText: String {
        if let message = calendarBridge.message {
            return message
        }
        if calendarBridge.importedCalendarTitles.isEmpty {
            return "실행 전"
        }
        return "\(calendarBridge.importedCalendarTitles.count)개 캘린더"
    }

    private var lastDriveSyncText: String {
        guard let lastSyncDate = driveSync.lastSyncDate else {
            return "아직 없음"
        }
        return lastSyncDate.formatted(date: .omitted, time: .shortened)
    }

    private var validationItems: [ValidationChecklistItem] {
        var items = [
            ValidationChecklistItem(
                title: "Google 로그인",
                status: driveSync.isAuthorized ? "완료" : (driveSync.isConfigured ? "로그인 필요" : "Client ID 필요"),
                isComplete: driveSync.isAuthorized
            ),
            ValidationChecklistItem(
                title: "Drive 동기화",
                status: driveSync.lastSyncDate == nil ? "아직 없음" : lastDriveSyncText,
                isComplete: driveSync.lastSyncDate != nil
            ),
            ValidationChecklistItem(
                title: "캘린더 권한",
                status: calendarBridge.statusText,
                isComplete: calendarBridge.statusText == "허용됨"
            ),
            ValidationChecklistItem(
                title: "캘린더 가져오기",
                status: calendarImportText,
                isComplete: !calendarBridge.importedCalendarTitles.isEmpty || calendarBridge.message != nil
            ),
            ValidationChecklistItem(
                title: "새 일정 처리",
                status: store.calendarInboxItems.isEmpty ? "대기 없음" : "\(store.calendarInboxItems.count)개 남음",
                isComplete: store.calendarInboxItems.isEmpty
            )
        ]

        let notificationAllowed = notificationStatus == "허용됨" || notificationStatus == "임시 허용" || notificationStatus == "일시 허용"
        items.append(
            ValidationChecklistItem(
                title: "알림 권한",
                status: notificationStatus,
                isComplete: notificationAllowed
            )
        )
        items.append(
            ValidationChecklistItem(
                title: "알림 예약",
                status: "\(ScheduleNotificationScheduler.candidates(from: store).count)개 후보",
                isComplete: notificationAllowed
            )
        )

        return items
    }
}

private struct StatusMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct StatusMetricGrid: View {
    let metrics: [StatusMetric]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 128), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(metrics) { metric in
                StatusMetricCard(metric: metric)
            }
        }
    }
}

private struct StatusMetricCard: View {
    let metric: StatusMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.muted)

            Text(metric.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
    }
}

private struct CalendarAccessGuideView: View {
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ScheduleCategory.classTime.tint)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text("캘린더 권한을 직접 켜야 합니다")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(Self.instructionText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], alignment: .leading, spacing: 10) {
                Button {
                    onOpenSettings()
                } label: {
                    Label(Self.settingsButtonTitle, systemImage: "gearshape")
                }
                .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.classTime.tint))

                Button {
                    onRefresh()
                } label: {
                    Label("다시 확인", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
            }
        }
        .padding(11)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
    }

    private static var instructionText: String {
        #if os(macOS)
        "macOS에서는 한 번 거부한 캘린더 권한창을 앱이 다시 띄울 수 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 캘린더에서 정리시간을 켜세요."
        #else
        "설정 > 정리시간 > 캘린더에서 전체 접근을 허용하세요."
        #endif
    }

    private static var settingsButtonTitle: String {
        #if os(macOS)
        "시스템 설정 열기"
        #else
        "설정 열기"
        #endif
    }
}

private struct CalendarSourceSelectionView: View {
    let sources: [CalendarSourceChoice]
    let selectedIDs: Set<String>
    let selectedCount: Int
    let totalCount: Int
    let onToggleCalendar: (String, Bool) -> Void
    let onToggleSource: (String, Bool) -> Void
    let onSelectAll: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("가져올 캘린더")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(totalCount == 0 ? "캘린더 권한을 허용하면 계정 목록이 보입니다." : "\(selectedCount)개 선택됨")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Button("전체") {
                    onSelectAll()
                }
                .buttonStyle(CompactSettingsButtonStyle())
                .disabled(totalCount == 0 || selectedCount == totalCount)

                Button("해제") {
                    onClear()
                }
                .buttonStyle(CompactSettingsButtonStyle())
                .disabled(selectedCount == 0)
            }

            if sources.isEmpty {
                EmptyManagementRow(text: "아직 가져올 캘린더를 읽지 못했습니다. 캘린더 허용을 먼저 누르세요.")
            } else {
                VStack(spacing: 8) {
                    ForEach(sources) { source in
                        CalendarAccountSelectionCard(
                            source: source,
                            selectedIDs: selectedIDs,
                            onToggleCalendar: onToggleCalendar,
                            onToggleSource: onToggleSource
                        )
                    }
                }
            }
        }
    }
}

private struct CalendarAccountSelectionCard: View {
    let source: CalendarSourceChoice
    let selectedIDs: Set<String>
    let onToggleCalendar: (String, Bool) -> Void
    let onToggleSource: (String, Bool) -> Void

    private var selectedCount: Int {
        source.calendarIDs.intersection(selectedIDs).count
    }

    private var isFullySelected: Bool {
        selectedCount == source.calendars.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(source.typeName) · \(selectedCount)/\(source.calendars.count)개")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Button(isFullySelected ? "계정 해제" : "계정 선택") {
                    onToggleSource(source.id, !isFullySelected)
                }
                .buttonStyle(CompactSettingsButtonStyle())
            }

            VStack(spacing: 6) {
                ForEach(source.calendars) { calendar in
                    Toggle(
                        isOn: Binding(
                            get: {
                                selectedIDs.contains(calendar.id)
                            },
                            set: { isSelected in
                                onToggleCalendar(calendar.id, isSelected)
                            }
                        )
                    ) {
                        Text(calendar.title)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .background(AppTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
                }
            }
        }
        .padding(12)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CompactSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(configuration.isPressed ? AppTheme.secondaryBackground : AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ValidationChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let status: String
    let isComplete: Bool
}

private struct ValidationChecklistRow: View {
    let item: ValidationChecklistItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isComplete ? Color.green : AppTheme.muted)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(11)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsNavigationRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(11)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ManagementSection<Content: View>: View {
    let title: String
    let count: Int?
    let content: Content

    init(title: String, count: Int?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.content = content()
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if let count {
                        Text("\(count)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                content
            }
        }
    }
}

private struct ManagedScheduleRow: View {
    let title: String
    let interval: String
    let duration: String
    let badge: String
    let tint: Color
    let canEdit: Bool
    let canAdjustToday: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onAdjustToday: () -> Void
    let onDelete: () -> Void

    init(
        title: String,
        interval: String,
        duration: String,
        badge: String,
        tint: Color,
        canEdit: Bool = false,
        canAdjustToday: Bool = false,
        canDelete: Bool,
        onEdit: @escaping () -> Void = {},
        onAdjustToday: @escaping () -> Void = {},
        onDelete: @escaping () -> Void
    ) {
        self.title = title
        self.interval = interval
        self.duration = duration
        self.badge = badge
        self.tint = tint
        self.canEdit = canEdit
        self.canAdjustToday = canAdjustToday
        self.canDelete = canDelete
        self.onEdit = onEdit
        self.onAdjustToday = onAdjustToday
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(AppTheme.ink)
                        .background(tint.opacity(0.16))
                        .clipShape(Capsule())
                }

                Text("\(interval) · \(duration)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            if canEdit {
                Button {
                    onEdit()
                } label: {
                    Label("수정", systemImage: "pencil")
                }
                .buttonStyle(ActionPillButtonStyle(tint: tint))
            }

            if canAdjustToday {
                Button {
                    onAdjustToday()
                } label: {
                    Label("오늘만 조정", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent))
            }

            if canDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.focus)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(11)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimetableEditorSheet: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    let block: ScheduleBlock
    @State private var title: String
    @State private var startMinute: Int
    @State private var endMinute: Int
    @State private var category: ScheduleCategory
    @State private var place: SchedulePlace
    @State private var placeEdited: Bool
    @State private var message: String?

    init(block: ScheduleBlock) {
        self.block = block
        _title = State(initialValue: block.title)
        _startMinute = State(initialValue: block.startMinute)
        _endMinute = State(initialValue: block.endMinute)
        _category = State(initialValue: block.displayCategory)
        _place = State(initialValue: block.displayPlace)
        _placeEdited = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("시간표 수정")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("이 항목을 내 시간표에 맞게 바꿉니다.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            TextField("제목", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, newValue in
                    if !placeEdited {
                        place = SchedulePlace.infer(title: newValue, category: category)
                    }
                }

            Picker("분류", selection: Binding(
                get: { category },
                set: {
                    category = $0
                    if !placeEdited {
                        place = SchedulePlace.infer(title: title, category: category)
                    }
                }
            )) {
                ForEach(ScheduleCategory.allCases.filter { $0 != .free && $0 != .planned }) { item in
                    Label(item.displayName, systemImage: item.symbolName).tag(item)
                }
            }

            SchedulePlacePicker(
                title: "장소",
                selection: Binding(
                    get: { place },
                    set: {
                        place = $0
                        placeEdited = true
                    }
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                TimePickerRow(title: "시작", minute: $startMinute)
                TimePickerRow(title: "종료", minute: $endMinute, allowsEndAtMidnight: true)
            }

            if let message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.focus)
            }

            HStack {
                Text(TimeFormatter.duration(endMinute - startMinute))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(category.tint)
                Spacer()
                Button("취소") {
                    dismiss()
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))

                Button {
                    if store.saveTimetableBlock(
                        originalID: block.id,
                        day: block.day,
                        startMinute: startMinute,
                        endMinute: endMinute,
                        title: title,
                        category: category,
                        place: place
                    ) {
                        dismiss()
                    } else {
                        message = "겹치는 시간이 있어 저장하지 못했습니다."
                    }
                } label: {
                    Label("저장", systemImage: "checkmark")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endMinute <= startMinute)
            }
        }
        .padding(22)
        .frame(minWidth: 400)
        .onChange(of: startMinute) { _, newValue in
            if endMinute <= newValue {
                endMinute = min(24 * 60, newValue + 5)
            }
        }
    }
}

private struct TimePickerRow: View {
    let title: String
    @Binding var minute: Int
    var allowsEndAtMidnight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            HStack(spacing: 7) {
                TimePartMenu(value: hourBinding, options: hourOptions, unit: "시")

                Text(":")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.muted)

                TimePartMenu(value: minuteBinding, options: minuteOptions, unit: "분")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hourOptions: [Int] {
        Array(0...(allowsEndAtMidnight ? 24 : 23))
    }

    private var minuteOptions: [Int] {
        if allowsEndAtMidnight && minute == 24 * 60 {
            return [0]
        }
        return stride(from: 0, through: 55, by: 5).map { $0 }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { min(minute / 60, 24) },
            set: { newHour in
                if allowsEndAtMidnight && newHour == 24 {
                    minute = 24 * 60
                } else {
                    minute = newHour * 60 + (minute == 24 * 60 ? 0 : minute % 60)
                }
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { minute == 24 * 60 ? 0 : minute % 60 },
            set: { newMinute in
                if allowsEndAtMidnight && minute == 24 * 60 {
                    minute = 24 * 60
                    return
                }
                let hour = min(minute / 60, 23)
                minute = hour * 60 + newMinute
            }
        )
    }
}

private struct TimePartMenu: View {
    @Binding var value: Int
    let options: [Int]
    let unit: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button("\(String(format: "%02d", option))\(unit)") {
                    value = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(String(format: "%02d", value))
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 28, alignment: .trailing)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyManagementRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
