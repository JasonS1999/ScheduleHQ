import Foundation
import FirebaseFirestore

/// Represents a user account in Firebase Auth with associated Firestore data
struct AppUser: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let managerUid: String
    let employeeId: Int
    let role: UserRole?
    let email: String?
    
    enum UserRole: String, Codable {
        case employee
        case manager
    }
    
    /// Computed property for safe role access (defaults to employee)
    var userRole: UserRole {
        role ?? .employee
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case managerUid
        case employeeId
        case role
        case email
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        managerUid = try container.decode(String.self, forKey: .managerUid)
        
        // Handle employeeId as either Int or String
        if let intId = try? container.decode(Int.self, forKey: .employeeId) {
            employeeId = intId
        } else if let stringId = try? container.decode(String.self, forKey: .employeeId),
                  let parsed = Int(stringId) {
            employeeId = parsed
        } else {
            throw DecodingError.typeMismatch(Int.self, DecodingError.Context(
                codingPath: [CodingKeys.employeeId],
                debugDescription: "employeeId must be Int or String"
            ))
        }
        
        role = try container.decodeIfPresent(UserRole.self, forKey: .role)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }
}
