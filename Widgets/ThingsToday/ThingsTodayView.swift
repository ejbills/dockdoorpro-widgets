import DockDoorWidgetSDK
import SwiftUI

struct ThingsTodayView: View {
    let size: CGSize
    let isVertical: Bool
    @ObservedObject var store: ThingsStore

    private var dim: CGFloat { min(size.width, size.height) }
    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    private var topTasks: [ThingsTask] {
        Array(store.snapshot.today.prefix(3))
    }

    var body: some View {
        Group {
            if let error = store.snapshot.errorMessage {
                fallback(error)
            } else if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
        .padding(isExtended ? 6 : 5)
        .onAppear { store.refresh() }
    }

    private var compactLayout: some View {
        VStack(spacing: 2) {
            Image(systemName: "checklist")
                .font(.system(size: dim * 0.28, weight: .semibold))
                .foregroundStyle(.blue)

            Text("\(store.snapshot.today.count)")
                .font(.system(size: dim * 0.23, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(topTasks.first?.title ?? "Today")
                .font(.system(size: dim * 0.12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: 5) {
                    header
                    taskStack(limit: 2, fontSize: dim * 0.12)
                }
            } else {
                HStack(alignment: .center, spacing: dim * 0.09) {
                    VStack(spacing: 1) {
                        Image(systemName: "checklist")
                            .font(.system(size: dim * 0.24, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("\(store.snapshot.today.count)")
                            .font(.system(size: dim * 0.20, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(width: dim * 0.55)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today")
                            .font(.system(size: dim * 0.16, weight: .bold))
                            .foregroundStyle(.primary)

                        taskStack(limit: 3, fontSize: dim * 0.115)

                        if let due = nearestDueText {
                            Text(due)
                                .font(.system(size: dim * 0.10, weight: .medium))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 1) {
            Image(systemName: "checklist")
                .font(.system(size: dim * 0.22, weight: .semibold))
                .foregroundStyle(.blue)
            Text("\(store.snapshot.today.count)")
                .font(.system(size: dim * 0.18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private func taskStack(limit: Int, fontSize: CGFloat) -> some View {
        VStack(alignment: isVertical ? .center : .leading, spacing: 2) {
            if topTasks.isEmpty {
                Text("No Today tasks")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(Array(topTasks.prefix(limit))) { task in
                    Text(task.title)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
    }

    private var nearestDueText: String? {
        let task = store.snapshot.today.first { $0.deadline != nil }
            ?? store.snapshot.deadlines.first
        guard let task, let deadline = task.deadline else {
            return nil
        }
        return "Next deadline \(relativeDate(deadline))"
    }

    private func fallback(_ text: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: dim * 0.26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: dim * 0.12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}
