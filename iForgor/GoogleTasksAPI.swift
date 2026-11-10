import Foundation

nonisolated struct GTaskList: Codable, Identifiable, Hashable {
    let id: String
    var title: String
}

/// A Google task. Only fields the app reads are decoded; PATCH requests send just the changed fields.
nonisolated struct GTask: Codable, Identifiable, Hashable {
    let id: String
    var title: String?
    var notes: String?
    var status: String?
    /// RFC 3339 timestamp; Google keeps only the date part.
    var due: String?
    var completed: String?
    var parent: String?
    var position: String?
    var hidden: Bool?

    var isCompleted: Bool { status == "completed" }
    var displayTitle: String { title?.isEmpty == false ? title! : "Untitled" }
    var dueDate: DueDate? { due.flatMap(DueDate.init(rfc3339:)) }
}

/// A calendar day without a time zone. Google Tasks deadlines are dates, so storing them as
/// a `Date` instant would shift the day when the Mac's time zone changes.
nonisolated struct DueDate: Hashable, Codable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads the leading "yyyy-MM-dd" of an RFC 3339 timestamp and ignores the time.
    init?(rfc3339: String) {
        let parts = rfc3339.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    var rfc3339: String { String(format: "%04d-%02d-%02dT00:00:00.000Z", year, month, day) }

    /// Local midnight of this day.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func < (lhs: DueDate, rhs: DueDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension DueDate {
    /// "Today", "Tomorrow", a weekday within the next week, otherwise a short date.
    func relativeLabel(today: Date = Date(), calendar: Calendar = .current) -> (text: String, isToday: Bool, isOverdue: Bool) {
        let start = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: start, to: date(calendar: calendar)).day ?? 0
        let text: String
        switch days {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case -1: text = "Yesterday"
        case 2...6: text = date(calendar: calendar).formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: start) == year
            text = date(calendar: calendar).formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                                                : .dateTime.month(.abbreviated).day().year())
        }
        return (text, days == 0, days < 0)
    }
}

/// Thin Google Tasks REST client. Every call reads all result pages and retries once after a 401
/// with a fresh access token.
struct GoogleTasksAPI {
    let account: GoogleAccount
    private static let base = "https://tasks.googleapis.com/tasks/v1/"

    func taskLists() async throws -> [GTaskList] {
        try await allPages(path: "users/@me/lists", query: [:])
    }

    /// Includes completed and hidden tasks so they can be shown and reopened.
    func tasks(in listID: String) async throws -> [GTask] {
        try await allPages(path: "lists/\(Self.escape(listID))/tasks",
                           query: ["showCompleted": "true", "showHidden": "true"])
    }

    func createTask(in listID: String, title: String) async throws -> GTask {
        try await send("POST", path: "lists/\(Self.escape(listID))/tasks", body: ["title": title])
    }

    /// `fields` values may be `NSNull()` to clear a field, e.g. the deadline.
    func updateTask(_ taskID: String, in listID: String, fields: [String: Any]) async throws -> GTask {
        try await send("PATCH", path: "lists/\(Self.escape(listID))/tasks/\(Self.escape(taskID))", body: fields)
    }

    func deleteTask(_ taskID: String, in listID: String) async throws {
        let _: Empty = try await send("DELETE", path: "lists/\(Self.escape(listID))/tasks/\(Self.escape(taskID))")
    }

    func createList(title: String) async throws -> GTaskList {
        try await send("POST", path: "users/@me/lists", body: ["title": title])
    }

    func renameList(_ listID: String, title: String) async throws -> GTaskList {
        try await send("PATCH", path: "users/@me/lists/\(Self.escape(listID))", body: ["title": title])
    }

    func deleteList(_ listID: String) async throws {
        let _: Empty = try await send("DELETE", path: "users/@me/lists/\(Self.escape(listID))")
    }

    private func allPages<Item: Decodable>(path: String, query: [String: String]) async throws -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            var pageQuery = query
            pageQuery["maxResults"] = "100"
            if let pageToken { pageQuery["pageToken"] = pageToken }
            let page: Page<Item> = try await send("GET", path: path, query: pageQuery)
            items += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }

    private func send<Response: Decodable>(_ method: String, path: String, query: [String: String] = [:],
                                           body: [String: Any]? = nil) async throws -> Response {
        var components = URLComponents(string: Self.base + path)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var (data, response) = try await authorized(request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            account.invalidateAccessToken()
            (data, response) = try await authorized(request)
        }
        try GoogleAccount.check(response, data)
        if Response.self == Empty.self { return Empty() as! Response }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func authorized(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("Bearer \(try await account.validAccessToken())", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
    }

    private static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }
}

private struct Page<Item: Decodable>: Decodable {
    let items: [Item]?
    let nextPageToken: String?
}

private struct Empty: Decodable {}
