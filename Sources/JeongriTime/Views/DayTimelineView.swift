import SwiftUI

struct DayTimelineView: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var activeEditor: TimelineEditor?
    @State private var commandMessage: String?
    private let showsTitle: Bool

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
    }

    var body: some View {
        let current = store.currentBlock(at: store.now)
        let blocks = store.blocks(for: store.selectedDay)
        let freeBlocks = blocks.filter(\.isFree)
        let timetableBlocks = store.timetableBlocks(for: store.selectedDay)
        let todayCancellations = store.todayCancellations(for: store.selectedDay)
        let locationGroups = TimelineLocationGroup.make(from: blocks)

        ResponsiveScroll(maximumWidth: 980) { _ in
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    #if os(macOS)
                    if showsTitle {
                        Text("빈시간")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    #endif

                    DaySelector(selection: $store.selectedDay)
                }

                FreeTimeCommandPanel(
                    day: store.selectedDay,
                    remaining: remainingForSelectedDay(),
                    planned: store.plannedMinutes(for: store.selectedDay),
                    freeBlocks: freeBlocks,
                    timetableBlocks: timetableBlocks,
                    timetableCount: timetableBlocks.count,
                    todayCancellations: todayCancellations,
                    message: commandMessage,
                    onPlan: { activeEditor = .plan($0) },
                    onAdjustToday: { activeEditor = .todayOverride($0) },
                    onClearDay: {
                        let count = store.hideAllTimetableBlocksForToday(day: store.selectedDay)
                        commandMessage = count == 0 ? "비울 고정 시간이 없습니다." : "\(count)개의 고정 시간을 오늘만 비웠습니다."
                    },
                    onRestoreCancellation: { entry in
                        store.restoreTodayCancellation(id: entry.id)
                        commandMessage = "\(entry.title)을 원래대로 돌렸습니다."
                    },
                    onRestoreAll: {
                        let count = store.restoreAllTodayCancellations(day: store.selectedDay)
                        commandMessage = count == 0 ? "원래대로 돌릴 항목이 없습니다." : "\(count)개의 고정 시간을 원래대로 돌렸습니다."
                    }
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("하루 흐름")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    LazyVStack(spacing: 12) {
                        ForEach(locationGroups) { group in
                            LocationTimelineGroupView(
                                group: group,
                                current: current,
                                selectedDay: store.selectedDay,
                                onPlan: { activeEditor = .plan($0) },
                                onAdjustToday: { activeEditor = .todayOverride($0) },
                                onHideToday: { block in
                                    if store.hideTimetableBlockForToday(sourceBlockID: block.id, day: block.day) {
                                        commandMessage = "\(block.title)을 오늘만 비웠습니다."
                                    } else {
                                        commandMessage = "오늘만 비우지 못했습니다."
                                    }
                                },
                                onDeletePlan: { store.deletePlan(id: $0.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(showsTitle ? "빈시간" : "시간표")
        .sheet(item: $activeEditor) { editor in
            switch editor {
            case .plan(let block):
                PlanEditorSheet(block: block)
                    .environmentObject(store)
            case .todayOverride(let block):
                TodayOverrideEditorSheet(block: block)
                    .environmentObject(store)
            }
        }
    }

    private func remainingForSelectedDay() -> Int {
        let today = Weekday.from(date: store.now)
        if store.selectedDay == today {
            return store.remainingFreeMinutes(from: store.now)
        }
        return store.freeMinutes(for: store.selectedDay)
    }
}

private enum TimelineEditor: Identifiable {
    case plan(ScheduleBlock)
    case todayOverride(ScheduleBlock)

    var id: String {
        switch self {
        case .plan(let block):
            "plan-\(block.id)"
        case .todayOverride(let block):
            "today-\(block.id)"
        }
    }
}

private struct FreeTimeCommandPanel: View {
    let day: Weekday
    let remaining: Int
    let planned: Int
    let freeBlocks: [ScheduleBlock]
    let timetableBlocks: [ScheduleBlock]
    let timetableCount: Int
    let todayCancellations: [PlannedBlock]
    let message: String?
    let onPlan: (ScheduleBlock) -> Void
    let onAdjustToday: (ScheduleBlock) -> Void
    let onClearDay: () -> Void
    let onRestoreCancellation: (PlannedBlock) -> Void
    let onRestoreAll: () -> Void

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                summaryRow

                todayTimetableActions

                if let message {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }

                todayCancellationList

                freeBlockActions
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 10) {
            freeTimeSummary
                .layoutPriority(1)

            Spacer(minLength: 8)

            plannedSummary
                .frame(width: 106, alignment: .trailing)
        }
    }

    private var freeTimeSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.free)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(day.longName) 남은 빈 시간")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(TimeFormatter.duration(remaining))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
    }

    private var plannedSummary: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("계획한 시간")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            Text(TimeFormatter.duration(planned))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(ScheduleCategory.planned.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var freeBlockActions: some View {
        Group {
            if freeBlocks.isEmpty {
                Text("남은 빈 시간을 모두 채웠습니다.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(freeBlocks.prefix(6)) { block in
                        Button {
                            onPlan(block)
                        } label: {
                            HStack(spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text(block.intervalText)
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(1)

                                    Text(block.durationText)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.free))
                    }
                }
            }
        }
    }

    private var todayTimetableActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
            Menu {
                ForEach(timetableBlocks) { block in
                    Button {
                        onAdjustToday(block)
                    } label: {
                        Label("\(block.intervalText) \(block.title)", systemImage: "clock.arrow.circlepath")
                    }
                }
            } label: {
                Label("오늘만 조정", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent))
            .disabled(timetableBlocks.isEmpty)

            Button {
                onClearDay()
            } label: {
                Label("오늘 시간표 비우기", systemImage: "calendar.badge.minus")
            }
            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
            .disabled(timetableCount == 0)

            if !todayCancellations.isEmpty {
                Button {
                    onRestoreAll()
                } label: {
                    Label("오늘 시간표 원래대로", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
            }
        }
    }

    @ViewBuilder
    private var todayCancellationList: some View {
        if !todayCancellations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("오늘만 비운 시간표")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)

                ForEach(todayCancellations) { entry in
                    TodayCancellationRow(entry: entry) {
                        onRestoreCancellation(entry)
                    }
                }
            }
        }
    }
}

