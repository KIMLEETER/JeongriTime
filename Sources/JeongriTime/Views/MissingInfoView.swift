import SwiftUI

struct MissingInfoView: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var sectionFilter: CheckFilter = .all
    @State private var priorityFilter: MissingPriority? = nil
    @State private var calendarHandlingMessage: String?
    @State private var editingCalendarItem: CalendarInboxItem?

    var body: some View {
        ResponsiveScroll(maximumWidth: 980) { width in
            VStack(alignment: .leading, spacing: 16) {
                let calendarItems = filteredCalendarItems

                #if os(macOS)
                if width < 620 {
                    Text("확인 필요")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    mainFilterBar
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("확인 필요")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.ink)

                        Spacer()

                        mainFilterBar
                    }
                }
                #else
                mainFilterBar
                #endif

                if showsMissingItems {
                    priorityFilterBar
                }

                if !calendarItems.isEmpty {
                    CalendarInboxSection(
                        items: calendarItems,
                        message: calendarHandlingMessage,
                        canAccept: { item in
                            store.canAcceptCalendarInboxItem(id: item.id)
                        },
                        todayOverrideSource: { item in
                            store.calendarInboxTodayOverrideSource(id: item.id)
                        },
                        onAccept: { item, kind in
                            handleCalendarItem(item, kind: kind)
                        },
                        onTodayOverride: { item in
                            handleCalendarItemAsTodayOverride(item)
                        },
                        onIgnore: { item in
                            store.ignoreCalendarInboxItem(id: item.id)
                            calendarHandlingMessage = "\(item.title)을 숨겼습니다."
                        },
                        onEdit: { item in
                            editingCalendarItem = item
                        }
                    )
                }

                ForEach(Weekday.allCases) { day in
                    let items = filteredItems(for: day)
                    if !items.isEmpty {
                        MissingDaySection(day: day, items: items)
                    }
                }

                if calendarItems.isEmpty && !hasFilteredMissingItems {
                    EmptyCheckPanel()
                }
            }
        }
        .navigationTitle("확인 필요")
        .sheet(item: $editingCalendarItem) { item in
            CalendarInboxEditorSheet(item: item)
                .environmentObject(store)
        }
        .background(AppTheme.background)
    }

    private var mainFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CheckFilter.allCases) { filter in
                    Button {
                        sectionFilter = filter
                    } label: {
                        Label(filter.title, systemImage: filter.symbolName)
                    }
                    .buttonStyle(SelectorChipButtonStyle(isSelected: sectionFilter == filter))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var priorityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(nil, title: "전체")
                ForEach(MissingPriority.allCases) { priority in
                    filterButton(priority, title: priority.rawValue)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filteredItems(for day: Weekday) -> [MissingInfoItem] {
        guard showsMissingItems else {
            return []
        }
        return store.engine.missingItems(for: day)
            .filter { item in
                !store.isResolved(item)
            }
            .filter { item in
                priorityFilter == nil || item.priority == priorityFilter
            }
    }

    private func filterButton(_ priority: MissingPriority?, title: String) -> some View {
        Button {
            priorityFilter = priority
        } label: {
            Text(title)
        }
        .buttonStyle(SelectorChipButtonStyle(isSelected: priorityFilter == priority))
    }

    private var hasFilteredMissingItems: Bool {
        Weekday.allCases.contains { !filteredItems(for: $0).isEmpty }
    }

    private var filteredCalendarItems: [CalendarInboxItem] {
        let items = store.calendarInboxItems.sorted { $0.startDate < $1.startDate }
        guard showsCalendarItems else {
            return []
        }
        if sectionFilter == .conflicts {
            return items.filter { !store.canAcceptCalendarInboxItem(id: $0.id) }
        }
        return items
    }

    private var showsCalendarItems: Bool {
        sectionFilter == .all || sectionFilter == .calendar || sectionFilter == .conflicts
    }

    private var showsMissingItems: Bool {
        sectionFilter == .all || sectionFilter == .missing
    }

    private func handleCalendarItem(_ item: CalendarInboxItem, kind: ScheduleEntryKind) {
        let category = ScheduleCategory.infer(from: item.title)
        let place = SchedulePlace.infer(title: item.title, category: category)

        if store.acceptCalendarInboxItem(id: item.id, kind: kind, category: category, place: place) {
            calendarHandlingMessage = "\(item.title)을 \(kind.displayName) 항목으로 추가했습니다."
        } else {
            calendarHandlingMessage = "\(item.title)은 겹치는 시간이 있어 추가하지 못했습니다."
        }
    }

    private func handleCalendarItemAsTodayOverride(_ item: CalendarInboxItem) {
        let category = ScheduleCategory.infer(from: item.title)
        let place = SchedulePlace.infer(title: item.title, category: category)

        if store.acceptCalendarInboxItemAsTodayOverride(id: item.id, category: category, place: place) {
            calendarHandlingMessage = "\(item.title)을 오늘만 조정으로 반영했습니다."
        } else {
            calendarHandlingMessage = "\(item.title)은 오늘만 조정으로 처리하지 못했습니다."
        }
    }
}

private enum CheckFilter: String, CaseIterable, Identifiable {
    case all
    case calendar
    case missing
    case conflicts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .calendar: "캘린더"
        case .missing: "빠진 정보"
        case .conflicts: "시간 겹침"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .calendar: "calendar.badge.clock"
        case .missing: "exclamationmark.circle"
        case .conflicts: "exclamationmark.triangle"
        }
    }
}

