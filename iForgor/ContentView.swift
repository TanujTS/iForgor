import AppKit
import SwiftUI

struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
    var isCompleted = false
    var notes = ""
    var scheduledDate: Date?
}

struct TaskList: Identifiable {
    let id = UUID()
    var title: String
    var tasks: [TaskItem] = []

    static let samples = [
        TaskList(title: "Personal", tasks: [
            TaskItem(title: "This is task 1"),
            TaskItem(title: "Learn swift"),
            TaskItem(title: "This is a longer task to verify that the text wraps inside the panel")
        ]),
        TaskList(title: "Work", tasks: [TaskItem(title: "Plan the week")])
    ]
}

struct ContentView: View {
    @State private var lists = TaskList.samples
    @State private var selectedListID: UUID? = TaskList.samples[0].id
    @State private var newTaskTitle = ""
    @State private var editingTask: TaskItem?
    @State private var listName = ""
    @State private var isRenamingList = false
    @State private var showingListEditor = false
    @State private var showingDeleteConfirmation = false

    private var selectedListIndex: Int? {
        lists.firstIndex { $0.id == selectedListID }
    }

    private var selectedList: TaskList? {
        guard let index = selectedListIndex else { return nil }
        return lists[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("iForgor")
                    .font(.title3.bold())
                Spacer()
                Text("Local tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Picker("List", selection: $selectedListID) {
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

            HStack(spacing: 8) {
                TextField("New task", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button("Add", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(selectedList == nil)

            ScrollView {
                if let index = selectedListIndex {
                    if lists[index].tasks.isEmpty {
                        ContentUnavailableView("No tasks yet", systemImage: "checklist",
                                               description: Text("Add a task to this list above."))
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach($lists[index].tasks) { $task in
                                taskRow(task: $task)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Recreate row bindings when selection changes to a different list.
                        .id(selectedListID)
                    }
                } else {
                    ContentUnavailableView("No lists", systemImage: "list.bullet",
                                           description: Text("Create a list using the list menu."))
                }
            }
            .frame(height: 280)

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
        .onChange(of: selectedListID) { newTaskTitle = "" }
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task, onSave: saveTask)
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

    /// Renders one bound task; the menu edits a draft or removes this task by stable ID.
    private func taskRow(task: Binding<TaskItem>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: task.isCompleted) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.wrappedValue.title)
                        .strikethrough(task.wrappedValue.isCompleted)
                        .foregroundStyle(task.wrappedValue.isCompleted ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !task.wrappedValue.notes.isEmpty {
                        Text(task.wrappedValue.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let date = task.wrappedValue.scheduledDate {
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
                    editingTask = task.wrappedValue
                }
                Button("Delete task", systemImage: "trash", role: .destructive) {
                    deleteTask(id: task.wrappedValue.id)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(task.wrappedValue.title)")
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = selectedListIndex else { return }
        lists[index].tasks.append(TaskItem(title: title))
        newTaskTitle = ""
    }

    /// Commits an editor's copy by identity, preserving the original list and task ID.
    private func saveTask(_ updated: TaskItem) {
        for listIndex in lists.indices {
            if let taskIndex = lists[listIndex].tasks.firstIndex(where: { $0.id == updated.id }) {
                lists[listIndex].tasks[taskIndex] = updated
                return
            }
        }
        assertionFailure("The edited task must still belong to a local list.")
    }

    private func deleteTask(id: UUID) {
        guard let index = selectedListIndex else { return }
        lists[index].tasks.removeAll { $0.id == id }
    }

    /// Saves a validated list name; new lists become selected and start without tasks.
    private func saveList() {
        let title = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if isRenamingList {
            guard let index = selectedListIndex else { return }
            lists[index].title = title
        } else {
            let list = TaskList(title: title)
            lists.append(list)
            selectedListID = list.id
        }
    }

    /// Selects a surviving list, or clears selection to display the no-lists state.
    private func deleteList() {
        lists.removeAll { $0.id == selectedListID }
        selectedListID = lists.first?.id
        newTaskTitle = ""
    }
}

#Preview {
    ContentView()
}
