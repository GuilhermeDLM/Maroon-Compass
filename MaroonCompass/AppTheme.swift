import SwiftUI
import UIKit

enum AppTheme {
    /// A dynamic, high-contrast blue used for controls and information.
    /// Maroon is intentionally reserved for the product name and small identity accents.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.67, blue: 1.00, alpha: 1)
            : UIColor(red: 0.04, green: 0.32, blue: 0.72, alpha: 1)
    })
    static let deepBlue = Color(red: 0.025, green: 0.12, blue: 0.27)
    static let warmPaper = Color(red: 0.98, green: 0.965, blue: 0.95)
    static let gold = Color(red: 0.91, green: 0.66, blue: 0.27)
    static let cardRadius: CGFloat = 20
    static let compactRadius: CGFloat = 14
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension Course {
    var tint: Color { Color(hex: colorHex) }
}

enum CampusFormatters {
    static let dayHeading: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    static let compactDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
        }
        return "\(minutes) min"
    }
}
