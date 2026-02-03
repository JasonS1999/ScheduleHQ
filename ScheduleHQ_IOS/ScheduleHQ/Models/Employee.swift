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
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown"
        jobCode = try container.decodeIfPresent(String.self, forKey: .jobCode) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        uid = try container.decodeIfPresent(String.self, forKey: .uid)
        vacationWeeksAllowed = try container.decodeIfPresent(Int.self, forKey: .vacationWeeksAllowed) ?? 0
        vacationWeeksUsed = try container.decodeIfPresent(Int.self, forKey: .vacationWeeksUsed) ?? 0
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
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
