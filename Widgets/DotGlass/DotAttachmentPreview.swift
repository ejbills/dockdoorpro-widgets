import AppKit
import SwiftUI

/// Small previews made from images already rendered in the owned web session.
/// Authenticated downloads and unsupported media remain explicit browser actions.
struct DotAttachmentPreview: View {
    let encoded: String
    @State private var enlarged = false
    private var image: NSImage? {
        guard encoded.utf8.count <= 180000, encoded.hasPrefix("data:image/png;base64,"),
              let data = Data(base64Encoded: String(encoded.dropFirst(22))),
              let image = NSImage(data: data), image.size.width <= 320, image.size.height <= 220 else { return nil }
        return image
    }
    var body: some View {
        if let image {
            Button { enlarged.toggle() } label: {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: enlarged ? 360 : 240, maxHeight: enlarged ? 260 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel(enlarged ? "Shrink image preview" : "Enlarge image preview")
        }
    }
}
