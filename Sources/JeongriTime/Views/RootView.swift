import SwiftUI

struct RootView: View {
    @StateObject private var store = ScheduleStore()
    @StateObject private var driveSync = GoogleDriveSyncService()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        rootContent
            .onReceive(timer) {
                store.updateNow($0)
                Task {
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 90)
                }
            }
            .task {
                await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                await driveSync.synchronizeIfReady(store: store, minimumInterval: 0)
            }
            .onChange(of: store.plannedBlocks) { _, _ in
                Task {
                    await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 10)
                }
            }
            .onChange(of: store.deletedBaseBlockIDs) { _, _ in
                Task {
                    await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 10)
                }
            }
            .onChange(of: store.resolvedMissingIDs) { _, _ in
                Task {
                    await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 10)
                }
            }
            .onChange(of: store.calendarInboxItems) { _, _ in
                Task {
                    await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 10)
                }
            }
            .onChange(of: store.ignoredCalendarEventIDs) { _, _ in
                Task {
                    await ScheduleNotificationScheduler.synchronizeIfAuthorized(store: store)
                    await driveSync.synchronizeIfReady(store: store, minimumInterval: 10)
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        Group {
            #if os(macOS)
            splitView
            #else
            tabView
            #endif
        }
    }

    #if os(macOS)
    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .id(store.selectedSection)
                .environmentObject(store)
                .environmentObject(driveSync)
                .background(AppTheme.background)
        }
    }
    #endif

    #if !os(macOS)
    private var tabView: some View {
        TabView(selection: $store.selectedSection) {
            ForEach(AppSection.primarySections) { section in
                NavigationStack {
                    detailView(for: section)
                        .environmentObject(store)
                        .environmentObject(driveSync)
                        .background(AppTheme.background)
                }
                .tabItem {
                    Label(section.rawValue, systemImage: section.symbolName)
                }
                .tag(section)
                .badge(section == .settings ? store.checkNeededCount : 0)
            }
        }
    }
    #endif

    @ViewBuilder
    private var detailView: some View {
        detailView(for: store.selectedSection)
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView()
        case .timeline:
            DayTimelineView()
        case .week:
            WeekPlannerView()
        case .schedule:
            ScheduleHubView()
        case .statistics:
            StatisticsView()
        case .missing:
            MissingInfoView()
        case .settings:
            AppSettingsView()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 6) {
                ForEach(AppSection.primarySections) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        HStack {
                            Label(section.rawValue, systemImage: section.symbolName)
                            Spacer()
                            if section == .settings && store.checkNeededCount > 0 {
                                Text("\(store.checkNeededCount)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(store.selectedSection == section ? AppTheme.accent : AppTheme.ink)
                    .fontWeight(store.selectedSection == section ? .bold : .regular)
                    .background(store.selectedSection == section ? AppTheme.accent.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(10)
        }
        .navigationTitle("정리시간")
        .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
        #else
        List {
            ForEach(AppSection.primarySections) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.symbolName)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.selectedSection == section ? AppTheme.accent : AppTheme.ink)
                .fontWeight(store.selectedSection == section ? .bold : .regular)
            }
        }
        .navigationTitle("정리시간")
        #endif
    }
}
