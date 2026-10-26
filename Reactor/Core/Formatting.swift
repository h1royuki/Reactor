import Foundation

enum Formatting {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    private static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let absoluteWithTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    static func date(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "только что" }
        if interval < 7 * 24 * 3600 { return relative.localizedString(for: date, relativeTo: Date()) }
        return absolute.string(from: date)
    }

    static func fullDate(_ date: Date) -> String { absoluteWithTime.string(from: date) }

    static func shortDate(_ date: Date) -> String { absolute.string(from: date) }

    static func rating(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded) >= 1000 { return compact(Int(rounded)) }
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    static func compact(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000...: return sign + String(format: "%.1fM", Double(absValue) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 10_000...: return sign + "\(absValue / 1000)K"
        case 1_000...: return sign + String(format: "%.1fK", Double(absValue) / 1000).replacingOccurrences(of: ".0K", with: "K")
        default: return "\(value)"
        }
    }
}
