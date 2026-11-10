import Foundation
import Observation

/// One visible row: an open task and its nesting depth (Google allows one level of subtasks).
struct TaskRowItem: Identifiable, Hashable {
    let task: GTask
    let depth: Int
    var id: String { task.id }
}

/// Google Tasks data for the signed-in account: fetching, the offline copy, and the selected list.
@MainActor
@Observable
final class TasksModel {
    private(set) var lists: [GTaskList] = []
    private(set) var tasksByList: [String: [GTask]] = [:]
    var selectedListID: String? {
        didSet { if oldValue != selectedListID { saveCache() } }
    }
    private(set) var isRefreshing = false
    private(set) var lastSynced: Date?
    /// True when the lists on screen come from the saved copy because Google could not be reached.
    private(set) var isShowingCache = false
    var errorMessage: String?

    let account: GoogleAccount
    @ObservationIgnored private let api: GoogleTasksAPI
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(account: GoogleAccount) {
        self.account = account
        api = GoogleTasksAPI(account: account)
    }

    var selectedList: GTaskList? { lists.first { $0.id == selectedListID } }
    var selectedTasks: [GTask] { selectedListID.flatMap { tasksByList[$0] } ?? [] }

    /// Shows the new account's saved copy right away, then fetches fresh data. Sign-out clears everything.
    func accountChanged(to email: String?) {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        lists = []
        tasksByList = [:]
        lastSynced = nil
        errorMessage = nil
        if let email {
            loadCache(for: email)
            refresh()
        } else {
            selectedListID = nil
            Self.deleteCache()
        }
    }

    func refreshIfStale(olderThan seconds: TimeInterval = 60) {
        guard let lastSynced, Date().timeIntervalSince(lastSynced) < seconds else { return refresh() }
    }

    /// Fetches every list and its tasks. Ignored while a refresh is running; results for an account
    /// that is no longer signed in are discarded.
    func refresh() {
        guard let email = account.email, refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task {
            defer {
                refreshTask = nil
                isRefreshing = false
            }
            do {
                let lists = try await api.taskLists()
                var tasks: [String: [GTask]] = [:]
                for list in lists {
                    tasks[list.id] = try await api.tasks(in: list.id)
                }
                guard !Task.isCancelled, account.email == email else { return }
                self.lists = lists
                tasksByList = tasks
                if selectedListID == nil || !lists.contains(where: { $0.id == selectedListID }) {
                    selectedListID = lists.first?.id
                }
                lastSynced = Date()
                isShowingCache = false
                errorMessage = nil
                saveCache()
            } catch {
                guard !Task.isCancelled, account.email == email else { return }
                isShowingCache = !lists.isEmpty
                errorMessage = Self.describe(error)
            }
        }
    }

    // MARK: - Changes
    // Each change shows on screen immediately, marked pending, and is reverted with a message
    // if Google rejects it. Nothing is retried automatically, so a failure can't create duplicates.

    /// Tasks with a change waiting for Google; their controls are disabled to avoid double submits.
    private(set) var pendingTaskIDs: Set<String> = []
    private(set) var isAddingTask = false
    /// Message for a change that failed; shown as a dismissible banner.
    var changeError: String?

    func listID(ofTask taskID: String) -> String? {
        tasksByList.first { $0.value.contains { $0.id == taskID } }?.key
    }

    func task(withID taskID: String) -> GTask? {
        tasksByList.values.lazy.flatMap { $0 }.first { $0.id == taskID }
    }

    /// Creates a task at the top of the selected list. Returns false when it wasn't saved.
    func addTask(title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isAddingTask, let listID = selectedListID else { return false }
        isAddingTask = true
        defer { isAddingTask = false }
        do {
            let task = try await api.createTask(in: listID, title: title)
            tasksByList[listID, default: []].insert(task, at: 0)
            didChangeTasks()
            return true
        } catch {
            fail("Couldn't add “\(title)”.", error)
            return false
        }
    }

    func setCompleted(_ completed: Bool, task: GTask) {
        var changed = task
        changed.status = completed ? "completed" : "needsAction"
        changed.completed = completed ? ISO8601DateFormatter().string(from: Date()) : nil
        let fields: [String: Any] = completed ? ["status": "completed"] : ["status": "needsAction", "completed": NSNull()]
        apply(changed, original: task, fields: fields,
              failure: completed ? "Couldn't complete “\(task.displayTitle)”." : "Couldn't reopen “\(task.displayTitle)”.")
    }

