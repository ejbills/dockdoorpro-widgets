import SwiftUI

enum SimpleSearchLayout {
    static func isExtended(size: CGSize, isVertical: Bool) -> Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }
}