private struct TodayCancellationRow: View {
    let entry: PlannedBlock
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Text("\(TimeFormatter.clock(entry.startMinute))-\(TimeFormatter.clock(entry.endMinute)) · \(TimeFormatter.duration(entry.durationMinutes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label("원래대로", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
        }
        .padding(10)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimelineLocationGroup: Identifiable {
    let place: SchedulePlace
    var blocks: [ScheduleBlock]

    var id: String {
        "\(place.rawValue)-\(startMinute)-\(endMinute)-\(blocks.count)"
    }

    var startMinute: Int {
        blocks.first?.startMinute ?? 0
    }

    var endMinute: Int {
        blocks.last?.endMinute ?? startMinute
    }

    var intervalText: String {
        "\(TimeFormatter.clock(startMinute))-\(TimeFormatter.clock(endMinute))"
    }

    var durationText: String {
        TimeFormatter.duration(max(0, endMinute - startMinute))
    }

    static func make(from blocks: [ScheduleBlock]) -> [TimelineLocationGroup] {
        var groups: [TimelineLocationGroup] = []

        for block in blocks {
            let place = block.displayPlace
            if let lastIndex = groups.indices.last, groups[lastIndex].place == place {
                groups[lastIndex].blocks.append(block)
            } else {
                groups.append(TimelineLocationGroup(place: place, blocks: [block]))
            }
        }

        return groups
    }
}

private struct LocationTimelineGroupView: View {
    let group: TimelineLocationGroup
    let current: ScheduleBlock
    let selectedDay: Weekday
    let onPlan: (ScheduleBlock) -> Void
    let onAdjustToday: (ScheduleBlock) -> Void
    let onHideToday: (ScheduleBlock) -> Void
    let onDeletePlan: (ScheduleBlock) -> Void

