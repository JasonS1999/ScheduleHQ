import Foundation
import FirebaseFirestore

/// Represents a work shift in the schedule
struct Shift: Codable, Identifiable, Equatable {
    @DocumentID var documentId: String?
    let id: Int?
    let employeeId: Int?
    let employeeUid: String?
    let startTime: Date
    let endTime: Date
    let dateString: String?  // "yyyy-MM-dd" format
    let label: String?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
    let publishedAt: Date?
    
    /// Duration of the shift in hours
    var durationHours: Double {
        endTime.timeIntervalSince(startTime) / 3600
    }
    
    /// Formatted duration string (e.g., "8.0 hrs")
    var formattedDuration: String {
        String(format: "%.1f hrs", durationHours)
    }
    
    /// Date of the shift (start date, ignoring time)
    var date: Date {
        Calendar.current.startOfDay(for: startTime)
    }
    
    /// Formatted time range (e.g., "9:00 AM - 5:00 PM")
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    /// Check if this shift is on the same day as a given date
    func isOnDate(_ targetDate: Date) -> Bool {
        Calendar.current.isDate(startTime, inSameDayAs: targetDate)
    }
    
    /// Check if this shift is today
    var isToday: Bool {
        Calendar.current.isDateInToday(startTime)
    }
    
    /// Check if this is an "off" day (no work scheduled)
    var isOff: Bool {
        label?.uppercased() == "OFF"
    }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case id
        case employeeId
        case employeeUid
        case startTime
        case endTime
        case dateString = "date"
        case label
        case notes
        case createdAt
        case updatedAt
        case publishedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        employeeId = try container.decodeIfPresent(Int.self, forKey: .employeeId)
        employeeUid = try container.decodeIfPresent(String.self, forKey: .employeeUid)
        dateString = try container.decodeIfPresent(String.self, forKey: .dateString)
        
        // Handle Firestore Timestamp or Date
        if let timestamp = try? container.decode(Timestamp.self, forKey: .startTime) {
            startTime = timestamp.dateValue()
        } else {
            startTime = try container.decode(Date.self, forKey: .startTime)
        }
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .endTime) {
            endTime = timestamp.dateValue()
        } else {
            endTime = try container.decode(Date.self, forKey: .endTime)
        }
        
        label = try container.decodeIfPresent(String.self, forKey: .label)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        }
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .updatedAt) {
            updatedAt = timestamp.dateValue()
        } else {
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .publishedAt) {
            publishedAt = timestamp.dateValue()
        } else {
            publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        }
    }
    
    init(
        documentId: String? = nil,
        id: Int? = nil,
        employeeId: Int? = nil,
        employeeUid: String? = nil,
        startTime: Date,
        endTime: Date,
        dateString: String? = nil,
        label: String? = nil,
        notes: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        publishedAt: Date? = nil
    ) {
        self.documentId = documentId
        self.id = id
        self.employeeId = employeeId
        self.employeeUid = employeeUid
        self.startTime = startTime
        self.endTime = endTime
        self.dateString = dateString
        self.label = label
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.publishedAt = publishedAt
    }
}
