import Foundation

enum MissingPriority: String, CaseIterable, Identifiable {
    case high = "높음"
    case medium = "중간"
    case low = "낮음"

    var id: String { rawValue }
}

struct MissingInfoItem: Identifiable, Hashable {
    let id: String
    let day: Weekday
    let topic: String
    let currentState: String
    let decisionNeeded: String
    let priority: MissingPriority

    init(day: Weekday, topic: String, currentState: String, decisionNeeded: String, priority: MissingPriority) {
        self.day = day
        self.topic = topic
        self.currentState = currentState
        self.decisionNeeded = decisionNeeded
        self.priority = priority
        self.id = "\(day.rawValue)-\(topic)"
    }
}
