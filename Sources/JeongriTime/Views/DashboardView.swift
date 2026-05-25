import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        let current = store.currentBlock(at: store.now)
        let next = nextScheduleItem(current: current)
        let remaining = store.remainingFreeMinutes(from: store.now)
        let totalFree = max(store.freeMinutes(for: current.day), 1)
        let planned = store.plannedMinutes(for: current.day)
        let fixed = store.fixedMinutes(for: current.day)
        let unresolvedCount = store.checkNeededCount

        ResponsiveScroll(maximumWidth: 1120) { width in
            VStack(alignment: .leading, spacing: 16) {
                header(day: current.day)

                if width >= 920 {
                    HStack(alignment: .top, spacing: 12) {
                        currentPanel(current: current, remaining: remaining, totalFree: totalFree)
                            .frame(maxWidth: .infinity)

                        todayOverviewPanel(
                            remaining: remaining,
                            totalFree: totalFree,
                            planned: planned,
                            fixed: fixed,
                            unresolvedCount: unresolvedCount
                        )
                        .frame(width: 360)
                    }
                } else {
                    currentPanel(current: current, remaining: remaining, totalFree: totalFree)

                    todayOverviewPanel(
                        remaining: remaining,
                        totalFree: totalFree,
                        planned: planned,
                        fixed: fixed,
                        unresolvedCount: unresolvedCount
                    )
                }

                if let next {
                    nextPanel(next)
                }

                if unresolvedCount > 0 {
                    missingPanel(count: unresolvedCount)
                }

                TodayBlockPreview(day: current.day)
            }
        }
        .navigationTitle("오늘")
    }

    private func currentPanel(current: ScheduleBlock, remaining: Int, totalFree: Int) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("지금")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)

                        Text(current.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                    }

                    Spacer()

                    CategoryBadge(category: current.category)
                }

                HStack(spacing: 12) {
                    Label(current.intervalText, systemImage: "clock")
                    Label(current.durationText, systemImage: "hourglass")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.muted)

                ProgressView(value: Double(remaining), total: Double(totalFree))
                    .tint(current.category == .free ? .green : AppTheme.accent)

                HStack {
                    Text("오늘 남은 빈 시간")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    Text(TimeFormatter.duration(remaining))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    private func todayOverviewPanel(
        remaining: Int,
        totalFree: Int,
        planned: Int,
        fixed: Int,
        unresolvedCount: Int
    ) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    overviewMetric(
                        title: "남은 빈 시간",
                        value: TimeFormatter.compactDuration(remaining),
                        symbolName: "sparkles",
                        tint: AppTheme.free
                    )

                    overviewMetric(
                        title: "다음 체크",
                        value: nextCheckpointText(),
                        symbolName: "timer",
                        tint: AppTheme.accent
                    )
                }

                Divider()

                VStack(spacing: 9) {
                    summaryLine("하루 빈 시간", TimeFormatter.compactDuration(totalFree), color: AppTheme.free)
                    summaryLine("계획한 시간", TimeFormatter.compactDuration(planned), color: ScheduleCategory.planned.tint)
                    summaryLine("이미 쓰는 시간", TimeFormatter.compactDuration(fixed), color: AppTheme.focus)
                    summaryLine("확인 필요", "\(unresolvedCount)개", color: .orange)
                }
            }
        }
    }

    private func overviewMetric(title: String, value: String, symbolName: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryLine(_ title: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func header(day: Weekday) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.longName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            Text(Date.now.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func nextPanel(_ next: DashboardNextScheduleItem) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: next.symbolName)
                    .font(.title2)
                    .foregroundStyle(next.tint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(next.caption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Text(next.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(next.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()
            }
        }
    }

    private func nextScheduleItem(current: ScheduleBlock) -> DashboardNextScheduleItem? {
        guard let occurrence = store.nextBlockOccurrence(after: store.now) else {
            return nil
        }

        let next = occurrence.block
        if current.displayCategory == .sleep,
           current.endMinute == 24 * 60,
           occurrence.dayOffset == 1,
           next.displayCategory == .sleep,
           next.startMinute == 0,
           next.title == current.title {
            let minutes = minutesUntil(minute: next.endMinute, on: occurrence.date)
            return DashboardNextScheduleItem(
                caption: "수면 계속",
                title: current.title,
                detail: "내일 \(TimeFormatter.clock(next.endMinute))까지 · \(TimeFormatter.duration(minutes)) 남음",
                symbolName: ScheduleCategory.sleep.symbolName,
                tint: ScheduleCategory.sleep.tint
            )
        }

        if next.displayCategory == .sleep,
           next.endMinute == 24 * 60,
           let continuation = sleepContinuation(after: occurrence) {
            let duration = sleepDuration(from: next, on: occurrence.date, to: continuation.block, on: continuation.date)
            let startPrefix = occurrence.dayOffset == 0 ? "" : "\(Weekday.from(date: occurrence.date).longName) "
            let endPrefix = continuation.dayOffset == 1 ? "내일 " : "\(Weekday.from(date: continuation.date).longName) "
            return DashboardNextScheduleItem(
                caption: "다음 일정",
                title: next.title,
                detail: "\(startPrefix)\(TimeFormatter.clock(next.startMinute))-\(endPrefix)\(TimeFormatter.clock(continuation.block.endMinute)) · \(TimeFormatter.duration(duration))",
                symbolName: ScheduleCategory.sleep.symbolName,
                tint: ScheduleCategory.sleep.tint
            )
        }

        let dayPrefix = occurrence.dayOffset == 0 ? "" : "\(Weekday.from(date: occurrence.date).longName) "
        return DashboardNextScheduleItem(
            caption: "다음 일정",
            title: next.title,
            detail: "\(dayPrefix)\(next.intervalText) · \(next.durationText)",
            symbolName: "arrow.right.circle",
            tint: next.displayCategory.tint
        )
    }

    private func sleepContinuation(after occurrence: ScheduleBlockOccurrence, calendar: Calendar = .autoupdatingCurrent) -> ScheduleBlockOccurrence? {
        guard let nextDate = calendar.date(byAdding: .day, value: 1, to: occurrence.date) else {
            return nil
        }

        let nextDay = Weekday.from(date: nextDate, calendar: calendar)
        guard let block = store.blocks(for: nextDay).first(where: {
            $0.displayCategory == .sleep &&
            $0.startMinute == 0 &&
            $0.title == occurrence.block.title
        }) else {
            return nil
        }

        return ScheduleBlockOccurrence(block: block, date: nextDate, dayOffset: occurrence.dayOffset + 1)
    }

    private func sleepDuration(
        from startBlock: ScheduleBlock,
        on startDate: Date,
        to endBlock: ScheduleBlock,
        on endDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .minute, value: startBlock.startMinute, to: startDay) ?? startDay
        let end = calendar.date(byAdding: .minute, value: endBlock.endMinute, to: endDay) ?? endDay
        return max(0, calendar.dateComponents([.minute], from: start, to: end).minute ?? 0)
    }

    private func minutesUntil(minute: Int, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
        return max(0, calendar.dateComponents([.minute], from: store.now, to: endDate).minute ?? 0)
    }

    private func missingPanel(count: Int) -> some View {
        #if os(macOS)
        Button {
            store.selectedSection = .missing
        } label: {
            missingPanelContent(count: count)
        }
        .buttonStyle(.plain)
        #else
        NavigationLink {
            MissingInfoView()
                .environmentObject(store)
        } label: {
            missingPanelContent(count: count)
        }
        .buttonStyle(.plain)
        #endif
    }

    private func missingPanelContent(count: Int) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 5) {
                    Text("확인 필요")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("기상, 준비, 이동처럼 아직 정하지 않은 항목 \(count)개가 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func nextCheckpointText() -> String {
        let minute = TimeFormatter.minuteOfDay(from: store.now)
        guard let next = TimeFormatter.nextFiveMinuteBoundary(after: minute) else {
            return "완료"
        }
        return TimeFormatter.clock(next)
    }

}

private struct DashboardNextScheduleItem {
    let caption: String
    let title: String
    let detail: String
    let symbolName: String
    let tint: Color
}

private struct TodayBlockPreview: View {
    @EnvironmentObject private var store: ScheduleStore
    let day: Weekday

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("오늘 흐름")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                ForEach(store.blocks(for: day).prefix(8)) { block in
                    CompactBlockRow(block: block)
                }
            }
        }
    }
}