private struct CalendarInboxSection: View {
    let items: [CalendarInboxItem]
    let message: String?
    let canAccept: (CalendarInboxItem) -> Bool
    let todayOverrideSource: (CalendarInboxItem) -> ScheduleBlock?
    let onAccept: (CalendarInboxItem, ScheduleEntryKind) -> Void
    let onTodayOverride: (CalendarInboxItem) -> Void
    let onIgnore: (CalendarInboxItem) -> Void
    let onEdit: (CalendarInboxItem) -> Void

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("캘린더에서 들어온 일정", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    Spacer()

                    Text("\(items.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text("가져온 일정은 바로 섞지 않고, 여기서 계획이나 시간표로 정리합니다.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.focus)
                }

                ForEach(items) { item in
                    PendingCalendarItemRow(
                        item: item,
                        canAccept: canAccept(item),
                        todayOverrideSource: todayOverrideSource(item),
                        onAccept: { kind in onAccept(item, kind) },
                        onTodayOverride: { onTodayOverride(item) },
                        onIgnore: { onIgnore(item) },
                        onEdit: { onEdit(item) }
                    )
                }
            }
        }
    }
}

private struct PendingCalendarItemRow: View {
    let item: CalendarInboxItem
    let canAccept: Bool
    let todayOverrideSource: ScheduleBlock?
    let onAccept: (ScheduleEntryKind) -> Void
    let onTodayOverride: () -> Void
    let onIgnore: () -> Void
    let onEdit: () -> Void

    private var inferredCategory: ScheduleCategory {
        ScheduleCategory.infer(from: item.title)
    }

    var body: some View {
        let actionColumns = [GridItem(.adaptive(minimum: 112), spacing: 8)]

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(inferredCategory.tint)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    Text("새 일정")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(AppTheme.ink)
                        .background(inferredCategory.tint.opacity(0.16))
                        .clipShape(Capsule())
                }

