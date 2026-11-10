import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var store: TaskStore
    let account: GoogleAccount
    @Environment(\.openWindow) private var openWindow
    @State private var newTaskTitle = ""
    @State private var editingTask: TaskDraft?
    @State private var listName = ""
    @State private var isRenamingList = false
    @State private var showingListEditor = false
    @State private var showingDeleteConfirmation = false

    private var lists: [TaskList] { store.lists }
    private var selectedListID: UUID? { store.selectedListID }
    private var selectedList: TaskList? { store.selectedList }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("iForgor")
                    .font(.title3.bold())
                Spacer()
                Button(account.email ?? "Sign in with Google") {
                    openWindow(id: "account")
                    NSApplication.shared.activate()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            HStack {
                Picker("List", selection: Binding(get: { store.selectedListID }, set: store.selectList)) {
                    if lists.isEmpty {
                        Text("No lists").tag(nil as UUID?)
                    }
                    ForEach(lists) { list in
                        Text(list.title).tag(Optional(list.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Menu {
                    Button("New list…", systemImage: "plus") {
                        isRenamingList = false
                        listName = ""
                        showingListEditor = true
                    }
                    Button("Rename list…", systemImage: "pencil") {
                        isRenamingList = true
                        listName = selectedList?.title ?? ""
                        showingListEditor = true
                    }
                    .disabled(selectedList == nil)
                    Button("Delete list…", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(selectedList == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Manage lists")
            }
            .disabled(store.isUnavailable)

            HStack(spacing: 8) {
                TextField("New task", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button("Add", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(selectedList == nil || store.isUnavailable)

            ScrollView {
                if let list = selectedList {
                    if list.tasks.isEmpty {
                        ContentUnavailableView("No tasks yet", systemImage: "checklist",
                                               description: Text("Add a task to this list above."))
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(list.orderedTasks) { task in
                                taskRow(task: task)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Reset row state when a different list is selected.
                        .id(selectedListID)
                    }
                } else {
                    ContentUnavailableView("No lists", systemImage: "list.bullet",
                                           description: Text("Create a list using the list menu."))
                }
            }
            .frame(height: 280)
            .disabled(store.isUnavailable)

            Divider()

            HStack {
                if let list = selectedList {
                    Text("\(list.tasks.filter { !$0.isCompleted }.count) remaining · \(list.tasks.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit iForgor") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
        .alert("Storage problem", isPresented: Binding(
            get: { store.errorMessage != nil && editingTask == nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: selectedListID) { newTaskTitle = "" }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task, onSave: store.updateTask)
        }
        .alert(isRenamingList ? "Rename list" : "New list", isPresented: $showingListEditor) {
            TextField("List name", text: $listName)
            Button("Cancel", role: .cancel) { }
            Button("Save", action: saveList)
                .disabled(listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete this list?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: deleteList)
        } message: {
            Text("Deleting “\(selectedList?.title ?? "")” also deletes all of its local tasks.")
        }
    }

    /// Routes checkbox changes through explicit saving and edits through a separate value draft.
    private func taskRow(task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: Binding(get: { task.isCompleted }, set: { store.setCompleted($0, task: task) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let date = task.scheduledDate {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.checkbox)

            Menu {
                Button("Edit task…", systemImage: "pencil") {
                    editingTask = TaskDraft(task: task)
                }
                Button("Delete task", systemImage: "trash", role: .destructive) {
                    store.deleteTask(task)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(task.title)")
        }
    }

    private func addTask() {
        if store.addTask(title: newTaskTitle) { newTaskTitle = "" }
    }

    private func saveList() {
        if isRenamingList {
            store.renameSelectedList(title: listName)
        } else {
            store.addList(title: listName)
        }
    }

    private func deleteList() {
        store.deleteSelectedList()
        newTaskTitle = ""
    }
}

#Preview {
    ContentPreview()
}

/// Preview data stays in memory and never reads or writes the user's database.
private struct ContentPreview: View {
    private let storage = Result { try TaskStore(configuration: .init(isStoredInMemoryOnly: true)) }

    var body: some View {
        switch storage {
        case .success(let store): ContentView(store: store, account: GoogleAccount())
        case .failure: Text("Could not create preview storage.")
        }
    }
}
