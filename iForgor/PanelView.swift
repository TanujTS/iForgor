import AppKit
import SwiftUI

/// Root of the menu bar panel: sign-in screen or the tasks panel.
struct PanelView: View {
    let model: TasksModel
    private var account: GoogleAccount { model.account }

    var body: some View {
        Group {
            switch account.status {
            case .checking:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut, .signingIn:
                SignInView(account: account)
            case .signedIn:
                TasksPanel(model: model)
            }
        }
        .frame(width: 360, height: 540)
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .animation(Theme.spring, value: account.status)
    }
}

private struct SignInView: View {
    let account: GoogleAccount

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.ink)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.background))
                VStack(spacing: 6) {
                    Text("iForgor").font(.system(size: 18, weight: .semibold))
                    Text("Your Google Tasks, one click away in the menu bar.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                }
                if account.status == .signingIn {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finish signing in in your browser…").font(.system(size: 13))
                        }
                        Button("Cancel") { account.cancelSignIn() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    .transition(.opacity)
                } else {
                    Button { account.signIn() } label: {
                        Text("Continue with Google")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Theme.background)
                    }
                    .buttonStyle(PressableStyle())
                    .keyboardShortcut(.defaultAction)
                    .transition(.opacity)
                }
                Text(account.message ?? "Opens your browser. Reminders stay on this Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .frame(maxHeight: .infinity)
            .padding(32)

            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
        }
    }
}

private struct TasksPanel: View {
    let model: TasksModel
    @Namespace private var pillNamespace
    @State private var showCompleted = false

    private var arrangement: (open: [TaskRowItem], completed: [GTask]) { TasksModel.arrange(model.selectedTasks) }

    var body: some View {
        let arrangement = arrangement
        VStack(spacing: 0) {
            header(openCount: arrangement.open.count)
            listPills
            taskList(arrangement)
            footer
        }
        .onAppear { model.refreshIfStale() }
    }

    private func header(openCount: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedList?.title ?? "Tasks")
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(openCount == 1 ? "1 open" : "\(openCount) open")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: model.isRefreshing)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh")
            .accessibilityLabel("Refresh")
            AccountMenu(model: model)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var listPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.lists) { list in
                    let isSelected = list.id == model.selectedListID
                    Button {
                        withAnimation(Theme.spring) { model.selectedListID = list.id }
                    } label: {
                        Text(list.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundStyle(isSelected ? Theme.background : Theme.secondaryInk)
                            .background {
                                if isSelected {
                                    Capsule().fill(Theme.ink).matchedGeometryEffect(id: "pill", in: pillNamespace)
                                } else {
                                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private func taskList(_ arrangement: (open: [TaskRowItem], completed: [GTask])) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.lists.isEmpty {
                    EmptyState(symbol: "tray", title: model.isRefreshing ? "Loading your lists…" : "No lists yet",
                               detail: model.isRefreshing ? nil : "Create a list in Google Tasks, then refresh.")
                } else if arrangement.open.isEmpty && arrangement.completed.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "All clear", detail: "Nothing to do in this list.")
                } else {
                    ForEach(arrangement.open) { row in
                        TaskRow(task: row.task, depth: row.depth)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                    if !arrangement.completed.isEmpty {
                        completedSection(arrangement.completed)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .animation(Theme.spring, value: arrangement.open)
            .animation(Theme.spring, value: showCompleted)
        }
        .scrollIndicators(.never)
        .id(model.selectedListID)
        .transition(.opacity)
    }

    private func completedSection(_ completed: [GTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showCompleted ? 90 : 0))
                    Text("Completed · \(completed.count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            if showCompleted {
                ForEach(completed) { task in
                    TaskRow(task: task, depth: 0)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(statusText(now: context.date))
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }

    private var statusColor: Color {
        if model.isRefreshing { return Theme.warning }
        if model.errorMessage != nil { return Theme.overdue }
        return Theme.success
    }

    private func statusText(now: Date) -> String {
        if model.isRefreshing { return "Syncing…" }
        if let error = model.errorMessage {
            return model.isShowingCache ? "\(error) Showing saved copy." : error
        }
        guard let lastSynced = model.lastSynced else { return "Not synced yet" }
        if now.timeIntervalSince(lastSynced) < 60 { return "Synced just now" }
        return "Synced " + lastSynced.formatted(.relative(presentation: .named))
    }
}

private struct AccountMenu: View {
    let model: TasksModel

    var body: some View {
        Menu {
            if let email = model.account.email {
                Text(email)
            }
            Divider()
            Button("Sign out") { Task { await model.account.signOut() } }
            Button("Quit iForgor") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Text(String(model.account.email?.first ?? "?").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accentSoft, in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Account")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.ring)
            Text(title).font(.system(size: 13, weight: .medium))
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}

/// Slight shrink on press, used for pills and primary buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Muted icon button with a soft hover background.
struct IconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.muted)
            .background(Theme.field.opacity(isHovering || configuration.isPressed ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
