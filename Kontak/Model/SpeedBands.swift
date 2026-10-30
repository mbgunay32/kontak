import SwiftUI

/// Speed ranges used for the distance breakdown, the colored route and the share card.
enum SpeedBands {
    /// Upper limits in km/h. The last band is "above the last limit".
    static let limitsKmh: [Double] = [30, 60, 90, 120]

    static var count: Int { limitsKmh.count + 1 }

    static func index(forKmh kmh: Double) -> Int {
        limitsKmh.firstIndex(where: { kmh < $0 }) ?? limitsKmh.count
    }

    static func index(forSpeed mps: Double) -> Int {
        index(forKmh: mps * 3.6)
    }

    static func label(_ i: Int) -> String {
        if i >= limitsKmh.count {
            return "\(Int(limitsKmh.last ?? 0))+"
        }
        let lower = i == 0 ? 0 : Int(limitsKmh[i - 1])
        return "\(lower)–\(Int(limitsKmh[i]))"
    }

    private static let palette: [Color] = [
        Color(hex: 0x3B82F6), // blue
        Color(hex: 0x22C55E), // green
        Color(hex: 0xEAB308), // yellow
        Color(hex: 0xF97316), // orange
        Color(hex: 0xEF4444), // red
    ]

    static func color(_ i: Int) -> Color {
        palette[min(max(i, 0), palette.count - 1)]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    /// Same red as the "K" in the app icon.
    static let accent = Color(hex: 0xE4161F)
    static let card = Color.white.opacity(0.06)
}
