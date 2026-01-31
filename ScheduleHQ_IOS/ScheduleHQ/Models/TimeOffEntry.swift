import Foundation
import FirebaseFirestore

/// Types of time off available
enum TimeOffType: String, Codable, CaseIterable {
    case pto = "pto"
    case vacation = "vac"
    case sick = "sick"
    case dayOff = "off"
    case requestedOff = "req"
    
    /// Display name for the time off type
    var displayName: String {
        switch self {
        case .pto: return "PTO"
        case .vacation: return "Vacation"
        case .sick: return "Sick"
        case .dayOff: return "Day Off"
        case .requestedOff: return "Requested Off"
        }
    }
    
    /// Short label for display in shift cards
    var shortLabel: String {
        switch self {
        case .pto: return "PTO"
        case .vacation: return "VAC"
        case .sick: return "SICK"
        case .dayOff: return "OFF"
        case .requestedOff: return "REQ OFF"
        }
    }
    
    /// SF Symbol name for the type
    var iconName: String {
        switch self {
        case .pto: return "clock.badge.checkmark"
        case .vacation: return "airplane"
        case .sick: return "cross.case"
        case .dayOff: return "moon.zzz"
        case .requestedOff: return "calendar.badge.clock"
        }
    }
}

/// Represents an approved time off entry in the schedule
struct TimeOffEntry: Codable, Identifiable, Equatable {
    @DocumentID var documentId: String?
    let id: Int?
    let employeeId: Int
    let date: Date
    let timeOffType: TimeOffType
    let hours: Int
    let vacationGroupId: String?
    let isAllDay: Bool
    let startTime: String?  // "HH:mm" format
    let endTime: String?    // "HH:mm" format
    
    /// Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Time range display for partial days
    var timeRangeDisplay: String? {
        guard !isAllDay, let start = startTime, let end = endTime else { return nil }
        return "\(start) - \(end)"
    }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case id
        case employeeId
        case date
        case timeOffType
        case hours
        case vacationGroupId
        case isAllDay
        case startTime
        case endTime
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        employeeId = try container.decode(Int.self, forKey: .employeeId)
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .date) {
            date = timestamp.dateValue()
        } else {
            date = try container.decode(Date.self, forKey: .date)
        }
        
        // Handle timeOffType as string
        let typeString = try container.decode(String.self, forKey: .timeOffType)
        timeOffType = TimeOffType(rawValue: typeString) ?? .dayOff
        
        hours = try container.decodeIfPresent(Int.self, forKey: .hours) ?? 8
        vacationGroupId = try container.decodeIfPresent(String.self, forKey: .vacationGroupId)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? true
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
    }
    
    init(
        documentId: String? = nil,
        id: Int? = nil,
        employeeId: Int,
        date: Date,
        timeOffType: TimeOffType,
        hours: Int = 8,
        vacationGroupId: String? = nil,
        isAllDay: Bool = true,
        startTime: String? = nil,
        endTime: String? = nil
    ) {
        self.documentId = documentId
        self.id = id
        self.employeeId = employeeId
        self.date = date
        self.timeOffType = timeOffType
        self.hours = hours
        self.vacationGroupId = vacationGroupId
        self.isAllDay = isAllDay
        self.startTime = startTime
        self.endTime = endTime
    }
}
