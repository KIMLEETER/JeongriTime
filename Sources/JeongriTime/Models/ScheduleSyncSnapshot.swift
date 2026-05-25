import Foundation

struct ScheduleSyncSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let plannedBlocks: [PlannedBlock]
    let deletedBaseBlockIDs: [String]
    let deletedPlanIDs: [String]
    let resolvedMissingIDs: [String]
    let calendarInboxItems: [CalendarInboxItem]
    let ignoredCalendarEventIDs: [String]

    init(
        updatedAt: Date = Date(),
        plannedBlocks: [PlannedBlock],
        deletedBaseBlockIDs: Set<String>,
        deletedPlanIDs: Set<String>,
        resolvedMissingIDs: Set<String>,
        calendarInboxItems: [CalendarInboxItem],
        ignoredCalendarEventIDs: Set<String>
    ) {
        self.schemaVersion = 1
        self.updatedAt = updatedAt
        self.plannedBlocks = plannedBlocks
        self.deletedBaseBlockIDs = Array(deletedBaseBlockIDs).sorted()
        self.deletedPlanIDs = Array(deletedPlanIDs).sorted()
        self.resolvedMissingIDs = Array(resolvedMissingIDs).sorted()
        self.calendarInboxItems = calendarInboxItems.sorted { $0.startDate < $1.startDate }
        self.ignoredCalendarEventIDs = Array(ignoredCalendarEventIDs).sorted()
    }
}
