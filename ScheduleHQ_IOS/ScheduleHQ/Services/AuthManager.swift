import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Manages Firebase authentication and user data
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    /// Current Firebase user
    @Published private(set) var currentUser: User?
    
    /// Current app user data from Firestore
    @Published private(set) var appUser: AppUser?
    
    /// Current employee data
    @Published private(set) var employee: Employee?
    
    /// Manager UID for the current user
    @Published private(set) var managerUid: String?
    
    /// Whether authentication state is being checked
    @Published private(set) var isLoading: Bool = true
    
    /// Whether a sign-in operation is in progress
    @Published private(set) var isSigningIn: Bool = false
    
    /// Whether the user is authenticated
    var isAuthenticated: Bool {
        currentUser != nil && appUser != nil
    }
    
    /// Employee's local ID (for Firestore queries)
    var employeeLocalId: Int? {
        appUser?.employeeId
    }
    
    private let alertManager = AlertManager.shared
    
    private init() {
        startAuthStateListener()
    }
    
    deinit {
        stopAuthStateListener()
    }
    
    // MARK: - Auth State Listener
    
    /// Start listening to authentication state changes
    func startAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                if let user = user {
                    await self?.fetchUserData(uid: user.uid)
                } else {
                    self?.clearUserData()
                }
                self?.isLoading = false
            }
        }
    }
    
    /// Stop listening to authentication state changes
    func stopAuthStateListener() {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
            authStateListener = nil
        }
    }
    
    // MARK: - Sign In
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        isSigningIn = true
        defer { isSigningIn = false }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            currentUser = result.user
            await fetchUserData(uid: result.user.uid)
        } catch let error as NSError {
            let message = mapAuthError(error)
            alertManager.showError("Sign In Failed", message: message)
            throw error
        }
    }
    
    // MARK: - Sign Out
    
    /// Sign out the current user
    func signOut() throws {
        do {
            try auth.signOut()
            clearUserData()
        } catch {
            alertManager.showError("Sign Out Failed", message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Password Reset
    
    /// Send password reset email
    func sendPasswordResetEmail(to email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
            alertManager.showSuccess("Email Sent", message: "Check your inbox for password reset instructions.")
        } catch let error as NSError {
            let message = mapAuthError(error)
            alertManager.showError("Password Reset Failed", message: message)
            throw error
        }
    }
    
    // MARK: - User Data
    
    /// Fetch user data from Firestore
    @MainActor
    private func fetchUserData(uid: String) async {
        do {
            // Fetch app user document
            let userDoc = try await db.collection("users").document(uid).getDocument()
            
            guard userDoc.exists else {
                print("❌ User document does not exist for uid: \(uid)")
                alertManager.showError("Account Error", message: "Your account is not properly configured. Please contact your manager.")
                try? signOut()
                return
            }
            
            print("📄 User document data: \(userDoc.data() ?? [:])")
            
            guard let appUser = try? userDoc.data(as: AppUser.self) else {
                print("❌ Failed to decode AppUser from document")
                alertManager.showError("Account Error", message: "Your account is not properly configured. Please contact your manager.")
                try? signOut()
                return
            }
            
            print("✅ AppUser loaded: managerUid=\(appUser.managerUid), employeeId=\(appUser.employeeId)")
            
            self.appUser = appUser
            self.managerUid = appUser.managerUid
            
            // Fetch employee details
            let employeePath = "managers/\(appUser.managerUid)/employees/\(appUser.employeeId)"
            print("📍 Fetching employee from: \(employeePath)")
            
            let employeeDoc = try await db.collection("managers")
                .document(appUser.managerUid)
                .collection("employees")
                .document(String(appUser.employeeId))
                .getDocument()
            
            if employeeDoc.exists {
                print("📄 Employee document data: \(employeeDoc.data() ?? [:])")
                do {
                    let employee = try employeeDoc.data(as: Employee.self)
                    self.employee = employee
                    print("✅ Employee loaded: \(employee.name)")
                } catch {
                    print("⚠️ Failed to decode Employee: \(error)")
                    // Try manual decode as fallback
                    if let data = employeeDoc.data() {
                        let name = data["name"] as? String ?? "Unknown"
                        let jobCode = data["jobCode"] as? String ?? ""
                        let email = data["email"] as? String
                        let uid = data["uid"] as? String
                        let employee = Employee(
                            documentId: employeeDoc.documentID,
                            id: data["id"] as? Int,
                            name: name,
                            jobCode: jobCode,
                            email: email,
                            uid: uid,
                            vacationWeeksAllowed: data["vacationWeeksAllowed"] as? Int ?? 0,
                            vacationWeeksUsed: data["vacationWeeksUsed"] as? Int ?? 0
                        )
                        self.employee = employee
                        print("✅ Employee loaded (manual): \(employee.name)")
                    }
                }
            } else {
                print("⚠️ Employee document not found at: \(employeePath)")
            }
        } catch {
            alertManager.showError("Data Error", message: "Failed to load your profile: \(error.localizedDescription)")
            print("❌ Error fetching user data: \(error)")
        }
    }
    
    /// Clear all user data on sign out
    private func clearUserData() {
        appUser = nil
        employee = nil
        managerUid = nil
    }
    
    /// Refresh employee data from Firestore
    func refreshEmployeeData() async {
        guard let managerUid = managerUid,
              let employeeId = employeeLocalId else { return }
        
        do {
            let employeeDoc = try await db.collection("managers")
                .document(managerUid)
                .collection("employees")
                .document(String(employeeId))
                .getDocument()
            
            if let employee = try? employeeDoc.data(as: Employee.self) {
                await MainActor.run {
                    self.employee = employee
                }
            }
        } catch {
            print("Error refreshing employee data: \(error)")
        }
    }
    
    // MARK: - Error Mapping
    
    /// Map Firebase auth errors to user-friendly messages
    private func mapAuthError(_ error: NSError) -> String {
        guard let errorCode = AuthErrorCode(rawValue: error.code) else {
            return error.localizedDescription
        }
        
        switch errorCode {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .wrongPassword:
            return "Incorrect password. Please try again."
        case .userNotFound:
            return "No account found with this email."
        case .userDisabled:
            return "This account has been disabled. Please contact your manager."
        case .tooManyRequests:
            return "Too many failed attempts. Please wait a moment and try again."
        case .networkError:
            return "Network error. Please check your internet connection."
        case .invalidCredential:
            return "Invalid login credentials. Please check your email and password."
        default:
            return error.localizedDescription
        }
    }
}
