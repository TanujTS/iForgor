import Foundation

/// Checks app logic that needs no Google account, network, or UI. Run with Tests/run.sh.
@main
struct LogicTests {
    static func main() throws {
        try decodesGooglePages()
        dueDatesKeepTheirDay()
        relativeLabels()
        arrangesLikeGoogle()
        print("PASS: decoding, due dates across time zones, relative labels, ordering")
    }

    /// Sample shaped like a Google Tasks list response, including fields the app ignores.
    static func decodesGooglePages() throws {
        let json = """
        {"kind":"tasks#tasks","etag":"x","items":[
          {"kind":"tasks#task","id":"a","title":"Buy milk","status":"needsAction","due":"2026-11-12T00:00:00.000Z","position":"00000000000000000001","links":[]},
          {"kind":"tasks#task","id":"b","title":"Done","status":"completed","completed":"2026-11-10T10:00:00.000Z","hidden":true}
        ]}
        """
        struct Page: Decodable { let items: [GTask] }
        let tasks = try JSONDecoder().decode(Page.self, from: Data(json.utf8)).items
        check(tasks.count == 2 && tasks[0].dueDate == DueDate(year: 2026, month: 11, day: 12), "decode task fields")
        check(tasks[1].isCompleted && tasks[1].hidden == true, "decode completed/hidden")
    }

    /// Google's midnight-UTC due date must show as the same calendar day in every time zone.
    static func dueDatesKeepTheirDay() {
        let due = DueDate(rfc3339: "2026-03-01T00:00:00.000Z")!
        for zone in ["America/Los_Angeles", "Asia/Kolkata", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            check(DueDate(due.date(calendar: calendar), calendar: calendar) == due, "round trip in \(zone)")
        }
        check(due.rfc3339 == "2026-03-01T00:00:00.000Z", "encode RFC 3339")
        check(DueDate(rfc3339: "garbage") == nil, "reject invalid date")
    }

    static func relativeLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 30))!
        check(DueDate(year: 2026, month: 11, day: 11).relativeLabel(today: now, calendar: calendar).isToday, "today")
        check(DueDate(year: 2026, month: 11, day: 12).relativeLabel(today: now, calendar: calendar).text == "Tomorrow", "tomorrow")
        check(DueDate(year: 2026, month: 11, day: 10).relativeLabel(today: now, calendar: calendar).isOverdue, "overdue")
    }

    static func arrangesLikeGoogle() {
        func task(_ id: String, _ position: String, parent: String? = nil, done: Bool = false, hidden: Bool? = nil) -> GTask {
            GTask(id: id, title: id, status: done ? "completed" : "needsAction", parent: parent, position: position, hidden: hidden)
        }
        let result = TasksModel.arrange([
            task("second", "2"), task("first", "1"), task("child", "1", parent: "second"),
            task("done", "0", done: true), task("cleared", "0", done: true, hidden: true),
        ])
        check(result.open.map(\.id) == ["first", "second", "child"], "position order with subtasks under parent")
        check(result.open.last?.depth == 1, "subtask depth")
        check(result.completed.map(\.id) == ["done"], "completed excludes hidden")
    }

    static func check(_ condition: Bool, _ name: String) {
        if !condition {
            print("FAIL: \(name)")
            exit(1)
        }
    }
}
