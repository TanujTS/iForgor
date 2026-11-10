import SwiftUI

/// Account window; a separate window stays visible while the user is in the browser, unlike the menu bar panel.
struct AccountView: View {
    let account: GoogleAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Google account")
                .font(.title3.bold())

            switch account.status {
            case .checking:
                ProgressView("Checking saved sign-in…")
            case .signingIn:
                ProgressView("Finish signing in in your browser…")
                Button("Cancel") { account.cancelSignIn() }
            case .signedOut:
                Text("Sign in to sync iForgor with Google Tasks.")
                    .foregroundStyle(.secondary)
                Button("Sign in with Google") { account.signIn() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!GoogleConfig.isConfigured)
                if !GoogleConfig.isConfigured {
                    Text("Add your OAuth client ID in GoogleConfig.swift, then rebuild.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .signedIn(let email):
                LabeledContent("Signed in as", value: email)
                LabeledContent("Task lists", value: account.taskListCount.map(String.init) ?? "—")
                HStack {
                    Button("Check connection") {
                        Task { await account.checkConnection() }
                    }
                    .disabled(account.isCheckingConnection)
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        Task { await account.signOut() }
                    }
                }
            }

            if let message = account.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}
