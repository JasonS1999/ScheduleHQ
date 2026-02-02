
import Foundation
import Combine

/// Manages offline queue for time off entries
final class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()
    
    /// Queued entries waiting to be synced
    @Published private(set) var queuedRequests: [TimeOffEntry] = []
    
    /// Number of queued entries (for badge display)
    var queuedCount: Int {
        queuedRequests.count
    }
    
    /// Whether there are queued entries
    var hasQueuedRequests: Bool {
        !queuedRequests.isEmpty
    }
    
    /// Whether sync is in progress
    @Published private(set) var isSyncing: Bool = false
    
    private let networkMonitor = NetworkMonitor.shared
    private let timeOffManager = TimeOffManager.shared
    private let alertManager = AlertManager.shared
    
    private let queueFileURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    /// Local ID for queued items (stored separately since TimeOffEntry doesn't have localId)
    private var localIds: [String: String] = [:] // documentId -> localId
    
    private init() {
        // Set up queue file in documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        queueFileURL = documentsPath.appendingPathComponent("offline_queue.json")
        
        // Load existing queue
        loadQueue()
        
        // Watch for network changes to auto-sync
        setupNetworkObserver()
    }
    
    // MARK: - Queue Management
    
    /// Add an entry to the offline queue
    func enqueue(_ entry: TimeOffEntry) {
        var queuedEntry = entry
        let localId = UUID().uuidString
        // Use a synthetic documentId for tracking
        queuedEntry.documentId = "local_\(localId)"
        
        queuedRequests.append(queuedEntry)
        saveQueue()
        
        alertManager.showInfo("Request Queued", message: "Your request will be submitted when you're back online.")
        
        // Try to sync immediately if connected
        if networkMonitor.isConnected {
            Task {
                await syncQueue()
            }
        }
    }
    
    /// Remove an entry from the queue
    func dequeue(_ documentId: String?) {
        guard let documentId = documentId else { return }
        queuedRequests.removeAll { $0.documentId == documentId }
        saveQueue()
    }
    
    /// Clear all queued entries
    func clearQueue() {
        queuedRequests.removeAll()
        saveQueue()
    }
    
    // MARK: - Sync
    
    /// Sync queued entries when online
    func syncQueue() async {
        guard networkMonitor.isConnected else { return }
        guard !queuedRequests.isEmpty else { return }
        guard !isSyncing else { return }
        
        await MainActor.run {
            isSyncing = true
        }
        
        var successCount = 0
        var failedEntries: [TimeOffEntry] = []
        
        for entry in queuedRequests {
            do {
                try await timeOffManager.submitTimeOff(
                    employeeId: entry.employeeId,
                    employeeEmail: entry.employeeEmail ?? "",
                    employeeName: entry.employeeName ?? "",
                    date: entry.date,
                    timeOffType: entry.timeOffType,
                    hours: entry.hours,
                    isAllDay: entry.isAllDay,
                    startTime: entry.startTime,
                    endTime: entry.endTime,
                    vacationGroupId: entry.vacationGroupId,
                    notes: entry.notes
                )
                successCount += 1
                
                // Remove from queue on success
                if let documentId = entry.documentId {
                    await MainActor.run {
                        queuedRequests.removeAll { $0.documentId == documentId }
                    }
                }
            } catch {
                // Keep failed entries in queue
                failedEntries.append(entry)
                print("Failed to sync entry: \(error)")
            }
        }
        
        await MainActor.run {
            isSyncing = false
            saveQueue()
            
            if successCount > 0 && failedEntries.isEmpty {
                alertManager.showSuccess(
                    "Sync Complete",
                    message: "\(successCount) request(s) submitted successfully."
                )
            } else if !failedEntries.isEmpty {
                alertManager.showWarning(
                    "Partial Sync",
                    message: "\(successCount) submitted, \(failedEntries.count) failed. Will retry later."
                )
            }
        }
    }
    
    // MARK: - Persistence
    
    /// Save queue to local file
    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(queuedRequests)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            print("Failed to save offline queue: \(error)")
        }
    }
    
    /// Load queue from local file
    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else {
            queuedRequests = []
            return
        }
        
        do {
            let data = try Data(contentsOf: queueFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            queuedRequests = try decoder.decode([TimeOffEntry].self, from: data)
        } catch {
            print("Failed to load offline queue: \(error)")
            queuedRequests = []
        }
    }
    
    // MARK: - Network Observer
    
    /// Set up observer to sync when network becomes available
    private func setupNetworkObserver() {
        // Poll for network changes and sync when connected
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.networkMonitor.isConnected && self.hasQueuedRequests && !self.isSyncing {
                    Task {
                        await self.syncQueue()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Request Creation Helper
    
    /// Create a time off entry and either submit or queue based on connectivity
    func submitOrQueue(
        employeeId: Int,
        employeeEmail: String,
        employeeName: String,
        date: Date,
        timeOffType: TimeOffType,
        hours: Int,
        isAllDay: Bool,
        startTime: String?,
        endTime: String?,
        vacationGroupId: String?,
        notes: String?
    ) async {
        if networkMonitor.isConnected {
            do {
                try await timeOffManager.submitTimeOff(
                    employeeId: employeeId,
                    employeeEmail: employeeEmail,
                    employeeName: employeeName,
                    date: date,
                    timeOffType: timeOffType,
                    hours: hours,
                    isAllDay: isAllDay,
                    startTime: startTime,
                    endTime: endTime,
                    vacationGroupId: vacationGroupId,
                    notes: notes
                )
            } catch {
                // If submission fails, queue it
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
                    status: .pending,
                    requestedAt: Date(),
                    notes: notes
                )
                enqueue(entry)
            }
        } else {
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
                status: .pending,
                requestedAt: Date(),
                notes: notes
            )
            enqueue(entry)
        }
    }
}
