import AppKit
import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("iForgor", systemImage: "checkmark.circle") {
            PanelView(model: appDelegate.tasks)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app's long-lived models; macOS delivers the sign-in redirect URL here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let account: GoogleAccount
    let tasks: TasksModel

    override init() {
        account = GoogleAccount()
        tasks = TasksModel(account: account)
        super.init()
        account.onAccountChange = { [tasks] email in tasks.accountChanged(to: email) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await account.restore() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await account.handleRedirect(url) }
        }
    }
}
