import Foundation
import FirebaseFirestore

/// Represents an employee in the scheduling system
struct Employee: Codable, Identifiable, Equatable {
    @DocumentID var documentId: String?
    let id: Int?
    let name: String
    let jobCode: String
    let email: String?
    let uid: String?
    let vacationWeeksAllowed: Int
    let vacationWeeksUsed: Int
    var profileImageURL: String?
    
    /// Remaining vacation weeks available
    var vacationWeeksRemaining: Int {
        vacationWeeksAllowed - vacationWeeksUsed
    }
    
    /// Progress towards vacation usage (0.0 - 1.0)
    var vacationProgress: Double {
        guard vacationWeeksAllowed > 0 else { return 0 }
        return Double(vacationWeeksUsed) / Double(vacationWeeksAllowed)
    }
    
    /// First letter of name for avatar display
    var initial: String {
        String(name.prefix(1)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case documentId
        case id
        case localId  // Desktop app uses localId, iOS uses id - support both
        case name
        case jobCode
        case email
        case uid
        case vacationWeeksAllowed
        case vacationWeeksUsed
        case profileImageURL
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        // Try 'id' first, then fall back to 'localId' (Desktop app uses localId)
        if let idValue = try container.decodeIfPresent(Int.self, forKey: .id) {
            id = idValue
        } else {
            id = try container.decodeIfPresent(Int.self, forKey: .localId)
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown"
        jobCode = try container.decodeIfPresent(String.self, forKey: .jobCode) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        uid = try container.decodeIfPresent(String.self, forKey: .uid)
        vacationWeeksAllowed = try container.decodeIfPresent(Int.self, forKey: .vacationWeeksAllowed) ?? 0
        vacationWeeksUsed = try container.decodeIfPresent(Int.self, forKey: .vacationWeeksUsed) ?? 0
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(documentId, forKey: .documentId)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(jobCode, forKey: .jobCode)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(uid, forKey: .uid)
        try container.encode(vacationWeeksAllowed, forKey: .vacationWeeksAllowed)
        try container.encode(vacationWeeksUsed, forKey: .vacationWeeksUsed)
        try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
    }
    
    init(
        documentId: String? = nil,
        id: Int? = nil,
        name: String,
        jobCode: String = "",
        email: String? = nil,
        uid: String? = nil,
        vacationWeeksAllowed: Int = 0,
        vacationWeeksUsed: Int = 0,
        profileImageURL: String? = nil
    ) {
        self.documentId = documentId
        self.id = id
        self.name = name
        self.jobCode = jobCode
        self.email = email
        self.uid = uid
        self.vacationWeeksAllowed = vacationWeeksAllowed
        self.vacationWeeksUsed = vacationWeeksUsed
        self.profileImageURL = profileImageURL
    }
}
