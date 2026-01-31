import Foundation
import Combine

/// Manages offline queue for time off requests
@Observable
final class OfflineQueueManager {
    static let shared = OfflineQueueManager()
    
    /// Queued requests waiting to be synced
    private(set) var queuedRequests: [TimeOffRequest] = []
    
    /// Number of queued requests (for badge display)
    var queuedCount: Int {
        queuedRequests.count
    }
    
    /// Whether there are queued requests
    var hasQueuedRequests: Bool {
        !queuedRequests.isEmpty
    }
    
    /// Whether sync is in progress
    private(set) var isSyncing: Bool = false
    
    private let networkMonitor = NetworkMonitor.shared
    private let timeOffManager = TimeOffManager.shared
    private let alertManager = AlertManager.shared
    
    private let queueFileURL: URL
    private var cancellables = Set<AnyCancellable>()
    
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
    
    /// Add a request to the offline queue
    func enqueue(_ request: TimeOffRequest) {
        var queuedRequest = request
        queuedRequest.localId = UUID().uuidString
        
        queuedRequests.append(queuedRequest)
        saveQueue()
        
        alertManager.showInfo("Request Queued", message: "Your request will be submitted when you're back online.")
        
        // Try to sync immediately if connected
        if networkMonitor.isConnected {
            Task {
                await syncQueue()
            }
        }
    }
    
    /// Remove a request from the queue
    func dequeue(_ localId: String) {
        queuedRequests.removeAll { $0.localId == localId }
        saveQueue()
    }
    
    /// Clear all queued requests
    func clearQueue() {
        queuedRequests.removeAll()
        saveQueue()
    }
    
    // MARK: - Sync
    
    /// Sync queued requests when online
    func syncQueue() async {
        guard networkMonitor.isConnected else { return }
        guard !queuedRequests.isEmpty else { return }
        guard !isSyncing else { return }
        
        await MainActor.run {
            isSyncing = true
        }
        
        var successCount = 0
        var failedRequests: [TimeOffRequest] = []
        
        for request in queuedRequests {
            do {
                try await timeOffManager.submitRequest(request)
                successCount += 1
                
                // Remove from queue on success
                if let localId = request.localId {
                    await MainActor.run {
                        queuedRequests.removeAll { $0.localId == localId }
                    }
                }
            } catch {
                // Keep failed requests in queue
                failedRequests.append(request)
                print("Failed to sync request: \(error)")
            }
        }
        
        await MainActor.run {
            isSyncing = false
            saveQueue()
            
            if successCount > 0 && failedRequests.isEmpty {
                alertManager.showSuccess(
                    "Sync Complete",
                    message: "\(successCount) request(s) submitted successfully."
                )
            } else if !failedRequests.isEmpty {
                alertManager.showWarning(
                    "Partial Sync",
                    message: "\(successCount) submitted, \(failedRequests.count) failed. Will retry later."
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
            queuedRequests = try decoder.decode([TimeOffRequest].self, from: data)
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
    
    /// Create a time off request and either submit or queue based on connectivity
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
        let request = TimeOffRequest(
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
        
        if networkMonitor.isConnected {
            do {
                try await timeOffManager.submitRequest(request)
            } catch {
                // If submission fails, queue it
                enqueue(request)
            }
        } else {
            enqueue(request)
        }
    }
}
