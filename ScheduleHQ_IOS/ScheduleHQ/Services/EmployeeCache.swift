import Foundation
import FirebaseFirestore

/// Caches all employees for the current manager to enable name lookups
final class EmployeeCache: ObservableObject {
    static let shared = EmployeeCache()
    
    private let db = Firestore.firestore()
    private let authManager = AuthManager.shared
    
    /// Cached employees keyed by their UID
    @Published private(set) var employeesByUid: [String: Employee] = [:]
    
    /// Cached employees keyed by their local ID (Int)
    @Published private(set) var employeesById: [Int: Employee] = [:]
    
    /// Whether the cache has been loaded
    @Published private(set) var isLoaded: Bool = false
    
    /// Whether loading is in progress
    @Published private(set) var isLoading: Bool = false
    
    private var listenerRegistration: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get employee name for a given UID
    /// - Parameter uid: The employee's Firebase UID
    /// - Returns: The employee's name, or nil if not found
    func name(for uid: String) -> String? {
        employeesByUid[uid]?.name
    }
    
    /// Get employee name for a given local ID
    /// - Parameter id: The employee's local numeric ID
    /// - Returns: The employee's name, or nil if not found
    func name(forId id: Int) -> String? {
        employeesById[id]?.name
    }
    
    /// Get full employee for a given UID
    /// - Parameter uid: The employee's Firebase UID
    /// - Returns: The Employee object, or nil if not found
    func employee(for uid: String) -> Employee? {
        employeesByUid[uid]
    }
    
    /// Get full employee for a given local ID
    /// - Parameter id: The employee's local numeric ID
    /// - Returns: The Employee object, or nil if not found
    func employee(forId id: Int) -> Employee? {
        employeesById[id]
    }
    
    /// Load all employees for the current manager
    /// - Parameter forceReload: If true, reloads even if already loaded
    func loadEmployees(forceReload: Bool = false) async {
        // Skip if already loaded and not forcing reload
        if isLoaded && !forceReload {
            return
        }
        
        // Skip if already loading
        guard !isLoading else { return }
        
        guard let managerUid = authManager.managerUid else {
            print("❌ EmployeeCache: No manager UID available")
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let snapshot = try await db.collection("managers")
                .document(managerUid)
                .collection("employees")
                .getDocuments()
            
            var cacheByUid: [String: Employee] = [:]
            var cacheById: [Int: Employee] = [:]
            
            for document in snapshot.documents {
                if let employee = try? document.data(as: Employee.self) {
                    // Cache by UID if available
                    if let uid = employee.uid {
                        cacheByUid[uid] = employee
                    }
                    // Cache by local ID if available
                    if let id = employee.id {
                        cacheById[id] = employee
                    }
                }
            }
            
            await MainActor.run {
                self.employeesByUid = cacheByUid
                self.employeesById = cacheById
                self.isLoaded = true
                self.isLoading = false
            }
            
            print("✅ EmployeeCache: Loaded \(cacheByUid.count) employees by UID, \(cacheById.count) by ID")
            
        } catch {
            print("❌ EmployeeCache: Failed to load employees: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    /// Start listening for real-time employee updates
    func startListening() {
        guard let managerUid = authManager.managerUid else {
            print("❌ EmployeeCache: No manager UID available for listener")
            return
        }
        
        // Remove existing listener if any
        stopListening()
        
        listenerRegistration = db.collection("managers")
            .document(managerUid)
            .collection("employees")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ EmployeeCache: Listener error: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                var cacheByUid: [String: Employee] = [:]
                var cacheById: [Int: Employee] = [:]
                
                for document in documents {
                    if let employee = try? document.data(as: Employee.self) {
                        // Cache by UID if available
                        if let uid = employee.uid {
                            cacheByUid[uid] = employee
                        }
                        // Cache by local ID if available
                        if let id = employee.id {
                            cacheById[id] = employee
                        }
                    }
                }
                
                Task { @MainActor in
                    self.employeesByUid = cacheByUid
                    self.employeesById = cacheById
                    self.isLoaded = true
                    self.isLoading = false
                }
            }
    }
    
    /// Stop listening for updates
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    /// Clear the cache (e.g., on sign out)
    func clearCache() {
        stopListening()
        employeesByUid = [:]
        employeesById = [:]
        isLoaded = false
    }
}