    /// Saves edits from the task editor. Returns false (keeping the editor open) when Google rejects them.
    func updateTask(_ task: GTask, title: String, notes: String, due: DueDate?) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let listID = listID(ofTask: task.id) else { return false }
        let fields: [String: Any] = [
            "title": title,
            "notes": notes.isEmpty ? NSNull() : notes,
            "due": due.map { $0.rfc3339 as Any } ?? NSNull(),
        ]
        pendingTaskIDs.insert(task.id)
        defer { pendingTaskIDs.remove(task.id) }
        do {
            let saved = try await api.updateTask(task.id, in: listID, fields: fields)
            replace(saved, in: listID)
            didChangeTasks()
            return true
        } catch {
            fail("Couldn't save “\(title)”.", error)
            return false
        }
    }

    func deleteTask(_ task: GTask) {
        guard let listID = listID(ofTask: task.id), !pendingTaskIDs.contains(task.id) else { return }
        let before = tasksByList[listID] ?? []
        tasksByList[listID]?.removeAll { $0.id == task.id || $0.parent == task.id }
        pendingTaskIDs.insert(task.id)
        Task {
            defer { pendingTaskIDs.remove(task.id) }
            do {
                try await api.deleteTask(task.id, in: listID)
                didChangeTasks()
            } catch {
                tasksByList[listID] = before
                fail("Couldn't delete “\(task.displayTitle)”.", error)
            }
        }
    }

    func createList(title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        do {
            let list = try await api.createList(title: title)
            lists.append(list)
            tasksByList[list.id] = []
            selectedListID = list.id
            didChangeTasks()
            return true
        } catch {
            fail("Couldn't create “\(title)”.", error)
            return false
        }
    }

    func renameList(_ list: GTaskList, to title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != list.title else { return !title.isEmpty }
        do {
            let renamed = try await api.renameList(list.id, title: title)
            if let index = lists.firstIndex(where: { $0.id == list.id }) { lists[index] = renamed }
            didChangeTasks()
            return true
        } catch {
            fail("Couldn't rename “\(list.title)”.", error)
            return false
        }
    }

    /// Deletes the list and all its tasks in Google.
    func deleteList(_ list: GTaskList) async {
        do {
            try await api.deleteList(list.id)
            lists.removeAll { $0.id == list.id }
            tasksByList[list.id] = nil
            if selectedListID == list.id { selectedListID = lists.first?.id }
            didChangeTasks()
        } catch {
            fail("Couldn't delete “\(list.title)”.", error)
        }
    }

    /// Shows `changed` right away, sends `fields` to Google, then keeps Google's version or reverts.
    private func apply(_ changed: GTask, original: GTask, fields: [String: Any], failure: String) {
        guard let listID = listID(ofTask: original.id), !pendingTaskIDs.contains(original.id) else { return }
        replace(changed, in: listID)
        pendingTaskIDs.insert(original.id)
        Task {
            defer { pendingTaskIDs.remove(original.id) }
            do {
                let saved = try await api.updateTask(original.id, in: listID, fields: fields)
                replace(saved, in: listID)
                didChangeTasks()
            } catch {
                replace(original, in: listID)
                fail(failure, error)
            }
        }
    }

    private func replace(_ task: GTask, in listID: String) {
        guard let index = tasksByList[listID]?.firstIndex(where: { $0.id == task.id }) else { return }
        tasksByList[listID]?[index] = task
    }

    private func didChangeTasks() {
        saveCache()
    }

    private func fail(_ action: String, _ error: Error) {
        changeError = "\(action) \(Self.describe(error))"
    }

    /// Orders open tasks the way Google Tasks does (by position, subtasks under their parent)
    /// and lists completed tasks newest first. Hidden tasks were cleared in Google and are left out.
    static func arrange(_ tasks: [GTask]) -> (open: [TaskRowItem], completed: [GTask]) {
        let open = tasks.filter { !$0.isCompleted && $0.hidden != true }
        let openIDs = Set(open.map(\.id))
        let byPosition: (GTask, GTask) -> Bool = { ($0.position ?? "") < ($1.position ?? "") }
        let topLevel = open.filter { $0.parent == nil || !openIDs.contains($0.parent!) }.sorted(by: byPosition)
        var rows: [TaskRowItem] = []
        for task in topLevel {
            rows.append(TaskRowItem(task: task, depth: 0))
            rows += open.filter { $0.parent == task.id }.sorted(by: byPosition).map { TaskRowItem(task: $0, depth: 1) }
        }
        let completed = tasks
            .filter { $0.isCompleted && $0.hidden != true }
            .sorted { ($0.completed ?? "") > ($1.completed ?? "") }
        return (rows, completed)
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return "You're offline."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Offline copy

    private struct Snapshot: Codable {
        let email: String
        var lists: [GTaskList]
        var tasks: [String: [GTask]]
        var selectedListID: String?
        var savedAt: Date
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "iForgor/google-cache.json")
    }

    private func loadCache(for email: String) {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.email == email else { return Self.deleteCache() }
            lists = snapshot.lists
            tasksByList = snapshot.tasks
            selectedListID = snapshot.selectedListID ?? snapshot.lists.first?.id
            lastSynced = snapshot.savedAt
            isShowingCache = true
        } catch {
            // An unreadable copy is only a cache; the refresh that follows replaces it.
            Self.deleteCache()
        }
    }

    private func saveCache() {
        guard let email = account.email, !lists.isEmpty, let lastSynced else { return }
        let snapshot = Snapshot(email: email, lists: lists, tasks: tasksByList,
                                selectedListID: selectedListID, savedAt: lastSynced)
        do {
            try FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: Self.cacheURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't save the offline copy. \(error.localizedDescription)"
        }
    }

    private static func deleteCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
