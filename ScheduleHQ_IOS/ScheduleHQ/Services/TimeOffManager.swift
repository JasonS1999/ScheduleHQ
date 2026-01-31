import Foundation
import FirebaseFirestore

/// Manages time off requests and PTO/vacation tracking
@Observable
final class TimeOffManager {
    static let shared = TimeOffManager()
    
    private let db = Firestore.firestore()
    private var requestsListener: ListenerRegistration?
    private var timeOffListener: ListenerRegistration?
    
    /// All time off requests for the current employee
    private(set) var requests: [TimeOffRequest] = []
    
    /// Approved time off entries for the current employee
    private(set) var approvedTimeOff: [TimeOffEntry] = []
    
    /// Whether data is loading
    private(set) var isLoading: Bool = false
    
    /// PTO usage by date (for trimester calculations)
    private(set) var ptoUsageByDate: [Date: Int] = [:]
    
    private let authManager = AuthManager.shared
    private let alertManager = AlertManager.shared
    
    private init() {}
    
    // MARK: - Computed Properties
    
    /// Pending requests
    var pendingRequests: [TimeOffRequest] {
        requests.filter { $0.status == .pending }
            .sorted { $0.date < $1.date }
    }
    
    /// Approved requests
    var approvedRequests: [TimeOffRequest] {
        requests.filter { $0.status == .approved }
            .sorted { $0.date < $1.date }
    }
    
    /// Denied requests
    var deniedRequests: [TimeOffRequest] {
        requests.filter { $0.status == .denied }
            .sorted { $0.date > $1.date }
    }
    
    /// Upcoming approved time off (from today onwards)
    var upcomingTimeOff: [TimeOffEntry] {
        let today = Date().startOfDay
        return approvedTimeOff.filter { $0.date >= today }
            .sorted { $0.date < $1.date }
    }
    
    /// Current trimester summary
    var currentTrimesterSummary: TrimesterSummary? {
        TrimesterSummary.current(forYear: Date().year, ptoUsed: ptoUsageByDate)
    }
    
    /// All trimester summaries for the current year
    var allTrimesterSummaries: [TrimesterSummary] {
        TrimesterSummary.forYear(Date().year, ptoUsed: ptoUsageByDate)
    }
    
    // MARK: - Listeners
    
    /// Start listening to time off requests and entries
    func startListening() {
        guard let managerUid = authManager.managerUid,
              let employeeId = authManager.employeeLocalId else {
            return
        }
        
        stopListening()
        isLoading = true
        
        // Listen to time off requests (newer system)
        requestsListener = db.collection("managers")
            .document(managerUid)
            .collection("timeOffRequests")
            .whereField("employeeId", isEqualTo: employeeId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        print("Time off requests listener error: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.requests = []
                        return
                    }
                    
                    self?.requests = documents.compactMap { doc in
                        try? doc.data(as: TimeOffRequest.self)
                    }
                }
            }
        
        // Listen to approved time off entries
        timeOffListener = db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .whereField("employeeId", isEqualTo: employeeId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        print("Time off entries listener error: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.approvedTimeOff = []
                        return
                    }
                    
                    let entries = documents.compactMap { doc in
                        try? doc.data(as: TimeOffEntry.self)
                    }
                    
                    self?.approvedTimeOff = entries
                    self?.calculatePTOUsage(from: entries)
                }
            }
    }
    
    /// Stop all listeners
    func stopListening() {
        requestsListener?.remove()
        requestsListener = nil
        timeOffListener?.remove()
        timeOffListener = nil
    }
    
    // MARK: - PTO Calculations
    
    /// Calculate PTO usage by date from time off entries
    private func calculatePTOUsage(from entries: [TimeOffEntry]) {
        var usage: [Date: Int] = [:]
        
        for entry in entries where entry.timeOffType == .pto {
            let dateKey = Calendar.current.startOfDay(for: entry.date)
            usage[dateKey, default: 0] += entry.hours
        }
        
        ptoUsageByDate = usage
    }
    
    // MARK: - Submit Request
    
    /// Submit a new time off request
    func submitRequest(_ request: TimeOffRequest) async throws {
        guard let managerUid = authManager.managerUid else {
            throw TimeOffError.notAuthenticated
        }
        
        // Check if auto-approval applies
        let shouldAutoApprove = try await checkAutoApproval(for: request)
        
        var requestToSubmit = request
        if shouldAutoApprove {
            requestToSubmit.status = .approved
        }
        
        let data = requestToSubmit.toFirestoreData()
        data["autoApproved"] as? Bool ?? false
        
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOffRequests")
            .addDocument(data: data)
        
        // If auto-approved, also create the time off entry
        if shouldAutoApprove {
            try await createTimeOffEntry(from: requestToSubmit)
        }
        
        let message = shouldAutoApprove
            ? "Your request has been auto-approved!"
            : "Your request has been submitted for review."
        
        alertManager.showSuccess("Request Submitted", message: message)
    }
    
    /// Check if a request should be auto-approved (fewer than 2 others off that day)
    private func checkAutoApproval(for request: TimeOffRequest) async throws -> Bool {
        guard let managerUid = authManager.managerUid else {
            return false
        }
        
        // Only auto-approve PTO and Day Off types
        guard request.timeOffType == .pto || request.timeOffType == .dayOff else {
            return false
        }
        
        let requestDate = Calendar.current.startOfDay(for: request.date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: requestDate)!
        
        // Count existing approved time off for this date
        let snapshot = try await db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: requestDate))
            .whereField("date", isLessThan: Timestamp(date: nextDay))
            .getDocuments()
        
        // Auto-approve if fewer than 2 others are off
        return snapshot.documents.count < 2
    }
    
    /// Create a time off entry for an approved request
    private func createTimeOffEntry(from request: TimeOffRequest) async throws {
        guard let managerUid = authManager.managerUid else { return }
        
        let entryData: [String: Any] = [
            "employeeId": request.employeeId,
            "date": Timestamp(date: request.date),
            "timeOffType": request.timeOffType.rawValue,
            "hours": request.hours,
            "isAllDay": request.isAllDay,
            "startTime": request.startTime as Any,
            "endTime": request.endTime as Any,
            "vacationGroupId": request.vacationGroupId as Any
        ]
        
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .addDocument(data: entryData)
    }
    
    // MARK: - Delete Request
    
    /// Delete a pending time off request
    func deleteRequest(_ request: TimeOffRequest) async throws {
        guard let managerUid = authManager.managerUid,
              let documentId = request.documentId else {
            throw TimeOffError.invalidRequest
        }
        
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOffRequests")
            .document(documentId)
            .delete()
        
        alertManager.showSuccess("Request Deleted", message: "Your time off request has been removed.")
    }
    
    // MARK: - Error Types
    
    enum TimeOffError: LocalizedError {
        case notAuthenticated
        case invalidRequest
        case networkError
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to submit requests."
            case .invalidRequest:
                return "Invalid request data."
            case .networkError:
                return "Network error. Please try again."
            }
        }
    }
}
