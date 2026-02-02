import Foundation
import FirebaseFirestore
import Combine

/// Manages time off requests and PTO/vacation tracking
/// All time off data is stored in the unified `timeOff` collection with status field
final class TimeOffManager: ObservableObject {
    static let shared = TimeOffManager()
    
    private let db = Firestore.firestore()
    private var timeOffListener: ListenerRegistration?
    
    /// All time off entries for the current employee (pending, approved, denied)
    @Published private(set) var allTimeOff: [TimeOffEntry] = []
    
    /// Whether data is loading
    @Published private(set) var isLoading: Bool = false
    
    /// PTO usage by date (for trimester calculations)
    @Published private(set) var ptoUsageByDate: [Date: Int] = [:]
    
    private let authManager = AuthManager.shared
    private let alertManager = AlertManager.shared
    
    private init() {}
    
    // MARK: - Computed Properties
    
    /// Pending requests
    var pendingRequests: [TimeOffEntry] {
        allTimeOff.filter { $0.status == .pending }
            .sorted { $0.date < $1.date }
    }
    
    /// Approved requests
    var approvedRequests: [TimeOffEntry] {
        allTimeOff.filter { $0.status == .approved }
            .sorted { $0.date < $1.date }
    }
    
    /// Denied requests
    var deniedRequests: [TimeOffEntry] {
        allTimeOff.filter { $0.status == .denied }
            .sorted { $0.date > $1.date }
    }
    
    /// All requests (for backwards compatibility with views)
    var requests: [TimeOffEntry] {
        allTimeOff
    }
    
    /// Approved time off (alias for backwards compatibility)
    var approvedTimeOff: [TimeOffEntry] {
        approvedRequests
    }
    
