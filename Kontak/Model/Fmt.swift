import Foundation

enum Fmt {
    private static let oneDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM, EEEE · HH:mm"
        return f
    }()

    /// "12,4"
    static func kmValue(_ meters: Double) -> String {
        oneDecimal.string(from: NSNumber(value: meters / 1000)) ?? "0,0"
    }

    /// "12,4 km"
    static func km(_ meters: Double) -> String { kmValue(meters) + " km" }

    /// "64 km/h"
    static func speed(_ mps: Double) -> String { "\(Int((mps * 3.6).rounded())) km/h" }

    static func duration(_ seconds: Double) -> String {
        let t = max(Int(seconds), 0)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "%36"
    static func percent(_ part: Double, of total: Double) -> String {
        guard total > 0 else { return "%0" }
        return "%\(Int((part / total * 100).rounded()))"
    }

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func dayTime(_ date: Date) -> String { dayTimeFormatter.string(from: date) }
}
