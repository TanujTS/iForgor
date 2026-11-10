import SwiftUI

/// A task in the panel: round checkbox, title, notes preview, and deadline. Clicking it opens the editor.
struct TaskRow: View {
    let task: GTask
    let depth: Int
    var isPending = false
    var reminder: Date?
    var onToggle: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Checkbox(isOn: task.isCompleted)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-4)
            .padding(.top, 1)
            .disabled(isPending)
            .accessibilityLabel(task.isCompleted ? "Reopen \(task.displayTitle)" : "Complete \(task.displayTitle)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayTitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(task.isCompleted ? Theme.muted : Theme.ink)
                    .strikethrough(task.isCompleted, color: Theme.ring)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.isCompleted, let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if !task.isCompleted, task.dueDate != nil || reminder != nil {
                    HStack(spacing: 10) {
                        if let due = task.dueDate { DueLabel(due: due) }
                        if let reminder {
                            Label(reminder.reminderLabel, systemImage: "bell")
                                .labelStyle(CompactLabelStyle())
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12 + CGFloat(depth) * 28)
        .padding(.trailing, 12)
        .opacity(isPending ? 0.55 : 1)
        .background(Theme.field.opacity(isHovering ? 0.7 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button(task.isCompleted ? "Mark as not done" : "Mark as done", action: onToggle)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

/// The task row expanded in place for editing: title, notes, deadline, and delete.
struct TaskEditorCard: View {
    let task: GTask
    let model: TasksModel
    let onClose: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var due: DueDate?
    @State private var showingDatePicker = false
    @State private var reminderDate: Date?
    private let originalReminder: Date?
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(task: GTask, model: TasksModel, onClose: @escaping () -> Void) {
        self.task = task
        self.model = model
        self.onClose = onClose
        _title = State(initialValue: task.title ?? "")
        _notes = State(initialValue: task.notes ?? "")
        _due = State(initialValue: task.dueDate)
        originalReminder = model.reminders.reminder(forTask: task.id)?.date
        _reminderDate = State(initialValue: originalReminder)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Checkbox(isOn: task.isCompleted).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .focused($titleFocused)
                        .onSubmit(save)
                    TextField("Add notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1...5)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldRow(symbol: "calendar", title: "Deadline", value: due?.relativeLabel().text ?? "None",
                         valueColor: due == nil ? Theme.muted : Theme.accent)
                HStack(spacing: 6) {
                    chip("Today", day: 0)
                    chip("Tomorrow", day: 1)
                    chip("Next week", day: 7)
                    Button { showingDatePicker.toggle() } label: {
                        Image(systemName: "ellipsis").chipStyle(selected: false)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Pick a date")
                    .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                        DatePicker("Deadline", selection: Binding(
                            get: { due?.date() ?? Date() },
                            set: { due = DueDate($0); showingDatePicker = false }
                        ), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                    }
                    if due != nil {
                        Button { withAnimation(Theme.spring) { due = nil } } label: {
                            Image(systemName: "xmark").chipStyle(selected: false)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Clear deadline")
                    }
                }
            }
            .padding(.leading, 30)

            if !task.isCompleted {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(Theme.spring) { reminderDate = reminderDate == nil ? defaultReminderDate : nil }
                    } label: {
                        fieldRow(symbol: "bell", title: "Remind me", value: reminderDate?.reminderLabel ?? "Add",
                                 valueColor: reminderDate == nil ? Theme.muted : Theme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    if reminderDate != nil {
                        HStack {
                            DatePicker("Reminder", selection: Binding(
                                get: { reminderDate ?? defaultReminderDate }, set: { reminderDate = $0 }
                            ), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.field)
                            .labelsHidden()
                            .font(.system(size: 12))
                            Spacer()
                            Button { withAnimation(Theme.spring) { reminderDate = nil } } label: {
                                Image(systemName: "xmark").chipStyle(selected: false)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Remove reminder")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.leading, 30)
            }

            HStack {
                Button {
                    model.deleteTask(task)
                    onClose()
                } label: {
                    Image(systemName: "trash").font(.system(size: 12)).frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.danger)
                .accessibilityLabel("Delete task")
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 10)
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.mini) }
                        Text(isSaving ? "Saving" : "Save")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Theme.background)
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSave)
                .opacity(canSave || isSaving ? 1 : 0.4)
            }
            .padding(.leading, 30)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .onAppear { titleFocused = true }
        .onExitCommand(perform: onClose)
    }

    private func fieldRow(symbol: String, title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Label(title, systemImage: symbol).labelStyle(CompactLabelStyle())
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(valueColor).contentTransition(.opacity)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func chip(_ label: String, day offset: Int) -> some View {
        let day = DueDate(Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
        return Button {
            withAnimation(Theme.spring) { due = day }
        } label: {
            Text(label).chipStyle(selected: due == day)
        }
        .buttonStyle(PressableStyle())
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard await model.updateTask(task, title: title, notes: notes, due: due) else { return }
            if reminderDate != originalReminder {
                if let reminderDate, let listID = model.listID(ofTask: task.id) {
                    let saved = model.task(withID: task.id) ?? task
                    guard await model.reminders.set(reminderDate, for: saved, listID: listID) else { return }
                } else {
                    model.reminders.remove(taskID: task.id)
                }
            }
            onClose()
        }
    }

    /// 9 AM on the deadline if that's still ahead, otherwise the next full hour.
    private var defaultReminderDate: Date {
        let calendar = Calendar.current
        if let due, let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due.date()), nine > Date() {
            return nine
        }
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date())!
        return calendar.date(bySetting: .minute, value: 0, of: nextHour) ?? nextHour
    }
}

private extension View {
    func chipStyle(selected: Bool) -> some View {
        font(.system(size: 11.5))
            .padding(.horizontal, 10)
            .frame(minWidth: 28, minHeight: 24)
            .foregroundStyle(selected ? Theme.background : Theme.secondaryInk)
            .background {
                if selected {
                    Capsule().fill(Theme.ink)
                } else {
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
    }
}

struct Checkbox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.ring, lineWidth: 1.5)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(Theme.accent)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .scaleEffect(isOn ? 1 : 0.4)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isOn)
    }
}

struct DueLabel: View {
    let due: DueDate

    var body: some View {
        let label = due.relativeLabel()
        Label {
            Text(label.text)
        } icon: {
            Image(systemName: "calendar")
        }
        .labelStyle(CompactLabelStyle())
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(label.isOverdue ? Theme.overdue : label.isToday ? Theme.accent : Theme.muted)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