    var body: some View {
        let isCurrentGroup = selectedDay == current.day && group.blocks.contains { $0.id == current.id }

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: group.place.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isCurrentGroup ? AppTheme.focus : group.place.tint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(group.place.rawValue)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)

                        if isCurrentGroup {
                            Label("현재", systemImage: "location.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.focus)
                        }
                    }

                    Text("\(group.intervalText) · \(group.durationText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Text("\(group.blocks.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isCurrentGroup ? AppTheme.focus.opacity(0.11) : group.place.surface)

            ForEach(group.blocks.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                        .padding(.leading, 92)
                }

                let block = group.blocks[index]
                LocationBlockRow(
                    block: block,
                    isCurrent: selectedDay == current.day && block.id == current.id,
                    onPlan: onPlan,
                    onAdjustToday: onAdjustToday,
                    onHideToday: onHideToday,
                    onDeletePlan: onDeletePlan
                )
            }
        }
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .decorativeStroke(
            RoundedRectangle(cornerRadius: 8, style: .continuous),
            color: isCurrentGroup ? AppTheme.focus.opacity(0.55) : AppTheme.line,
            lineWidth: isCurrentGroup ? 1.5 : 1
        )
    }
}

private struct LocationBlockRow: View {
    let block: ScheduleBlock
    let isCurrent: Bool
    let onPlan: (ScheduleBlock) -> Void
    let onAdjustToday: (ScheduleBlock) -> Void
    let onHideToday: (ScheduleBlock) -> Void
    let onDeletePlan: (ScheduleBlock) -> Void

    var body: some View {
        let category = block.displayCategory

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isCurrent ? AppTheme.focus : category.tint)
                .frame(width: 5)
                .padding(.vertical, 2)

            VStack(alignment: .trailing, spacing: 3) {
                Text(TimeFormatter.clock(block.startMinute))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(TimeFormatter.clock(block.endMinute))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(width: 56, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(block.title)
                        .font(.subheadline.weight(block.isFree ? .regular : .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)

                    if isCurrent {
                        Text("현재")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.focus)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Label(block.durationText, systemImage: "hourglass")
                    Label(category.displayName, systemImage: category.symbolName)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

                if let note = block.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if block.isFree {
                Button {
                    onPlan(block)
                } label: {
                    Label("계획하기", systemImage: "plus")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: isCurrent))
            } else if block.isTemporaryOverride {
                Button {
                    onDeletePlan(block)
                } label: {
                    Label("원래대로", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
            } else if block.isPlanned {
                Button {
                    onDeletePlan(block)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        onAdjustToday(block)
                    } label: {
                        Label("오늘만 조정", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: category.tint))

                    Button {
                        onHideToday(block)
                    } label: {
                        Label("오늘만 비우기", systemImage: "calendar.badge.minus")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isCurrent ? AppTheme.focus.opacity(0.08) : Color.clear)
    }
}

struct TodayOverrideEditorSheet: View {
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
                Text("오늘만 조정")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("원래 시간표는 그대로 두고 오늘의 실제 시간만 바꿉니다.")
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
                Stepper(value: $startMinute, in: 0...(24 * 60 - 5), step: 5) {
                    timeRow("시작", minute: startMinute)
                }

                Stepper(value: $endMinute, in: (startMinute + 5)...(24 * 60), step: 5) {
                    timeRow("종료", minute: endMinute)
                }
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
                    if store.saveTodayOverride(
                        sourceBlockID: block.id,
                        day: block.day,
                        startMinute: startMinute,
                        endMinute: endMinute,
                        title: title,
                        category: category,
                        place: place
                    ) {
                        dismiss()
                    } else {
                        message = "겹치는 시간이 있어 조정하지 못했습니다."
                    }
                } label: {
                    Label("오늘만 저장", systemImage: "checkmark")
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endMinute <= startMinute)
            }
        }
        .padding(22)
        .frame(minWidth: 360)
        .onChange(of: startMinute) { _, newValue in
            if endMinute <= newValue {
                endMinute = min(24 * 60, newValue + 5)
            }
        }
    }