    /// Upcoming approved time off (from today onwards)
    var upcomingTimeOff: [TimeOffEntry] {
        let today = Date().startOfDay
        return approvedRequests.filter { $0.date >= today }
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
    
    /// Start listening to time off entries (unified collection)
    func startListening() {
        guard let managerUid = authManager.managerUid,
              let employeeId = authManager.employeeLocalId else {
            print("TimeOffManager: Cannot start listening - managerUid: \(authManager.managerUid ?? "nil"), employeeId: \(authManager.employeeLocalId ?? -1)")
            return
        }
        
        print("TimeOffManager: Starting listener for managerUid=\(managerUid), employeeId=\(employeeId)")
        
        stopListening()
        isLoading = true
        
        // Listen to unified timeOff collection (includes pending, approved, denied)
        // Fetch all entries and filter by employeeId in memory to handle both old and new field names
        timeOffListener = db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        print("TimeOffManager: Listener error: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("TimeOffManager: No documents found")
                        self?.allTimeOff = []
                        self?.calculatePTOUsage()
                        return
                    }
                    
                    print("TimeOffManager: Found \(documents.count) total time off entries")
                    
                    // Filter by employee ID (handles both employeeId and employeeLocalId fields)
                    let allEntries = documents.compactMap { doc -> TimeOffEntry? in
                        guard let entry = try? doc.data(as: TimeOffEntry.self) else {
                            print("TimeOffManager: Failed to decode document: \(doc.documentID)")
                            return nil
                        }
                        // employeeId in the model handles both field names via the decoder
                        return entry.employeeId == employeeId ? entry : nil
                    }
                    
                    self?.allTimeOff = allEntries
                    print("TimeOffManager: Filtered to \(allEntries.count) entries for employee \(employeeId)")
                    
                    // Recalculate PTO usage
                    self?.calculatePTOUsage()
                }
            }
    }
    
    /// Fallback listener for legacy data that uses employeeId instead of employeeLocalId
    private func startLegacyListener(managerUid: String, employeeId: Int) {
        // No longer needed - main listener handles both formats
        print("TimeOffManager: Legacy listener not needed - main listener handles both formats")
    }
    
    /// Stop all listeners
    func stopListening() {
        timeOffListener?.remove()
        timeOffListener = nil
    }
    
    // MARK: - PTO Calculations
    
    /// Calculate PTO usage by date from all non-denied time off entries
    /// Deduplicates entries by date to prevent double-counting
    private func calculatePTOUsage() {
        var usage: [Date: Int] = [:]
        var seenDates: Set<String> = []  // Track date+type to deduplicate
        
        print("TimeOffManager: Calculating PTO from \(allTimeOff.count) total entries")
        
        // Add all PTO entries that are not denied, deduplicating by date
        for entry in allTimeOff where entry.timeOffType == .pto && entry.status != .denied {
            let dateKey = Calendar.current.startOfDay(for: entry.date)
            let dedupeKey = "\(entry.employeeId)_\(dateKey.timeIntervalSince1970)"
            
            // Skip if we've already counted this date for this employee
            if seenDates.contains(dedupeKey) {
                print("  PTO SKIPPED (duplicate): docId=\(entry.documentId ?? "nil") date=\(entry.formattedDate) hours=\(entry.hours)")
                continue
            }
            
            seenDates.insert(dedupeKey)
            usage[dateKey, default: 0] += entry.hours
            print("  PTO: docId=\(entry.documentId ?? "nil") date=\(entry.formattedDate) hours=\(entry.hours) status=\(entry.status.rawValue)")
        }
        
        let totalHours = usage.values.reduce(0, +)
        print("TimeOffManager: Total PTO hours: \(totalHours) from \(usage.count) unique dates")
        
        ptoUsageByDate = usage
    }
    
    // MARK: - Submit Request
    
    /// Submit a new time off entry to the unified timeOff collection
    func submitTimeOff(
        employeeId: Int,
        employeeEmail: String,
        employeeName: String,
        date: Date,
        timeOffType: TimeOffType,
        hours: Int,
        isAllDay: Bool = true,
        startTime: String? = nil,
        endTime: String? = nil,
        vacationGroupId: String? = nil,
        notes: String? = nil
    ) async throws {
        guard let managerUid = authManager.managerUid else {
            throw TimeOffError.notAuthenticated
        }
        
        // Check if employee already has time off for this date
        let requestDate = Calendar.current.startOfDay(for: date)
        let existingEntry = allTimeOff.first { entry in
            Calendar.current.startOfDay(for: entry.date) == requestDate && entry.status != .denied
        }
        
        if let existing = existingEntry {
            throw TimeOffError.duplicateRequest(date: existing.formattedDate, type: existing.timeOffType.displayName)
        }
        
        // Get employee UID (Firebase Auth UID)
        let employeeUid = authManager.appUser?.id
        
        // Check if auto-approval applies
        let shouldAutoApprove = await checkAutoApproval(for: date, timeOffType: timeOffType, managerUid: managerUid)
        
        // Generate a localId for this entry (timestamp-based unique ID)
        let localId = Int(Date().timeIntervalSince1970 * 1000) % 1000000
        
        let entry = TimeOffEntry(
            employeeId: employeeId,
            employeeEmail: employeeEmail,
            employeeName: employeeName,
            date: date,
            timeOffType: timeOffType,
            hours: hours,
            vacationGroupId: vacationGroupId,
            isAllDay: isAllDay,
            startTime: startTime,
            endTime: endTime,
            status: shouldAutoApprove ? .approved : .pending,
            autoApproved: shouldAutoApprove,
            requestedAt: Date(),
            notes: notes
        )
        
        // Create Firestore data with all fields needed by desktop
        var firestoreData = entry.toFirestoreData(employeeUid: employeeUid, managerUid: managerUid)
        firestoreData["localId"] = localId  // Desktop uses localId for syncing
        
        // Use document ID format: {employeeId}_{localId} (matches desktop format)
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .document("\(employeeId)_\(localId)")
            .setData(firestoreData)
        
        let message = shouldAutoApprove
            ? "Your request has been auto-approved!"
            : "Your request has been submitted for review."
        
        alertManager.showSuccess("Request Submitted", message: message)
    }
    
    /// Check if a request should be auto-approved (fewer than 2 others off that day)
    /// Fetches all entries for the date and filters in-memory to avoid composite index requirement
    private func checkAutoApproval(for date: Date, timeOffType: TimeOffType, managerUid: String) async -> Bool {
        // Only auto-approve PTO and Day Off types
        guard timeOffType == .pto || timeOffType == .dayOff else {
            return false
        }
        
        do {
            let requestDate = Calendar.current.startOfDay(for: date)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: requestDate)!
            
            // Fetch all time off entries for this date (no status filter to avoid index)
            let snapshot = try await db.collection("managers")
                .document(managerUid)
                .collection("timeOff")
                .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: requestDate))
                .whereField("date", isLessThan: Timestamp(date: nextDay))
                .getDocuments()
            
            // Filter in-memory for approved entries only
            let approvedCount = snapshot.documents.filter { doc in
                (doc.data()["status"] as? String) == "approved"
            }.count
            
            // Auto-approve if fewer than 2 others are approved off
            return approvedCount < 2
        } catch {
            print("Auto-approval check failed: \(error). Defaulting to pending.")
            return false
        }
    }
    
    // MARK: - Update Request
    
    /// Update a pending time off entry
    func updateTimeOff(
        _ entry: TimeOffEntry,
        newDate: Date,
        newType: TimeOffType,
        newHours: Int,
        newNotes: String?
    ) async throws {
        guard let managerUid = authManager.managerUid,
              let documentId = entry.documentId else {
            throw TimeOffError.invalidRequest
        }
        
        // Only allow editing pending requests
        guard entry.status == .pending else {
            throw TimeOffError.cannotEditApproved
        }
        
        // Check if new date conflicts with existing entries (excluding this one)
        let requestDate = Calendar.current.startOfDay(for: newDate)
        let existingEntry = allTimeOff.first { existing in
            existing.documentId != documentId &&
            Calendar.current.startOfDay(for: existing.date) == requestDate &&
            existing.status != .denied
        }
        
        if let existing = existingEntry {
            throw TimeOffError.duplicateRequest(date: existing.formattedDate, type: existing.timeOffType.displayName)
        }
        
        // Check auto-approval for new date
        let shouldAutoApprove = await checkAutoApproval(for: newDate, timeOffType: newType, managerUid: managerUid)
        
        // Format date as string for desktop compatibility
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: newDate)
        
        // Build update data
        var updateData: [String: Any] = [
            "date": dateString,
            "timeOffType": newType.rawValue,
            "hours": newHours,
            "isAllDay": true,
            "status": shouldAutoApprove ? "approved" : "pending",
            "autoApproved": shouldAutoApprove,
            "updatedAt": Timestamp(date: Date())
        ]
        
        if let notes = newNotes {
            updateData["notes"] = notes
        }
        
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .document(documentId)
            .updateData(updateData)
        
        let message = shouldAutoApprove
            ? "Your request has been updated and auto-approved!"
            : "Your request has been updated."
        
        alertManager.showSuccess("Request Updated", message: message)
    }
    
    // MARK: - Delete Request
    
    /// Delete a time off entry (pending or denied requests can be deleted by employees)
    func deleteTimeOff(_ entry: TimeOffEntry) async throws {
        guard let managerUid = authManager.managerUid,
              let documentId = entry.documentId else {
            throw TimeOffError.invalidRequest
        }
        
        // Only allow deleting pending or denied requests
        guard entry.status == .pending || entry.status == .denied else {
            throw TimeOffError.cannotDeleteApproved
        }
        
        try await db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .document(documentId)
            .delete()
        
        alertManager.showSuccess("Request Deleted", message: "Your time off request has been removed.")
    }
    
    // MARK: - Error Types
    
    enum TimeOffError: LocalizedError {
        case notAuthenticated
        case invalidRequest
        case networkError
        case duplicateRequest(date: String, type: String)
        case cannotEditApproved
        case cannotDeleteApproved
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to submit requests."
            case .invalidRequest:
                return "Invalid request data."
            case .networkError:
                return "Network error. Please try again."
            case .duplicateRequest(let date, let type):
                return "You already have \(type) scheduled for \(date). Delete the existing request first."
            case .cannotEditApproved:
                return "You cannot edit an approved request. Contact your manager for changes."
            case .cannotDeleteApproved:
                return "You cannot delete an approved request. Contact your manager to cancel."
            }
        }
    }
}
