import Foundation
import FirebaseFirestore

/// Manages schedule data and Firestore listeners for shifts
@Observable
final class ScheduleManager {
    static let shared = ScheduleManager()
    
    private let db = Firestore.firestore()
    private var shiftsListener: ListenerRegistration?
    private var timeOffListener: ListenerRegistration?
    
    /// Current week's start date
    private(set) var currentWeekStart: Date = Date().startOfWeek
    
    /// Shifts for the current week
    private(set) var shifts: [Shift] = []
    
    /// Time off entries for the current week
    private(set) var timeOffEntries: [TimeOffEntry] = []
    
    /// Whether data is loading
    private(set) var isLoading: Bool = false
    
    /// Error message if loading failed
    private(set) var errorMessage: String?
    
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
    
    // MARK: - Listeners
    
    /// Start listening to shifts for the current employee and week
    func startListening() {
        guard let managerUid = authManager.managerUid,
              let employeeId = authManager.employeeLocalId else {
            errorMessage = "Not authenticated"
            return
        }
        
        stopListening()
        isLoading = true
        errorMessage = nil
        
        let weekStart = currentWeekStart
        let weekEnd = currentWeekStart.endOfWeek
        
        // Listen to shifts
        shiftsListener = db.collection("managers")
            .document(managerUid)
            .collection("shifts")
            .whereField("employeeId", isEqualTo: employeeId)
            .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: weekStart))
            .whereField("startTime", isLessThanOrEqualTo: Timestamp(date: weekEnd))
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        self?.alertManager.showError("Schedule Error", message: "Failed to load schedule: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.shifts = []
                        return
                    }
                    
                    self?.shifts = documents.compactMap { doc in
                        try? doc.data(as: Shift.self)
                    }.sorted { $0.startTime < $1.startTime }
                }
            }
        
        // Listen to time off entries
        timeOffListener = db.collection("managers")
            .document(managerUid)
            .collection("timeOff")
            .whereField("employeeId", isEqualTo: employeeId)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: weekStart))
            .whereField("date", isLessThanOrEqualTo: Timestamp(date: weekEnd))
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        print("Time off listener error: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.timeOffEntries = []
                        return
                    }
                    
                    self?.timeOffEntries = documents.compactMap { doc in
                        try? doc.data(as: TimeOffEntry.self)
                    }.sorted { $0.date < $1.date }
                }
            }
    }
    
    /// Stop all listeners
    func stopListening() {
        shiftsListener?.remove()
        shiftsListener = nil
        timeOffListener?.remove()
        timeOffListener = nil
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
}
