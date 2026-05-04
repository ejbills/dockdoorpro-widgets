import SwiftUI

struct ThingsTodayPanel: View {
    let dismiss: () -> Void
    @ObservedObject var store: ThingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 320, height: 0)

            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = store.snapshot.errorMessage {
                        emptyRow(error, systemImage: "checkmark.circle")
                    } else {
                        section("Today", tasks: store.snapshot.today, emptyText: "No Today tasks")
                        section("Upcoming", tasks: store.snapshot.upcoming, emptyText: "No upcoming tasks")
                        section("Deadlines", tasks: store.snapshot.deadlines, emptyText: "No deadlines")
                    }
                }
                .padding(14)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
        .onAppear { store.refresh(force: true) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Things")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("\(store.snapshot.today.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func section(_ title: String, tasks: [ThingsTask], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if tasks.isEmpty {
                emptyRow(emptyText, systemImage: "circle")
            } else {
                VStack(spacing: 6) {
                    ForEach(tasks.prefix(12)) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: ThingsTask) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: task.deadline == nil ? "circle" : "calendar.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(task.deadline == nil ? Color.secondary : Color.orange)
                .frame(width: 14, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                let context = task.contextLine
                if !context.isEmpty {
                    Text(context)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func emptyRow(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.035))
        )
    }
}
