import AppKit
import Foundation
import Observation
import UserNotifications

/// A reminder time for a Google task. Google Tasks can't store times, so reminders live on this Mac.
nonisolated struct Reminder: Codable, Hashable {
    let taskID: String
    var listID: String
    var title: String
    var date: Date
}

/// Stores reminders and keeps macOS's scheduled notifications in step with them.
/// Each notification uses the task ID as its identifier, so rescheduling replaces rather than duplicates.
@MainActor
@Observable
final class ReminderCenter {
    private(set) var reminders: [String: Reminder] = [:]
    var message: String?

    static let categoryID = "TASK_REMINDER"
    static let completeAction = "COMPLETE"
    static let snoozeAction = "SNOOZE"

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    init() {
        load()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [
                UNNotificationAction(identifier: Self.completeAction, title: "Mark as done"),
                UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 10 minutes"),
            ], intentIdentifiers: []),
        ])
    }

    func reminder(forTask taskID: String) -> Reminder? { reminders[taskID] }

    /// Saves and schedules a reminder, asking for notification permission the first time.
    /// Returns false (with `message` set) when it couldn't be scheduled.
    func set(_ date: Date, for task: GTask, listID: String) async -> Bool {
        guard date > Date() else {
            message = "Pick a reminder time in the future."
            return false
        }
        guard await ensureAuthorized() else { return false }
        let reminder = Reminder(taskID: task.id, listID: listID, title: task.displayTitle, date: date)
        do {
            try await schedule(reminder)
        } catch {
            message = "Couldn't schedule the reminder. \(error.localizedDescription)"
            return false
        }
        reminders[task.id] = reminder
        save()
        return true
    }

    func remove(taskID: String) {
        guard reminders.removeValue(forKey: taskID) != nil else { return }
        center.removePendingNotificationRequests(withIdentifiers: [taskID])
        save()
    }

    func snooze(taskID: String, minutes: Int = 10) async {
        guard var reminder = reminders[taskID] else { return }
        reminder.date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        do {
            try await schedule(reminder)
            reminders[taskID] = reminder
            save()
        } catch {
            message = "Couldn't snooze the reminder. \(error.localizedDescription)"
        }
    }

    /// Applies Google's current tasks: drops reminders for completed, deleted, or past tasks and
    /// reschedules ones whose title or list changed. Call only with a complete set of lists.
    func reconcile(with tasksByList: [String: [GTask]], now: Date = Date()) {
        let plan = Self.plan(reminders: reminders, tasksByList: tasksByList, now: now)
        guard plan.keep != reminders else { return }
        if !plan.removed.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.removed)
        }
        for (id, reminder) in plan.keep where reminders[id] != reminder {
            Task {
                do {
                    try await schedule(reminder)
                } catch {
                    message = "Couldn't update the reminder for “\(reminder.title)”. \(error.localizedDescription)"
                }
            }
        }
        reminders = plan.keep
        save()
    }

    /// Cancels everything, e.g. on sign-out.
    func removeAll() {
        center.removePendingNotificationRequests(withIdentifiers: Array(reminders.keys))
        reminders = [:]
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    /// Pure decision behind `reconcile`, separated so it can be tested without notifications.
    static func plan(reminders: [String: Reminder], tasksByList: [String: [GTask]], now: Date)
        -> (keep: [String: Reminder], removed: [String]) {
        var located: [String: (task: GTask, listID: String)] = [:]
        for (listID, tasks) in tasksByList {
            for task in tasks { located[task.id] = (task, listID) }
        }
        var keep: [String: Reminder] = [:]
        var removed: [String] = []
        for (id, reminder) in reminders {
            guard let (task, listID) = located[id], !task.isCompleted, task.hidden != true, reminder.date > now else {
                removed.append(id)
                continue
            }
            var updated = reminder
            updated.title = task.displayTitle
            updated.listID = listID
            keep[id] = updated
        }
        return (keep, removed.sorted())
    }

    private func ensureAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                if try await center.requestAuthorization(options: [.alert, .sound]) { return true }
            } catch {
                message = "Couldn't ask for notification permission. \(error.localizedDescription)"
                return false
            }
            fallthrough
        default:
            message = "Notifications are off for iForgor. Turn them on in System Settings › Notifications."
            return false
        }
    }

    private func schedule(_ reminder: Reminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Reminder"
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = reminder.listID
        content.userInfo = ["taskID": reminder.taskID, "listID": reminder.listID]
        // Wall-clock components fire after sleep, unlike an interval trigger.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.taskID, content: content, trigger: trigger))
    }

    // MARK: - Storage

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "iForgor/reminders.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            reminders = try JSONDecoder().decode([String: Reminder].self, from: data)
        } catch {
            // Move the unreadable file aside so the next save doesn't overwrite it.
            let backup = Self.fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: Self.fileURL, to: backup)
            message = "Saved reminders couldn't be read and were set aside. \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(reminders).write(to: Self.fileURL, options: .atomic)
        } catch {
            message = "Couldn't save reminders. \(error.localizedDescription)"
        }
    }
}

extension Date {
    /// "6:00 PM" today, "Tomorrow 9:00 AM", otherwise "Nov 14, 9:00 AM".
    var reminderLabel: String {
        let time = formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(self) { return time }
        if Calendar.current.isDateInTomorrow(self) { return "Tomorrow \(time)" }
        return formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
