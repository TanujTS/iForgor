import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TaskStore {
    private(set) var lists: [TaskList] = []
    private(set) var isUnavailable = false
    var errorMessage: String?
    @ObservationIgnored private let context: ModelContext
    private var settings: AppSettings

    var selectedListID: UUID? { settings.selectedListID }
    var selectedList: TaskList? { lists.first { $0.id == selectedListID } }

    /// Opens saved data or an empty store; initialization never creates sample lists or tasks.
    init(configuration: ModelConfiguration = ModelConfiguration(cloudKitDatabase: .none)) throws {
        let container = try ModelContainer(for: TaskList.self, TaskItem.self, AppSettings.self,
                                           configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        let savedSettings = try context.fetch(FetchDescriptor<AppSettings>())
        let savedLists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\TaskList.position)]))
        if let existing = savedSettings.first {
            settings = existing
            lists = savedLists
        } else {
            settings = AppSettings(selectedListID: savedLists.first?.id)
            context.insert(settings)
            try context.save()
            lists = savedLists
        }
        if let id = settings.selectedListID, !lists.contains(where: { $0.id == id }) {
            settings.selectedListID = lists.first?.id
            try context.save()
        }
    }

    func selectList(_ id: UUID?) {
        guard id != selectedListID else { return }
        _ = save("select the list") { settings.selectedListID = id }
    }

    func addTask(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let list = selectedList else { return false }
        return save("add the task") {
            let task = TaskItem(title: title, position: (list.tasks.map(\.position).max() ?? -1) + 1)
            context.insert(task)
            list.tasks.append(task)
        }
    }

    func setCompleted(_ completed: Bool, task: TaskItem) {
        _ = save("change task completion") { task.isCompleted = completed }
    }

    func updateTask(_ draft: TaskDraft) -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        guard let task = lists.flatMap(\.tasks).first(where: { $0.id == draft.id }) else {
            errorMessage = "This task no longer exists. Close the editor and select another task."
            return false
        }
        return save("update the task") {
            task.title = title
            task.notes = draft.notes
            task.isCompleted = draft.isCompleted
            task.scheduledDate = draft.scheduledDate
        }
    }

    func deleteTask(_ task: TaskItem) {
        _ = save("delete the task") { context.delete(task) }
    }

    func addList(title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = save("add the list") {
            let list = TaskList(title: title, position: (lists.map(\.position).max() ?? -1) + 1)
            context.insert(list)
            settings.selectedListID = list.id
        }
    }

    func renameSelectedList(title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let list = selectedList else { return }
        _ = save("rename the list") { list.title = title }
    }

    func deleteSelectedList() {
        guard let list = selectedList else { return }
        _ = save("delete the list") {
            settings.selectedListID = lists.first { $0.id != list.id }?.id
            context.delete(list)
        }
    }

    /// Commits one UI action. Failed writes roll back; failed reloads block further edits.
    private func save(_ action: String, changes: () -> Void) -> Bool {
        guard !isUnavailable else { return false }
        changes()
        do {
            try context.save()
        } catch {
            context.rollback()
            let failure = error as NSError
            errorMessage = "Could not \(action). The change was not saved. Check available disk space and storage access. Error: \(failure.domain) (\(failure.code))."
            reload()
            return false
        }
        reload()
        return true
    }

    /// Refetches after saves or rollback so deleted/rolled-back model references leave the UI.
    private func reload() {
        do {
            lists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\TaskList.position)]))
        } catch {
            isUnavailable = true
            let failure = error as NSError
            errorMessage = "Lists could not be read. A preceding change may already be saved. Quit and reopen iForgor; storage has not been reset. Error: \(failure.domain) (\(failure.code))."
        }
    }
}
