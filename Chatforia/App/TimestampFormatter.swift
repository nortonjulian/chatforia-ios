import Foundation

enum TimestampFormatter {
    static func chatListTimestamp(from isoString: String?) -> String {
        guard let isoString, !isoString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let parsers: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]

        var date: Date?
        for parser in parsers {
            if let d = parser.date(from: isoString) {
                date = d
                break
            }
        }

        guard let date else { return "" }
        return chatListTimestamp(from: date)
    }

    static func chatListTimestamp(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 999

        if daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d/yy")
        return formatter.string(from: date)
    }
}
