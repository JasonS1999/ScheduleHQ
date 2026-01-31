import Foundation
import FirebaseFirestore

/// Status of a time off request
enum TimeOffRequestStatus: String, Codable {
    case pending
    case approved
    case denied
    
    /// Display color for the status
    var colorName: String {
        switch self {
        case .pending: return "orange"
        case .approved: return "green"
        case .denied: return "red"
        }
    }
    
    /// SF Symbol for the status
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .approved: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        }
    }
}

/// Represents a time off request submitted by an employee
struct TimeOffRequest: Codable, Identifiable, Equatable {
    @DocumentID var documentId: String?
    var id: String? { documentId }
    let employeeId: Int
    let employeeEmail: String
    let employeeName: String
    let date: Date
    let timeOffType: TimeOffType
    let hours: Int
    let isAllDay: Bool
    let startTime: String?
    let endTime: String?
    let vacationGroupId: String?
    var status: TimeOffRequestStatus
    let autoApproved: Bool
    let requestedAt: Date
    let reviewedAt: Date?
    let reviewedBy: String?
    let denialReason: String?
    let notes: String?
    
    /// Unique local ID for offline queue tracking
    var localId: String?
    
    /// Whether this request is queued locally (not yet synced)
    var isQueued: Bool {
        localId != nil && documentId == nil
    }
    
    /// Formatted request date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Formatted requested at timestamp
    var formattedRequestedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: requestedAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case employeeId
        case employeeEmail
        case employeeName
        case date
        case timeOffType
        case hours
        case isAllDay
        case startTime
        case endTime
        case vacationGroupId
        case status
        case autoApproved
        case requestedAt
        case reviewedAt
        case reviewedBy
        case denialReason
        case notes
        case localId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        employeeId = try container.decode(Int.self, forKey: .employeeId)
        employeeEmail = try container.decodeIfPresent(String.self, forKey: .employeeEmail) ?? ""
        employeeName = try container.decodeIfPresent(String.self, forKey: .employeeName) ?? ""
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .date) {
            date = timestamp.dateValue()
        } else {
            date = try container.decode(Date.self, forKey: .date)
        }
        
        let typeString = try container.decode(String.self, forKey: .timeOffType)
        timeOffType = TimeOffType(rawValue: typeString) ?? .dayOff
        
        hours = try container.decodeIfPresent(Int.self, forKey: .hours) ?? 8
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? true
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        vacationGroupId = try container.decodeIfPresent(String.self, forKey: .vacationGroupId)
        
        let statusString = try container.decode(String.self, forKey: .status)
        status = TimeOffRequestStatus(rawValue: statusString) ?? .pending
        
        autoApproved = try container.decodeIfPresent(Bool.self, forKey: .autoApproved) ?? false
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .requestedAt) {
            requestedAt = timestamp.dateValue()
        } else {
            requestedAt = try container.decodeIfPresent(Date.self, forKey: .requestedAt) ?? Date()
        }
        
        if let timestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .reviewedAt) {
            reviewedAt = timestamp.dateValue()
        } else {
            reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        }
        
        reviewedBy = try container.decodeIfPresent(String.self, forKey: .reviewedBy)
        denialReason = try container.decodeIfPresent(String.self, forKey: .denialReason)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        localId = try container.decodeIfPresent(String.self, forKey: .localId)
    }
    
    init(
        documentId: String? = nil,
        employeeId: Int,
        employeeEmail: String,
        employeeName: String,
        date: Date,
        timeOffType: TimeOffType,
        hours: Int = 8,
        isAllDay: Bool = true,
        startTime: String? = nil,
        endTime: String? = nil,
        vacationGroupId: String? = nil,
        status: TimeOffRequestStatus = .pending,
        autoApproved: Bool = false,
        requestedAt: Date = Date(),
        reviewedAt: Date? = nil,
        reviewedBy: String? = nil,
        denialReason: String? = nil,
        notes: String? = nil,
        localId: String? = nil
    ) {
        self.documentId = documentId
        self.employeeId = employeeId
        self.employeeEmail = employeeEmail
        self.employeeName = employeeName
        self.date = date
        self.timeOffType = timeOffType
        self.hours = hours
        self.isAllDay = isAllDay
        self.startTime = startTime
        self.endTime = endTime
        self.vacationGroupId = vacationGroupId
        self.status = status
        self.autoApproved = autoApproved
        self.requestedAt = requestedAt
        self.reviewedAt = reviewedAt
        self.reviewedBy = reviewedBy
        self.denialReason = denialReason
        self.notes = notes
        self.localId = localId
    }
    
    /// Convert to dictionary for Firestore upload
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "employeeId": employeeId,
            "employeeEmail": employeeEmail,
            "employeeName": employeeName,
            "date": Timestamp(date: date),
            "timeOffType": timeOffType.rawValue,
            "hours": hours,
            "isAllDay": isAllDay,
            "status": status.rawValue,
            "autoApproved": autoApproved,
            "requestedAt": Timestamp(date: requestedAt)
        ]
        
        if let startTime = startTime { data["startTime"] = startTime }
        if let endTime = endTime { data["endTime"] = endTime }
        if let vacationGroupId = vacationGroupId { data["vacationGroupId"] = vacationGroupId }
        if let notes = notes { data["notes"] = notes }
        
        return data
    }
}