                Text("\(Weekday.from(date: item.startDate).rawValue) \(item.intervalText()) · \(item.calendarTitle) · 가져옴 \(item.importedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)

                HStack(spacing: 8) {
                    Label(inferredCategory.displayName, systemImage: inferredCategory.symbolName)
                    if canAccept {
                        Label("처리 가능", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.green)
                    } else if todayOverrideSource != nil {
                        Label("오늘만 조정 가능", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        Label("시간 겹침", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.focus)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)

                if canAccept {
                    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                        if todayOverrideSource != nil {
                            Button {
                                onTodayOverride()
                            } label: {
                                Label("오늘만 조정", systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                        }

                        Button {
                            onAccept(.once)
                        } label: {
                            Label("이번만", systemImage: ScheduleEntryKind.once.symbolName)
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: todayOverrideSource == nil))

                        Button {
                            onAccept(.weeklyPlan)
                        } label: {
                            Label("매주", systemImage: ScheduleEntryKind.weeklyPlan.symbolName)
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.planned.tint))

                        Button {
                            onAccept(.timetable)
                        } label: {
                            Label("시간표에 고정", systemImage: ScheduleEntryKind.timetable.symbolName)
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: ScheduleCategory.lab.tint))

                        Button {
                            onEdit()
                        } label: {
                            Label("조정", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
                    }
                } else if todayOverrideSource != nil {
                    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                        Button {
                            onTodayOverride()
                        } label: {
                            Label("오늘만 조정", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))

                        Button {
                            onEdit()
                        } label: {
                            Label("시간 조정", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(ActionPillButtonStyle(tint: AppTheme.muted))
                    }

                    if let todayOverrideSource {
                        Text("겹친 시간표: \(todayOverrideSource.title)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                } else {
                    Button {
                        onEdit()
                    } label: {
                        Label("시간 조정", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                }
            }

            Spacer(minLength: 8)

            Button {
                onIgnore()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.muted)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(11)
        .background(canAccept ? AppTheme.background : AppTheme.focus.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CalendarInboxEditorSheet: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    let item: CalendarInboxItem
    @State private var title: String
    @State private var day: Weekday
    @State private var startMinute: Int
    @State private var endMinute: Int
    @State private var kind: ScheduleEntryKind
    @State private var category: ScheduleCategory
    @State private var categoryEdited: Bool
    @State private var place: SchedulePlace
    @State private var placeEdited: Bool
    @State private var message: String?

    init(item: CalendarInboxItem) {
        self.item = item
        let start = item.startMinute()
        let end = min(24 * 60, max(start + 5, item.endMinute()))
        let initialCategory = ScheduleCategory.infer(from: item.title)
        _title = State(initialValue: item.title)
        _day = State(initialValue: item.day())
        _startMinute = State(initialValue: start)
        _endMinute = State(initialValue: end)
        _kind = State(initialValue: .once)
        _category = State(initialValue: initialCategory)
        _categoryEdited = State(initialValue: false)
        _place = State(initialValue: SchedulePlace.infer(title: item.title, category: initialCategory))
        _placeEdited = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("시간 조정")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("겹치지 않는 빈 시간으로 옮긴 뒤 정리합니다.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            TextField("제목", text: $title)
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

            Picker("요일", selection: $day) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.rawValue).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

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
                    save()
                } label: {
                    Label(kind.saveLabel, systemImage: kind.symbolName)
                }
                .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endMinute <= startMinute)
            }
        }
        .padding(22)
        .frame(minWidth: 380)
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

    private func save() {
        if store.acceptCalendarInboxItem(
            id: item.id,
            kind: kind,
            day: day,
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
    }
}

private struct EmptyCheckPanel: View {
    var body: some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.green)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("처리할 항목이 없습니다.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("새 캘린더 일정이나 빠진 정보가 생기면 여기에 모입니다.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()
            }
        }
    }
}

private struct MissingDaySection: View {
    @EnvironmentObject private var store: ScheduleStore
    let day: Weekday
    let items: [MissingInfoItem]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(day.longName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                ForEach(items) { item in
                    MissingItemRow(
                        item: item,
                        isResolved: store.isResolved(item)
                    ) { resolved in
                        withAnimation(.snappy(duration: 0.18)) {
                            store.setMissingResolved(item, resolved: resolved)
                        }
                    }
                }
            }
        }
    }
}

private struct MissingItemRow: View {
    let item: MissingInfoItem
    let isResolved: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggle(!isResolved)
            } label: {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isResolved ? .green : AppTheme.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isResolved ? "확인 완료" : "확인 필요")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.topic)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isResolved ? AppTheme.muted : AppTheme.ink)
                    priorityBadge(item.priority)
                }

                Text(item.currentState)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)

                Text(item.decisionNeeded)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
            }

            Spacer()
        }
        .padding(11)
        .background(isResolved ? Color.green.opacity(0.08) : item.priority.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func priorityBadge(_ priority: MissingPriority) -> some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(priority == .high ? Color.white : AppTheme.ink)
            .background(priority.fill)
            .clipShape(Capsule())
    }
}

private extension MissingPriority {
    var fill: Color {
        switch self {
        case .high: AppTheme.focus
        case .medium: Color.orange.opacity(0.25)
        case .low: Color.green.opacity(0.22)
        }
    }

    var surface: Color {
        switch self {
        case .high: AppTheme.focus.opacity(0.08)
        case .medium: Color.orange.opacity(0.10)
        case .low: Color.green.opacity(0.08)
        }
    }
}
