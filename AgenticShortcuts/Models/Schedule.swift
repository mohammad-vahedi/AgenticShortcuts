import Foundation

struct Schedule: Codable {
    let hour: Int
    let minute: Int
    let recurrence: Recurrence
    let weekday: Int?
    let durationDays: Int?
    let startDate: Date
    let label: String

    enum Recurrence: String, Codable {
        case once
        case daily
        case weekly
    }

    var displayDescription: String {
        var parts: [String] = []
        let timeStr = String(format: "%02d:%02d", hour, minute)

        switch recurrence {
        case .once:
            parts.append("Once at \(timeStr)")
        case .daily:
            parts.append("Daily at \(timeStr)")
        case .weekly:
            let dayName = weekday.map { weekdayName($0) } ?? ""
            parts.append("Weekly on \(dayName) at \(timeStr)")
        }

        if let days = durationDays {
            parts.append("for \(days) days")
        }

        return parts.joined(separator: " ")
    }

    var expiryDate: Date? {
        guard let days = durationDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: startDate)
    }

    var plistIdentifier: String {
        let sanitized = label
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "com.agenticshortcuts.\(sanitized)"
    }

    private func weekdayName(_ day: Int) -> String {
        switch day {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        case 7: return "Sunday"
        default: return "Day \(day)"
        }
    }
}

struct ScheduleExtraction: Codable {
    let hasSchedule: Bool
    let hour: Int?
    let minute: Int?
    let recurrence: String?
    let weekday: Int?
    let durationDays: Int?
    let actionOnly: String?

    enum CodingKeys: String, CodingKey {
        case hasSchedule = "has_schedule"
        case hour, minute, recurrence, weekday
        case durationDays = "duration_days"
        case actionOnly = "action_only"
    }
}
