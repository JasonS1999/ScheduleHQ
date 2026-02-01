import Foundation
import FirebaseFirestore

/// Represents a shift runner assignment for a specific shift on a specific day
struct ShiftRunner: Codable, Identifiable {
    @DocumentID var documentId: String?
    let date: String  // "2026-01-25" format
    let localId: Int?
    let managerUid: String?
    let runnerName: String
    let shiftType: String  // "open", "lunch", "dinner", "close"
    
    var id: String { documentId ?? "\(date)_\(shiftType)" }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case date
        case localId
        case managerUid
        case runnerName
        case shiftType
    }
}

/// Represents daily schedule notes
struct ScheduleNote: Codable, Identifiable {
    @DocumentID var documentId: String?
    let date: String  // "2026-01-25" format
    let note: String?
    let managerUid: String?
    
    var id: String { documentId ?? date }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case date
        case note
        case managerUid
    }
}
