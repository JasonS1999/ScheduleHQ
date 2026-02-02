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

/// Represents a time off entry in the schedule (pending, approved, or denied)
struct TimeOffEntry: Codable, Identifiable, Equatable {
    @DocumentID var documentId: String?
    let legacyId: Int?
    let employeeId: Int
    let employeeEmail: String?
    let employeeName: String?
    let date: Date
    let timeOffType: TimeOffType
    let hours: Int
    let vacationGroupId: String?
    let isAllDay: Bool
    let startTime: String?  // "HH:mm" format
    let endTime: String?    // "HH:mm" format
    var status: TimeOffRequestStatus
    
    /// Computed unique ID for Identifiable conformance
    var id: String {
        documentId ?? "\(employeeId)_\(date.timeIntervalSince1970)_\(timeOffType.rawValue)"
    }
    let autoApproved: Bool
    let requestedAt: Date?
    let reviewedAt: Date?
    let reviewedBy: String?
    let denialReason: String?
    let notes: String?
    
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
    
    /// Formatted requested at timestamp
    var formattedRequestedAt: String? {
        guard let requestedAt = requestedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: requestedAt)
    }
    
    /// Dynamic coding keys for handling alternative field names from different platforms
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case legacyId = "id"
        case employeeId
        case employeeEmail
        case employeeName
        case date
        case timeOffType
        case hours
        case vacationGroupId
        case isAllDay
        case startTime
        case endTime
        case status
        case autoApproved
        case requestedAt
        case reviewedAt
        case reviewedBy
        case denialReason
        case notes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        
        // Support both localId and legacyId (id)
        if let localId = try dynamicContainer.decodeIfPresent(Int.self, forKey: DynamicCodingKey(stringValue: "localId")!) {
            legacyId = localId
        } else {
            legacyId = try container.decodeIfPresent(Int.self, forKey: .legacyId)
        }
        
        // Support both employeeLocalId (desktop) and employeeId (legacy)
        if let localEmpId = try dynamicContainer.decodeIfPresent(Int.self, forKey: DynamicCodingKey(stringValue: "employeeLocalId")!) {
            employeeId = localEmpId
        } else {
            employeeId = try container.decode(Int.self, forKey: .employeeId)
        }
        
        employeeEmail = try container.decodeIfPresent(String.self, forKey: .employeeEmail)
        employeeName = try container.decodeIfPresent(String.self, forKey: .employeeName)
        
        // Support both Timestamp and String date formats
        if let timestamp = try? container.decode(Timestamp.self, forKey: .date) {
            date = timestamp.dateValue()
        } else if let dateString = try? container.decode(String.self, forKey: .date) {
            // Parse "YYYY-MM-DD" string format from desktop
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsedDate = formatter.date(from: dateString) {
                date = parsedDate
            } else {
                // Fallback to ISO8601
                date = ISO8601DateFormatter().date(from: dateString) ?? Date()
            }
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
        
        // Status defaults to approved for backwards compatibility with old entries
        if let statusString = try container.decodeIfPresent(String.self, forKey: .status) {
            status = TimeOffRequestStatus(rawValue: statusString) ?? .approved
        } else {
            status = .approved
        }
        
        autoApproved = try container.decodeIfPresent(Bool.self, forKey: .autoApproved) ?? false
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .requestedAt) {
            requestedAt = timestamp.dateValue()
        } else {
            requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt)
        }
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .reviewedAt) {
            reviewedAt = timestamp.dateValue()
        } else {
            reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        }
        
        reviewedBy = try container.decodeIfPresent(String.self, forKey: .reviewedBy)
        denialReason = try container.decodeIfPresent(String.self, forKey: .denialReason)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    init(
        documentId: String? = nil,
        legacyId: Int? = nil,
        employeeId: Int,
        employeeEmail: String? = nil,
        employeeName: String? = nil,
        date: Date,
        timeOffType: TimeOffType,
        hours: Int = 8,
        vacationGroupId: String? = nil,
        isAllDay: Bool = true,
        startTime: String? = nil,
        endTime: String? = nil,
        status: TimeOffRequestStatus = .pending,
        autoApproved: Bool = false,
        requestedAt: Date? = nil,
        reviewedAt: Date? = nil,
        reviewedBy: String? = nil,
        denialReason: String? = nil,
        notes: String? = nil
    ) {
        self.documentId = documentId
        self.legacyId = legacyId
        self.employeeId = employeeId
        self.employeeEmail = employeeEmail
        self.employeeName = employeeName
        self.date = date
        self.timeOffType = timeOffType
        self.hours = hours
        self.vacationGroupId = vacationGroupId
        self.isAllDay = isAllDay
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.autoApproved = autoApproved
        self.requestedAt = requestedAt
        self.reviewedAt = reviewedAt
        self.reviewedBy = reviewedBy
        self.denialReason = denialReason
        self.notes = notes
    }
    
    /// Convert to dictionary for Firestore upload
    /// Includes all fields required by the desktop app
    func toFirestoreData(employeeUid: String?, managerUid: String?) -> [String: Any] {
        // Format date as "YYYY-MM-DD" string (required by desktop)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        var data: [String: Any] = [
            // Desktop requires these field names
            "employeeLocalId": employeeId,  // Desktop uses employeeLocalId
            "date": dateString,              // Desktop expects string "YYYY-MM-DD"
            "timeOffType": timeOffType.rawValue,
            "hours": hours,
            "isAllDay": isAllDay,
            "status": status.rawValue,
            "autoApproved": autoApproved,
            "requestedAt": Timestamp(date: requestedAt ?? Date()),
            "updatedAt": Timestamp(date: Date())  // Desktop uses this
        ]
        
        // Add employee UID (Firebase Auth UID)
        if let employeeUid = employeeUid {
            data["employeeUid"] = employeeUid
        }
        
        // Add manager UID
        if let managerUid = managerUid {
            data["managerUid"] = managerUid
        }
        
        if let employeeEmail = employeeEmail { data["employeeEmail"] = employeeEmail }
        if let employeeName = employeeName { data["employeeName"] = employeeName }
        if let startTime = startTime { data["startTime"] = startTime }
        if let endTime = endTime { data["endTime"] = endTime }
        if let vacationGroupId = vacationGroupId { data["vacationGroupId"] = vacationGroupId }
        if let notes = notes { data["notes"] = notes }
        
        return data
    }
}
