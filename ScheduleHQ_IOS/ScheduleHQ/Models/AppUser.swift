import Foundation
import FirebaseFirestore

/// Represents a user account in Firebase Auth with associated Firestore data
struct AppUser: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let managerUid: String
    let employeeId: Int
    let role: UserRole
    let email: String?
    
    enum UserRole: String, Codable {
        case employee
        case manager
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case managerUid
        case employeeId
        case role
        case email
    }
}
