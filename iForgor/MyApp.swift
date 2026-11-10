import AppKit
import SwiftUI
import UserNotifications

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("iForgor", systemImage: "checkmark.circle") {
            PanelView(model: appDelegate.tasks)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app's long-lived models; macOS delivers the sign-in redirect URL and notification responses here.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let account: GoogleAccount
    let reminders: ReminderCenter
    let tasks: TasksModel

    override init() {
        account = GoogleAccount()
        reminders = ReminderCenter()
        tasks = TasksModel(account: account, reminders: reminders)
        super.init()
        account.onAccountChange = { [tasks] email in tasks.accountChanged(to: email) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { await account.restore() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await account.handleRedirect(url) }
        }
    }

    /// Shows reminders as banners even while the panel is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let taskID = response.notification.request.content.userInfo["taskID"] as? String
        await MainActor.run { handleNotification(action: action, taskID: taskID) }
    }

    /// Mark as done, snooze, or (on a plain click) open the panel at the task.
    private func handleNotification(action: String, taskID: String?) {
        guard let taskID else { return }
        switch action {
        case ReminderCenter.completeAction:
            if let task = tasks.task(withID: taskID) {
                tasks.setCompleted(true, task: task)
            } else {
                reminders.remove(taskID: taskID)
            }
        case ReminderCenter.snoozeAction:
            Task { await reminders.snooze(taskID: taskID) }
        default:
            reminders.remove(taskID: taskID)
            tasks.focusedTaskID = taskID
            MenuBarPanel.open()
        }
    }
}

/// SwiftUI has no API to open a MenuBarExtra panel; clicking its status item does the same.
enum MenuBarPanel {
    static func open() {
        NSApplication.shared.activate()
        let statusWindows = NSApplication.shared.windows.filter { $0.className.contains("StatusBarWindow") }
        let panelIsOpen = NSApplication.shared.windows.contains {
            $0.isVisible && !statusWindows.contains($0) && $0.className.contains("MenuBarExtra")
        }
        guard !panelIsOpen else { return }
        for window in statusWindows {
            if let contentView = window.contentView, let button = statusButton(in: contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}
