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
