import SwiftUI

/// A task in the panel: round checkbox, title, notes preview, and deadline.
struct TaskRow: View {
    let task: GTask
    let depth: Int
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Checkbox(isOn: task.isCompleted)
                .padding(.top, 1)
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
                if !task.isCompleted, let due = task.dueDate {
                    DueLabel(due: due)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12 + CGFloat(depth) * 28)
        .padding(.trailing, 12)
        .background(Theme.field.opacity(isHovering ? 0.7 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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

extension DueDate {
    /// "Today", "Tomorrow", a weekday within the next week, otherwise a short date.
    func relativeLabel(today: Date = Date(), calendar: Calendar = .current) -> (text: String, isToday: Bool, isOverdue: Bool) {
        let start = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: start, to: date(calendar: calendar)).day ?? 0
        let text: String
        switch days {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case -1: text = "Yesterday"
        case 2...6: text = date(calendar: calendar).formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: start) == year
            text = date(calendar: calendar).formatted(sameYear ? .dateTime.month(.abbreviated).day()
                                                                : .dateTime.month(.abbreviated).day().year())
        }
        return (text, days == 0, days < 0)
    }
}
