import SwiftUI

struct DateSeparatorView: View {
    let date: Date

    var body: some View {
        HStack {
            Spacer()

            Text(labelText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.9))
                .clipShape(Capsule())

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(labelText)
    }

    private var labelText: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
