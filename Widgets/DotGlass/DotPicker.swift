import SwiftUI

@MainActor
struct DotPicker: View {
    @Bindable var connection: DotConnection
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Dots").font(.title2.bold())
                Spacer()
                Button("Done", action: done)
            }
            Text("Choose a previously opened Dot, or open Your Dot in ChatGPT.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(connection.directory.profiles) { profile in
                        Button {
                            connection.selectDot(profile); done()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.circle.fill").font(.title2).foregroundStyle(.blue)
                                Text(profile.name).font(.headline)
                                Spacer()
                                if profile.url == connection.conversation { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                            }.padding(12).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).disabled(!connection.canSwitchDot)
                    }
                }
            }.frame(maxHeight: 220)
            if !connection.canSwitchDot {
                Text("Finish the call or pending message before switching Dots.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Connect your ChatGPT account") { connection.beginSetup(); done() }
                .buttonStyle(.borderedProminent)

        }.padding(24)
    }
}
