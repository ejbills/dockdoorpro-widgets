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

    private var todayDeadlines: Int {
        store.snapshot.today.filter { isTodayDate($0.deadline) }.count
    }

    private var todayRegular: Int {
        max(store.snapshot.today.count - todayDeadlines, 0)
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
        VStack(spacing: 7) {
            Image(systemName: "star.fill")
                .font(.system(size: dim * 0.30, weight: .heavy))
                .foregroundStyle(ThingsStyle.today)
                .shadow(color: ThingsStyle.today.opacity(0.20), radius: 4, y: 2)

            countStrip(fontSize: dim * 0.15)
        }
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: 6) {
                    header
                }
            } else {
                HStack(alignment: .center, spacing: dim * 0.09) {
                    VStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: dim * 0.24, weight: .heavy))
                            .foregroundStyle(ThingsStyle.today)
                        countStrip(fontSize: dim * 0.10)
                    }
                    .frame(width: dim * 0.55)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today")
                            .font(.system(size: dim * 0.16, weight: .bold))
                            .foregroundStyle(.primary)

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
            Image(systemName: "star.fill")
                .font(.system(size: dim * 0.22, weight: .heavy))
                .foregroundStyle(ThingsStyle.today)
            countStrip(fontSize: dim * 0.10)
        }
    }

    private func countStrip(fontSize: CGFloat) -> some View {
        HStack(spacing: 5) {
            if todayDeadlines > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ThingsStyle.deadline)
                        .frame(width: fontSize * 0.62, height: fontSize * 0.62)
                    Text("\(todayDeadlines)")
                        .monospacedDigit()
                }
                .foregroundStyle(ThingsStyle.deadline)
            }

            if todayRegular > 0 {
                Text("\(todayRegular)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
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
            Image(systemName: "star")
                .font(.system(size: dim * 0.26, weight: .semibold))
                .foregroundStyle(ThingsStyle.today)
            Text(text)
                .font(.system(size: dim * 0.12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}
