import SwiftUI

/// Shared branding for the Ask widget.
enum AskBrand {
    /// The siri.gen2 glyph tinted with colors sampled from the Apple
    /// Intelligence icon: deep navy → steel blue → pale sky → sage → warm taupe,
    /// sweeping from the top-trailing to the bottom-leading corner.
    static let iconGradient = LinearGradient(
        colors: [
            Color(red: 0x08 / 255, green: 0x20 / 255, blue: 0x38 / 255), // #082038 deep navy
            Color(red: 0x30 / 255, green: 0x50 / 255, blue: 0x69 / 255), // #305069 steel blue
            Color(red: 0x80 / 255, green: 0xA6 / 255, blue: 0xB9 / 255), // #80A6B9 pale sky
            Color(red: 0xC6 / 255, green: 0xDA / 255, blue: 0xCF / 255), // #C6DACF sage
            Color(red: 0xA7 / 255, green: 0x94 / 255, blue: 0x84 / 255), // #A79484 warm taupe
        ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )
}
