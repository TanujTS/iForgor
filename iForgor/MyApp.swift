import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        MenuBarExtra("iForgor", systemImage: "checklist") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
