import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var notes: String
    var scheduledDate: Date?
    var position: Int
    var list: TaskList?

    init(title: String, position: Int = 0) {
        id = UUID()
        self.title = title
        isCompleted = false
        notes = ""
        self.position = position
    }
}

@Model
final class TaskList {
    @Attribute(.unique) var id: UUID
    var title: String
    var position: Int
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var tasks: [TaskItem]

    init(title: String, position: Int = 0, tasks: [TaskItem] = []) {
        id = UUID()
        self.title = title
        self.position = position
        self.tasks = tasks
    }

    var orderedTasks: [TaskItem] {
        tasks.sorted { $0.position < $1.position }
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var key: String
    var selectedListID: UUID?

    init(selectedListID: UUID?) {
        key = "settings"
        self.selectedListID = selectedListID
    }
}

/// A value copy for editing; changing it never changes a stored model until Save.
struct TaskDraft: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var notes: String
    var scheduledDate: Date?

    init(task: TaskItem) {
        id = task.id
        title = task.title
        isCompleted = task.isCompleted
        notes = task.notes
        scheduledDate = task.scheduledDate
    }
}