    private func timeRow(_ label: String, minute: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(TimeFormatter.clock(minute))
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
    }
}

private struct PlanEditorSheet: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var calendarBridge = CalendarBridge()

    let block: ScheduleBlock
    @State private var title: String
    @State private var startMinute: Int
    @State private var endMinute: Int
    @State private var kind: ScheduleEntryKind
    @State private var category: ScheduleCategory
    @State private var categoryEdited: Bool
    @State private var place: SchedulePlace
    @State private var placeEdited: Bool
    @State private var addToCalendar: Bool
    @State private var message: String?
    @State private var isSaving = false

    init(block: ScheduleBlock) {
        self.block = block
        _title = State(initialValue: "")
        _startMinute = State(initialValue: block.startMinute)
        _endMinute = State(initialValue: min(block.endMinute, block.startMinute + min(60, block.durationMinutes)))
        _kind = State(initialValue: .once)
        _category = State(initialValue: .other)
        _categoryEdited = State(initialValue: false)
        _place = State(initialValue: .other)
        _placeEdited = State(initialValue: false)
        _addToCalendar = State(initialValue: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("계획하기")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(block.intervalText) 안에서 5분 단위로 잡습니다.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            TextField("예: 과제, 독서, 휴식", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, newValue in
                    if !categoryEdited {
                        category = ScheduleCategory.infer(from: newValue)
                    }
                    if !placeEdited {
                        place = SchedulePlace.infer(title: newValue, category: category)
                    }
                }

            Picker("저장 방식", selection: $kind) {
                ForEach(ScheduleEntryKind.allCases) { entryKind in
                    Text(entryKind.displayName).tag(entryKind)
                }
            }
            .pickerStyle(.segmented)

            if kind == .once {
                Toggle("캘린더에도 추가", isOn: $addToCalendar)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            Picker("분류", selection: Binding(
                get: { category },
                set: {
                    category = $0
                    categoryEdited = true
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
                Stepper(value: $startMinute, in: block.startMinute...(block.endMinute - 5), step: 5) {
                    timeRow("시작", minute: startMinute)
                }

                Stepper(value: $endMinute, in: (startMinute + 5)...block.endMinute, step: 5) {
                    timeRow("종료", minute: endMinute)
                }
            }

            if let message {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.focus)
            }

            HStack {
                Text(TimeFormatter.duration(endMinute - startMinute))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ScheduleCategory.planned.tint)
                Spacer()
                Button("취소") {
                    dismiss()
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))

                Button {
                    save()
                } label: {
                    Label(kind.saveLabel, systemImage: kind.symbolName)
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(22)
        .frame(minWidth: 360)
        .onChange(of: startMinute) { _, newValue in
            if endMinute <= newValue {
                endMinute = min(block.endMinute, newValue + 5)
            }
        }
    }

    private func timeRow(_ label: String, minute: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(TimeFormatter.clock(minute))
                .font(.headline.monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func save() {
        guard let plan = store.addPlanAndReturn(
            day: block.day,
            startMinute: startMinute,
            endMinute: endMinute,
            title: title,
            kind: kind,
            category: category,
            place: place
        ) else {
            message = "겹치는 시간이 있어 저장하지 못했습니다."
            return
        }

        guard kind == .once, addToCalendar else {
            dismiss()
            return
        }

        isSaving = true
        Task {
            do {
                let eventID = try await calendarBridge.createEvent(for: plan, date: store.date(for: block.day))
                store.linkCalendarEvent(planID: plan.id, eventIdentifier: eventID)
                dismiss()
            } catch {
                message = "앱에는 저장됐지만 캘린더 추가에 실패했습니다."
                isSaving = false
            }
        }
    }
}
