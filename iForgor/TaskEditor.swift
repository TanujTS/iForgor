import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskItem
    @State private var hasScheduledDate: Bool
    @State private var scheduledDate: Date
    let onSave: (TaskItem) -> Void

    /// Edits a value copy so Cancel leaves the original task unchanged.
    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void) {
        _draft = State(initialValue: task)
        _hasScheduledDate = State(initialValue: task.scheduledDate != nil)
        _scheduledDate = State(initialValue: task.scheduledDate ?? Date())
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit task")
                .font(.title3.bold())

            Form {
                TextField("Title", text: $draft.title)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("Completed", isOn: $draft.isCompleted)
                Toggle("Scheduled date", isOn: $hasScheduledDate)
                if hasScheduledDate {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                }
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// Validates and normalizes the draft, then commits it once before closing the editor.
    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { return }
        draft.scheduledDate = hasScheduledDate ? Calendar.current.startOfDay(for: scheduledDate) : nil
        onSave(draft)
        dismiss()
    }
}
