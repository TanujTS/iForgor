import AppKit
import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store: TaskStore?
    @State private var storageFailure: String?

    init() {
        do {
            _store = State(initialValue: try TaskStore())
        } catch {
            let failure = error as NSError
            _storageFailure = State(initialValue: "Saved tasks could not be opened. Storage may be damaged or unavailable. Existing data has not been reset. Error: \(failure.domain) (\(failure.code)).")
        }
    }

    private var account: GoogleAccount { appDelegate.account }

    var body: some Scene {
        MenuBarExtra("iForgor", systemImage: "checklist") {
            if let store {
                ContentView(store: store, account: account)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Could not open storage").font(.headline)
                    Text(storageFailure ?? "Storage is unavailable.")
                    Button("Retry", action: openStore)
                    Button("Quit iForgor") { NSApplication.shared.terminate(nil) }
                }
                .padding(16)
                .frame(width: 360)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Google Account", id: "account") {
            AccountView(account: account)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    /// Retries the same database; never replaces failed storage with an empty or in-memory store.
    private func openStore() {
        do {
            store = try TaskStore()
            storageFailure = nil
        } catch {
            let failure = error as NSError
            storageFailure = "Saved tasks still could not be opened. Existing data has not been reset. Error: \(failure.domain) (\(failure.code))."
        }
    }
}

/// Owns the Google account so it can receive the sign-in redirect URL, which macOS delivers to the app delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let account = GoogleAccount()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await account.restore() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSApplication.shared.activate()
        for url in urls {
            Task { await account.handleRedirect(url) }
        }
    }
}
