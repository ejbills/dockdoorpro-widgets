import DockDoorWidgetSDK
import SwiftUI

enum SimpleSearchLayout {
    static func span(size: CGSize, isVertical: Bool) -> WidgetSlotSpan {
        WidgetSlotSpan.detect(size: size, isVertical: isVertical)
    }
}
