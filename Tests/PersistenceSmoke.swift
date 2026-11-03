import Foundation
import SwiftData

/// Integration checks use an isolated temporary database, never the app's saved tasks.
@main
struct PersistenceSmoke {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("smoke.store")
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let ids = try createAndEdit(configuration: configuration)
        try reopenAndDelete(configuration: configuration, listID: ids.list, taskID: ids.task)
        try verifyEmptyRelaunch(configuration: configuration)
        try verifyReadOnlyRollback(configuration: configuration)
        try verifyCorruptStore(directory: directory)
        print("PASS: persistence, identity, ordering, draft isolation, deletion, empty relaunch, rollback, corrupt storage")
    }

    /// Saves realistic edits and returns IDs that must survive a fresh container/context.
    @MainActor
    private static func createAndEdit(configuration: ModelConfiguration) throws -> (list: UUID, task: UUID) {
        let store = try TaskStore(configuration: configuration)
        precondition(store.lists.isEmpty && store.selectedListID == nil,
                     "First launch must be empty, with no sample data")
        store.addList(title: "Integration test")
        let list = store.selectedList!
        precondition(store.addTask(title: "  Duplicate  "))
        precondition(store.addTask(title: "Duplicate"))
        precondition(!store.addTask(title: " \n "))
        let task = list.orderedTasks[0]
        precondition(task.id != list.orderedTasks[1].id)
        var draft = TaskDraft(task: task)
        draft.title = "Saved title"
        draft.notes = "Saved notes"
        draft.scheduledDate = Date(timeIntervalSince1970: 1_800_000_000)
        precondition(task.title == "Duplicate", "Draft edits must not mutate the live model")
        precondition(store.updateTask(draft))
        store.setCompleted(true, task: task)
        store.renameSelectedList(title: "Renamed")
        precondition(store.errorMessage == nil)
        return (list.id, task.id)
    }

    /// A separate context must restore data, order and selection; cascade deletion must remove children.
    @MainActor
    private static func reopenAndDelete(configuration: ModelConfiguration, listID: UUID, taskID: UUID) throws {
        let store = try TaskStore(configuration: configuration)
        precondition(store.lists.count == 1, "Relaunch must preserve only saved lists")
        precondition(store.selectedListID == listID)
        let list = store.selectedList!
        precondition(list.title == "Renamed")
        let task = list.orderedTasks[0]
        precondition(task.id == taskID && task.title == "Saved title")
        precondition(task.notes == "Saved notes" && task.isCompleted)
        precondition(task.scheduledDate == Date(timeIntervalSince1970: 1_800_000_000))
        precondition(task.list?.id == listID, "Inverse relationship must persist")
        store.setCompleted(false, task: task)
        store.deleteTask(list.orderedTasks[1])
        precondition(list.tasks.count == 1, "Task deletion must update the relationship")
        store.deleteSelectedList()
        let inspection = try ModelContainer(for: TaskList.self, TaskItem.self, AppSettings.self,
                                             configurations: configuration)
        let tasks = try inspection.mainContext.fetch(FetchDescriptor<TaskItem>())
        precondition(!tasks.contains { $0.id == taskID }, "Deleting a list must cascade to tasks")
        while let first = store.lists.first {
            store.selectList(first.id)
            store.deleteSelectedList()
        }
        precondition(store.selectedListID == nil && store.errorMessage == nil)
    }

    @MainActor
    private static func verifyEmptyRelaunch(configuration: ModelConfiguration) throws {
        let store = try TaskStore(configuration: configuration)
        precondition(store.lists.isEmpty && store.selectedListID == nil,
                     "An empty store must stay empty after relaunch")
        store.addList(title: "After empty")
        precondition(store.selectedList?.title == "After empty")
        precondition(store.addTask(title: "Read-only original"))
    }

    /// An actual read-only database failure must retain the previous value in memory and on disk.
    @MainActor
    private static func verifyReadOnlyRollback(configuration: ModelConfiguration) throws {
        let readOnly = ModelConfiguration(url: configuration.url, allowsSave: false, cloudKitDatabase: .none)
        let store = try TaskStore(configuration: readOnly)
        let task = store.selectedList!.tasks[0]
        store.setCompleted(true, task: task)
        precondition(store.errorMessage != nil, "Failed writes must be visible")
        precondition(!store.selectedList!.tasks[0].isCompleted, "Failed writes must roll back")
        precondition(!store.addTask(title: "Must not be saved"))
        precondition(store.selectedList!.tasks.count == 1, "Failed insertion must roll back")
        store.deleteSelectedList()
        precondition(store.lists.count == 1 && store.selectedList != nil,
                     "Failed deletion and selection change must roll back together")
        let reopened = try TaskStore(configuration: configuration)
        precondition(!reopened.selectedList!.tasks[0].isCompleted)
    }

    /// Invalid storage must fail opening rather than silently replacing data with an empty store.
    @MainActor
    private static func verifyCorruptStore(directory: URL) throws {
        let url = directory.appendingPathComponent("corrupt.store")
        let bytes = Data("not a database".utf8)
        try bytes.write(to: url)
        var failed = false
        do {
            _ = try TaskStore(configuration: ModelConfiguration(url: url, cloudKitDatabase: .none))
        } catch {
            failed = true
        }
        precondition(failed, "Corrupt storage must fail opening")
        let remainingBytes = try Data(contentsOf: url)
        precondition(remainingBytes == bytes, "Corrupt storage must not be overwritten")
    }
}
