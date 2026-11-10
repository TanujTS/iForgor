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
    @State private var editingTaskID: String?
    @State private var newTitle = ""
    @FocusState private var addFieldFocused: Bool
    @State private var listEditor: ListEditor?
    @State private var listToDelete: GTaskList?

    /// The inline list-name field: creating a new list, or renaming an existing one.
    private struct ListEditor: Equatable {
        var renaming: GTaskList?
        var name: String
    }

    private var arrangement: (open: [TaskRowItem], completed: [GTask]) { TasksModel.arrange(model.selectedTasks) }

    var body: some View {
        let arrangement = arrangement
        VStack(spacing: 0) {
            header(openCount: arrangement.open.count)
            listPills
            if model.selectedList != nil { quickAdd }
            taskList(arrangement)
            if let error = model.changeError ?? model.reminders.message { errorBanner(error) }
            footer
        }
        .animation(Theme.spring, value: model.changeError)
        .animation(Theme.spring, value: model.reminders.message)
        .onAppear {
            model.refreshIfStale()
            revealFocusedTask()
        }
        .onChange(of: model.focusedTaskID) { revealFocusedTask() }
        .onChange(of: model.selectedListID) { if editingTaskID.flatMap(model.listID(ofTask:)) != model.selectedListID { editingTaskID = nil } }
        .alert("Delete “\(listToDelete?.title ?? "")”?", isPresented: Binding(
            get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let list = listToDelete { Task { await model.deleteList(list) } }
            }
        } message: {
            Text("This deletes the list and all of its tasks in Google Tasks.")
        }
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
            .keyboardShortcut("r")
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
                    if listEditor?.renaming?.id == list.id {
                        listNameField
                    } else {
                        pill(list)
                    }
                }
                if listEditor != nil && listEditor?.renaming == nil {
                    listNameField
                } else {
                    Button {
                        withAnimation(Theme.spring) { listEditor = ListEditor(renaming: nil, name: "") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Theme.ring, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .help("New list")
                    .accessibilityLabel("New list")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private func pill(_ list: GTaskList) -> some View {
        let isSelected = list.id == model.selectedListID
        return Button {
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
        .contextMenu {
            Button("Rename…") { listEditor = ListEditor(renaming: list, name: list.title) }
            Button("Delete list…", role: .destructive) { listToDelete = list }
        }
    }

    private var listNameField: some View {
        TextField("List name", text: Binding(
            get: { listEditor?.name ?? "" }, set: { listEditor?.name = $0 }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .frame(width: 110)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
        .onSubmit(saveList)
        .onExitCommand { withAnimation(Theme.spring) { listEditor = nil } }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func saveList() {
        guard let editor = listEditor else { return }
        Task {
            let saved = if let list = editor.renaming {
                await model.renameList(list, to: editor.name)
            } else {
                await model.createList(title: editor.name)
            }
            if saved || editor.name.trimmingCharacters(in: .whitespaces).isEmpty {
                withAnimation(Theme.spring) { listEditor = nil }
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(addFieldFocused ? Theme.accent : Theme.muted)
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addFieldFocused)
                .disabled(model.isAddingTask)
                .onSubmit(addTask)
            if model.isAddingTask {
                ProgressView().controlSize(.mini)
            } else if !newTitle.isEmpty {
                Text("⏎")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 5)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline, lineWidth: 1))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.accent.opacity(addFieldFocused ? 0.5 : 0), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: addFieldFocused)
        .animation(.easeOut(duration: 0.15), value: newTitle.isEmpty)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func addTask() {
        let title = newTitle
        Task {
            if await model.addTask(title: title) {
                withAnimation(Theme.spring) { newTitle = "" }
                addFieldFocused = true
            }
        }
    }

    private func taskList(_ arrangement: (open: [TaskRowItem], completed: [GTask])) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.lists.isEmpty {
                    EmptyState(symbol: "tray", title: model.isRefreshing ? "Loading your lists…" : "No lists yet",
                               detail: model.isRefreshing ? nil : "Create one with the + button.")
                } else if arrangement.open.isEmpty && arrangement.completed.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "All clear", detail: "Nothing to do in this list.")
                } else {
                    ForEach(arrangement.open) { row in
                        taskView(row.task, depth: row.depth)
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
            .animation(Theme.spring, value: arrangement.completed)
            .animation(Theme.spring, value: showCompleted)
            .animation(Theme.spring, value: editingTaskID)
        }
        .scrollIndicators(.never)
        .id(model.selectedListID)
        .transition(.opacity)
    }

    @ViewBuilder
    private func taskView(_ task: GTask, depth: Int) -> some View {
        if editingTaskID == task.id {
            TaskEditorCard(task: task, model: model) { editingTaskID = nil }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        } else {
            TaskRow(task: task, depth: depth,
                    isPending: model.pendingTaskIDs.contains(task.id),
                    reminder: model.reminders.reminder(forTask: task.id)?.date,
                    onToggle: { model.setCompleted(!task.isCompleted, task: task) },
                    onEdit: { editingTaskID = task.id },
                    onDelete: { model.deleteTask(task) })
        }
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
                        .contentTransition(.numericText())
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
                    taskView(task, depth: 0)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.overdue)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { dismissBanner() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("Dismiss")
        }
        .font(.system(size: 12))
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: message) {
            try? await Task.sleep(for: .seconds(8))
            if (model.changeError ?? model.reminders.message) == message { dismissBanner() }
        }
    }

    private func dismissBanner() {
        model.changeError = nil
        model.reminders.message = nil
    }

    /// Switches to the focused task's list and opens it in the editor.
    private func revealFocusedTask() {
        guard let taskID = model.focusedTaskID else { return }
        model.focusedTaskID = nil
        guard let listID = model.listID(ofTask: taskID) else { return }
        model.selectedListID = listID
        if model.task(withID: taskID)?.isCompleted == true { showCompleted = true }
        editingTaskID = taskID
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
