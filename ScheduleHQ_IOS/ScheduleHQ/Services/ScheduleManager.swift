import Foundation
import FirebaseFirestore
import Combine

/// Manages schedule data and Firestore listeners for shifts
final class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()
    
    private let db = Firestore.firestore()
    private var shiftsListener: ListenerRegistration?
    private var timeOffListener: ListenerRegistration?
    private var shiftRunnersListener: ListenerRegistration?
    private var scheduleNotesListener: ListenerRegistration?
    
    /// Current week's start date
    @Published private(set) var currentWeekStart: Date = Date().startOfWeek
    
    /// Shifts for the current week
    @Published private(set) var shifts: [Shift] = []
    
    /// Time off entries for the current week
    @Published private(set) var timeOffEntries: [TimeOffEntry] = []
    
    /// Shift runners for the current week (who is running each shift)
    @Published private(set) var shiftRunners: [ShiftRunner] = []
    
    /// Daily schedule notes for the current week
    @Published private(set) var scheduleNotes: [ScheduleNote] = []
    
    /// Whether data is loading
    @Published private(set) var isLoading: Bool = false
    
    /// Error message if loading failed
    @Published private(set) var errorMessage: String?
    
    private let authManager = AuthManager.shared
    private let alertManager = AlertManager.shared
    
    private init() {}
    
    // MARK: - Week Navigation
    
    /// Navigate to the previous week
    func goToPreviousWeek() {
        currentWeekStart = currentWeekStart.previousWeekStart
        restartListeners()
    }
    
    /// Navigate to the next week
    func goToNextWeek() {
        currentWeekStart = currentWeekStart.nextWeekStart
        restartListeners()
    }
    
    /// Navigate to the current week
    func goToCurrentWeek() {
        currentWeekStart = Date().startOfWeek
        restartListeners()
    }
    
    /// Whether currently viewing the current week
    var isViewingCurrentWeek: Bool {
        Calendar.current.isDate(currentWeekStart, equalTo: Date().startOfWeek, toGranularity: .day)
    }
    
    /// Formatted week range string
    var weekRangeDisplay: String {
        currentWeekStart.weekRangeFormatted
    }
    
    // MARK: - Data Grouped by Date
    
    /// Shifts grouped by date for display
    var shiftsByDate: [(date: Date, shifts: [Shift], timeOff: [TimeOffEntry])] {
        let dates = currentWeekStart.datesInWeek
        
        return dates.map { date in
            let dayShifts = shifts.filter { $0.isOnDate(date) }
            let dayTimeOff = timeOffEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            return (date: date, shifts: dayShifts, timeOff: dayTimeOff)
        }
    }
    
    // MARK: - Runner and Notes Helpers
    
    /// Check if the current user is a runner for a given date and shift type
    func isCurrentUserRunner(forDate date: Date, shiftType: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
        guard let currentUserName = authManager.employee?.name else { return false }
        
        return shiftRunners.contains { runner in
            runner.date == dateStr && 
            runner.shiftType.lowercased() == shiftType.lowercased() &&
            runner.runnerName.lowercased() == currentUserName.lowercased()
        }
    }
    
    /// Get the runner name for a specific shift on a date
    func getRunnerName(forDate date: Date, shiftType: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
        return shiftRunners.first { runner in
            runner.date == dateStr && runner.shiftType.lowercased() == shiftType.lowercased()
        }?.runnerName
    }
    
    /// Check if current user is a runner for ANY shift on a given date
    func isCurrentUserRunnerForDate(_ date: Date) -> (isRunner: Bool, shiftType: String?) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
        guard let currentUserName = authManager.employee?.name else { return (false, nil) }
        
        if let runner = shiftRunners.first(where: { 
            $0.date == dateStr && $0.runnerName.lowercased() == currentUserName.lowercased() 
        }) {
            return (true, runner.shiftType)
        }
        return (false, nil)
    }
    
    /// Get schedule note for a specific date
    func getScheduleNote(forDate date: Date) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        
        return scheduleNotes.first { $0.date == dateStr }?.note
    }
    
    // MARK: - Listeners
    
    /// Start listening to shifts for the current employee and week
    func startListening() {
        guard let managerUid = authManager.managerUid,
              let currentUid = authManager.currentUser?.uid else {
            errorMessage = "Not authenticated"
            return
        }
        
        stopListening()
        isLoading = true
        errorMessage = nil
        
        let weekStart = currentWeekStart
        let weekEnd = currentWeekStart.endOfWeek
        
        // Format dates as strings like Android does (yyyy-MM-dd)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekStartStr = dateFormatter.string(from: weekStart)
        let weekEndStr = dateFormatter.string(from: weekEnd)  // Saturday end of week
        
        // Month formatter for collection path (schedules/YYYY-MM/shifts)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        
        // Check if user is a manager (their UID matches the managerUid)
        let isManager = currentUid == managerUid
        print("ScheduleManager: currentUid=\(currentUid), managerUid=\(managerUid), isManager=\(isManager)")
        
        // Get the month(s) we need to query - a week can span two months
        let startMonth = monthFormatter.string(from: weekStart)
        let endMonth = monthFormatter.string(from: weekEnd)
        let months = startMonth == endMonth ? [startMonth] : [startMonth, endMonth]
        
        // Query shifts from schedules/{YYYY-MM}/shifts collection
        fetchShiftsFromSchedules(months: months, weekStartStr: weekStartStr, weekEndStr: weekEndStr, 
                                  currentUid: currentUid, isManager: isManager)
        
        // Time off still comes from managers/{uid}/timeOff
        let timeOffRef = db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
        
        // Get employee local ID for filtering
        let employeeLocalId = authManager.employeeLocalId
        print("ScheduleManager: employeeLocalId = \(employeeLocalId ?? -1), isManager = \(isManager)")
        
        // Always filter time off by current user's employeeLocalId (even for managers)
        // Managers see their own time off in Schedule view, not everyone's
        timeOffListener = timeOffRef
            .addSnapshotListener { [weak self, weekStart, weekEnd, employeeLocalId] snapshot, error in
                Task { @MainActor in
                    if error != nil { 
                        print("ScheduleManager: timeOff listener error: \(error!)")
                        return 
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.timeOffEntries = []
                        return
                    }
                    
                    print("ScheduleManager: Found \(documents.count) total timeOff docs, filtering for employeeLocalId=\(employeeLocalId ?? -1)")
                    
                    // Filter by employee ID and date range in memory
                    let filteredEntries = documents.compactMap { doc -> TimeOffEntry? in
                        guard let entry = try? doc.data(as: TimeOffEntry.self) else { 
                            print("  - Failed to decode doc: \(doc.documentID)")
                            return nil 
                        }
                        
                        // Check if this entry belongs to the current employee
                        guard let empId = employeeLocalId else {
                            print("  - No employeeLocalId available")
                            return nil
                        }
                        
                        if entry.employeeId != empId {
                            return nil // Skip entries for other employees
                        }
                        
                        // Check date range
                        if entry.date >= weekStart && entry.date <= weekEnd {
                            print("  - Including entry: \(entry.formattedDate) for employee \(entry.employeeId)")
                            return entry
                        }
                        return nil
                    }.sorted { $0.date < $1.date }
                    
                    print("ScheduleManager: Filtered to \(filteredEntries.count) entries for current user")
                    self?.timeOffEntries = filteredEntries
                }
            }
        
        // Fetch shift runners from managers/{managerUid}/shiftRunners
        fetchShiftRunners(managerUid: managerUid, weekStartStr: weekStartStr, weekEndStr: weekEndStr)
        
        // Fetch schedule notes from managers/{managerUid}/scheduleNotes
        fetchScheduleNotes(managerUid: managerUid, weekStartStr: weekStartStr, weekEndStr: weekEndStr)
    }
    
    /// Stop all listeners
    func stopListening() {
        shiftsListener?.remove()
        shiftsListener = nil
        timeOffListener?.remove()
        timeOffListener = nil
        shiftRunnersListener?.remove()
        shiftRunnersListener = nil
        scheduleNotesListener?.remove()
        scheduleNotesListener = nil
    }
    
    /// Restart listeners (e.g., after week change)
    private func restartListeners() {
        startListening()
    }
    
    /// Refresh data (for pull-to-refresh)
    func refresh() async {
        // Firestore listeners auto-refresh, but we can restart them
        await MainActor.run {
            startListening()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Fetch shifts from managers/{managerUid}/schedules/{YYYY-MM}/shifts collection
    private func fetchShiftsFromSchedules(months: [String], weekStartStr: String, weekEndStr: String,
                                          currentUid: String, isManager: Bool) {
        guard let managerUid = authManager.managerUid else {
            self.shifts = []
            self.isLoading = false
            return
        }
        
        guard let firstMonth = months.first else {
            self.shifts = []
            self.isLoading = false
            return
        }
        
        // Correct path: managers/{managerUid}/schedules/{month}/shifts
        let basePath = db.collection("managers").document(managerUid).collection("schedules")
        let shiftsRef = basePath.document(firstMonth).collection("shifts")
        
        shiftsListener = shiftsRef.addSnapshotListener { [weak self, weekStartStr, weekEndStr, currentUid, isManager, months, basePath] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    print("❌ Shifts error: \(error)")
                    self.errorMessage = error.localizedDescription
                    self.alertManager.showError("Schedule Error", message: "Failed to load schedule: \(error.localizedDescription)")
                    return
                }
                
                var allDocuments = snapshot?.documents ?? []
                
                // If week spans two months, also fetch from second month
                if months.count > 1, let secondMonth = months.last, secondMonth != firstMonth {
                    do {
                        let secondSnapshot = try await basePath
                            .document(secondMonth)
                            .collection("shifts")
                            .getDocuments()
                        allDocuments.append(contentsOf: secondSnapshot.documents)
                    } catch {
                        // Continue with first month's data if second month fails
                    }
                }
                
                // Filter by date range and optionally by employeeUid
                let filteredShifts = allDocuments.compactMap { doc -> Shift? in
                    let data = doc.data()
                    
                    // Check date range
                    guard let dateStr = data["date"] as? String else { return nil }
                    guard dateStr >= weekStartStr && dateStr <= weekEndStr else { return nil }
                    
                    // For employees, filter by their UID
                    if !isManager {
                        guard let shiftEmployeeUid = data["employeeUid"] as? String,
                              shiftEmployeeUid == currentUid else {
                            return nil
                        }
                    }
                    
                    // Parse the shift
                    return try? doc.data(as: Shift.self)
                }.sorted { $0.startTime < $1.startTime }
                
                self.shifts = filteredShifts
            }
        }
    }
    
    /// Fetch shift runners from managers/{managerUid}/shiftRunners collection
    private func fetchShiftRunners(managerUid: String, weekStartStr: String, weekEndStr: String) {
        let shiftRunnersRef = db.collection("managers")
            .document(managerUid)
            .collection("shiftRunners")
        
        shiftRunnersListener = shiftRunnersRef.addSnapshotListener { [weak self, weekStartStr, weekEndStr] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ ShiftRunners error: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.shiftRunners = []
                    return
                }
                
                // Filter by date range
                let filteredRunners = documents.compactMap { doc -> ShiftRunner? in
                    guard let runner = try? doc.data(as: ShiftRunner.self) else { return nil }
                    // Check if date is within the week
                    guard runner.date >= weekStartStr && runner.date <= weekEndStr else { return nil }
                    print("👟 Runner: date=\(runner.date), type=\(runner.shiftType), name=\(runner.runnerName)")
                    return runner
                }
                
                self.shiftRunners = filteredRunners
            }
        }
    }
    
    /// Fetch schedule notes from managers/{managerUid}/scheduleNotes collection
    private func fetchScheduleNotes(managerUid: String, weekStartStr: String, weekEndStr: String) {
        let scheduleNotesRef = db.collection("managers")
            .document(managerUid)
            .collection("scheduleNotes")
        
        scheduleNotesListener = scheduleNotesRef.addSnapshotListener { [weak self, weekStartStr, weekEndStr] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ ScheduleNotes error: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.scheduleNotes = []
                    return
                }
                
                // Filter by date range
                let filteredNotes = documents.compactMap { doc -> ScheduleNote? in
                    guard let note = try? doc.data(as: ScheduleNote.self) else { return nil }
                    // Check if date is within the week
                    guard note.date >= weekStartStr && note.date <= weekEndStr else { return nil }
                    print("📝 DailyNote: date=\(note.date), note=\(note.note ?? "nil")")
                    return note
                }
                
                self.scheduleNotes = filteredNotes
            }
        }
    }
}
