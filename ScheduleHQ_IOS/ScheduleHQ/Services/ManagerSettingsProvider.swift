import Foundation
import FirebaseFirestore
import Combine

/// Provides real-time access to manager settings from Firestore.
/// Used by the iOS app to enforce policies configured by the manager on desktop.
final class ManagerSettingsProvider: ObservableObject {
    static let shared = ManagerSettingsProvider()

    private let db = Firestore.firestore()
    private let authManager = AuthManager.shared
    private var listener: ListenerRegistration?

    @Published private(set) var requestDeadlineEnabled: Bool = false
    @Published private(set) var requestDeadlineDay: Int = 15

    /// Job code settings synced from the Desktop app, keyed by lowercase code.
    /// Each entry contains at minimum a "code" (String) and "hasPTO" (Bool/Int).
    private var ptoEnabledCodes: Set<String> = []

    private init() {}

    /// Returns whether the given job code has PTO enabled.
    /// Defaults to `false` if job code settings haven't been synced yet.
    func hasPTO(forJobCode code: String) -> Bool {
        ptoEnabledCodes.contains(code.lowercased())
    }

    func startListening() {
        guard let managerUid = authManager.managerUid else { return }
        stopListening()

        listener = db.collection("managerSettings")
            .document(managerUid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let data = snapshot?.data() else { return }

                DispatchQueue.main.async {
                    if let settings = data["settings"] as? [String: Any] {
                        self?.requestDeadlineEnabled = settings["requestDeadlineEnabled"] as? Bool ?? false
                        self?.requestDeadlineDay = settings["requestDeadlineDay"] as? Int ?? 15
                    }

                    // Parse job code settings to determine PTO eligibility per code
                    if let jobCodes = data["jobCodeSettings"] as? [[String: Any]] {
                        var codes = Set<String>()
                        for jc in jobCodes {
                            guard let code = jc["code"] as? String else { continue }
                            // hasPTO may arrive as Bool (from Firebase) or Int (0/1 from Desktop sync)
                            let hasPTO: Bool
                            if let boolVal = jc["hasPTO"] as? Bool {
                                hasPTO = boolVal
                            } else if let intVal = jc["hasPTO"] as? Int {
                                hasPTO = intVal == 1
                            } else {
                                hasPTO = false
                            }
                            if hasPTO {
                                codes.insert(code.lowercased())
                            }
                        }
                        self?.ptoEnabledCodes = codes
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Deadline Validation

    /// Returns an error message if the deadline for `targetDate` has passed, otherwise nil.
    static func deadlineError(
        for targetDate: Date,
        deadlineDay: Int,
        deadlineEnabled: Bool
    ) -> String? {
        guard deadlineEnabled else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let targetMonth = calendar.component(.month, from: targetDate)
        let targetYear = calendar.component(.year, from: targetDate)

        // Deadline is day D of the month before the target month
        var deadlineMonth = targetMonth - 1
        var deadlineYear = targetYear
        if deadlineMonth == 0 {
            deadlineMonth = 12
            deadlineYear -= 1
        }

        // Clamp day to the number of days in the deadline month
        let daysInDeadlineMonth = calendar.range(
            of: .day, in: .month,
            for: calendar.date(from: DateComponents(year: deadlineYear, month: deadlineMonth))!
        )!.count
        let clampedDay = min(deadlineDay, daysInDeadlineMonth)

        guard let deadlineDate = calendar.date(from: DateComponents(
            year: deadlineYear, month: deadlineMonth, day: clampedDay
        )) else { return nil }

        if today > deadlineDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            let deadlineStr = formatter.string(from: deadlineDate)

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM"
            let targetMonthStr = monthFormatter.string(from: targetDate)

            return "The deadline for \(targetMonthStr) requests was \(deadlineStr). You can still request time off for future months."
        }

        return nil
    }

    /// Returns an error message if the deadline for any month in a date range has passed.
    static func deadlineError(
        for startDate: Date,
        endDate: Date,
        deadlineDay: Int,
        deadlineEnabled: Bool
    ) -> String? {
        guard deadlineEnabled else { return nil }

        let calendar = Calendar.current
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var checkedMonths: Set<String> = []

        while current <= end {
            let key = "\(calendar.component(.year, from: current))-\(calendar.component(.month, from: current))"
            if !checkedMonths.contains(key) {
                checkedMonths.insert(key)
                if let error = deadlineError(
                    for: current,
                    deadlineDay: deadlineDay,
                    deadlineEnabled: deadlineEnabled
                ) {
                    return error
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return nil
    }
}
