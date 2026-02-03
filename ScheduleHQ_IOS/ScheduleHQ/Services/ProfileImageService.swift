import Foundation
import FirebaseStorage
import FirebaseFirestore
import UIKit

/// Service for uploading and managing profile images
final class ProfileImageService {
    static let shared = ProfileImageService()
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    /// Maximum image dimension (width or height) after compression
    private let maxImageDimension: CGFloat = 500
    
    /// JPEG compression quality (0.0 - 1.0)
    private let compressionQuality: CGFloat = 0.7
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Upload a profile image for an employee
    /// - Parameters:
    ///   - image: The UIImage to upload
    ///   - employeeDocumentId: The Firestore document ID of the employee
    ///   - managerUid: The manager's UID (for storage path)
    /// - Returns: The download URL of the uploaded image
    @MainActor
    func uploadProfileImage(_ image: UIImage, for employeeDocumentId: String, managerUid: String) async throws -> String {
        // Compress and resize the image
        guard let imageData = compressImage(image) else {
            throw ProfileImageError.compressionFailed
        }
        
        // Create storage reference
        let storagePath = "managers/\(managerUid)/employees/\(employeeDocumentId)/profile.jpg"
        let storageRef = storage.reference().child(storagePath)
        
        // Upload metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // Upload the image
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        
        // Get download URL
        let downloadURL = try await storageRef.downloadURL()
        let urlString = downloadURL.absoluteString
        
        // Update Firestore with the new profile image URL
        try await updateEmployeeProfileURL(employeeDocumentId: employeeDocumentId, managerUid: managerUid, imageURL: urlString)
        
        return urlString
    }
    
    /// Delete a profile image for an employee
    /// - Parameters:
    ///   - employeeDocumentId: The Firestore document ID of the employee
    ///   - managerUid: The manager's UID (for storage path)
    func deleteProfileImage(for employeeDocumentId: String, managerUid: String) async throws {
        let storagePath = "managers/\(managerUid)/employees/\(employeeDocumentId)/profile.jpg"
        let storageRef = storage.reference().child(storagePath)
        
        try await storageRef.delete()
        
        // Remove URL from Firestore
        try await updateEmployeeProfileURL(employeeDocumentId: employeeDocumentId, managerUid: managerUid, imageURL: nil)
    }
    
    // MARK: - Private Methods
    
    /// Compress and resize an image to meet size requirements
    private func compressImage(_ image: UIImage) -> Data? {
        // Resize if needed
        let resizedImage = resizeImageIfNeeded(image)
        
        // Compress to JPEG
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
    
    /// Resize image if it exceeds maximum dimensions
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        
        // Check if resizing is needed
        guard size.width > maxImageDimension || size.height > maxImageDimension else {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let ratio = min(maxImageDimension / size.width, maxImageDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // Resize the image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Update the employee's profile image URL in Firestore
    private func updateEmployeeProfileURL(employeeDocumentId: String, managerUid: String, imageURL: String?) async throws {
        let employeeRef = db.collection("managers").document(managerUid)
            .collection("employees").document(employeeDocumentId)
        
        if let imageURL = imageURL {
            try await employeeRef.updateData(["profileImageURL": imageURL])
        } else {
            try await employeeRef.updateData(["profileImageURL": FieldValue.delete()])
        }
    }
}

// MARK: - Errors

enum ProfileImageError: LocalizedError {
    case compressionFailed
    case uploadFailed
    case noManagerUid
    case noEmployeeId
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress the image"
        case .uploadFailed:
            return "Failed to upload the image"
        case .noManagerUid:
            return "No manager UID available"
        case .noEmployeeId:
            return "No employee ID available"
        }
    }
}
