import SwiftUI

/// Brand tokens — keep in lockstep with the SluggFishing Brand Book.
/// Dark-first: dawn launches, on-water glare, night tides.
enum Theme {
    // Canvas
    static let abyss      = Color(hex: 0x061019)  // deepest background
    static let deepWater  = Color(hex: 0x0A1622)  // primary background
    static let surface    = Color(hex: 0x122233)  // cards / sheets
    static let hairline   = Color(hex: 0x1E3247)

    // Text
    static let foam       = Color(hex: 0xE8F0F6)  // primary text
    static let mist       = Color(hex: 0x8CA3B5)  // secondary text

    // Action + signal
    static let bite       = Color(hex: 0xFF6B35)  // hot bite / CTA
    static let kelp       = Color(hex: 0x39B54A)  // success / fresh

    // Water-type layer colors (map pins + filters)
    static let salt       = Color(hex: 0x3B82C4)
    static let fresh      = Color(hex: 0x4CC38A)
    static let pierWood   = Color(hex: 0xE0A458)
    static let bayTeal    = Color(hex: 0x38B6B6)
    static let lakeGreen  = Color(hex: 0x62C46B)
    static let offshore   = Color(hex: 0x5D7BE8)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
