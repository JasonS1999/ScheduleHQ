//
//  LeaderboardManager.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import Foundation
import FirebaseFirestore
import Combine

/// Manages leaderboard data fetching and aggregation from shiftManagerReports
/// Online-only - no caching
final class LeaderboardManager: ObservableObject {
    static let shared = LeaderboardManager()
    
    private let db = Firestore.firestore()
    private let authManager = AuthManager.shared
    
    // MARK: - Published State
    
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var entries: [ShiftManagerEntry] = []
    @Published private(set) var aggregatedMetrics: [AggregatedMetric] = []
    
    // MARK: - Filters
    
    @Published var selectedDateRangeType: DateRangeType = .week
    @Published var selectedDate: Date = Date()
    @Published var selectedTimeSlice: TimeSlice = .all
    @Published var selectedMetric: LeaderboardMetric = .oepe
    
    private init() {}
    
    // MARK: - Date Range Calculations
    
    /// Get the start and end dates for the current selection (Sun-Sat weeks)
    func dateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        switch selectedDateRangeType {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            return (start, start)
            
        case .week:
            // Sunday-Saturday week
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
            components.weekday = 1 // Sunday
            let sunday = calendar.date(from: components) ?? selectedDate
            let saturday = calendar.date(byAdding: .day, value: 6, to: sunday) ?? selectedDate
            return (calendar.startOfDay(for: sunday), calendar.startOfDay(for: saturday))
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            let firstOfMonth = calendar.date(from: components) ?? selectedDate
            let lastOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfMonth) ?? selectedDate
            return (calendar.startOfDay(for: firstOfMonth), calendar.startOfDay(for: lastOfMonth))
        }
    }
    
    /// Format the date range for display
    func dateRangeDisplay() -> String {
        let (start, end) = dateRange()
        let formatter = DateFormatter()
        
        switch selectedDateRangeType {
        case .day:
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: start)
            
        case .week:
            formatter.dateFormat = "MMM d"
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = "MMM d, yyyy"
            return "\(formatter.string(from: start)) - \(endFormatter.string(from: end))"
            
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        }
    }
    
    /// Navigate to previous period
    func goToPrevious() {
        let calendar = Calendar.current
        switch selectedDateRangeType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }
    
    /// Navigate to next period
    func goToNext() {
        let calendar = Calendar.current
        switch selectedDateRangeType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        }
    }
    
    /// Go to today
    func goToToday() {
        selectedDate = Date()
    }
    
    // MARK: - Data Fetching
    
    /// Fetch leaderboard data for the selected date range
    /// - Parameter managerUids: Array of manager UIDs to fetch data from (for future multi-store support)
    @MainActor
    func fetchData(managerUids: [String]? = nil) async {
        guard let primaryManagerUid = authManager.managerUid else {
            errorMessage = "Not authenticated"
            return
        }
        
        let uids = managerUids ?? [primaryManagerUid]
        
        isLoading = true
        errorMessage = nil
        entries = []
        aggregatedMetrics = []
        
        do {
            var allEntries: [ShiftManagerEntry] = []
            
            // Fetch from each manager's shiftManagerReports
            for managerUid in uids {
                let managerEntries = try await fetchEntriesForManager(managerUid: managerUid)
                allEntries.append(contentsOf: managerEntries)
            }
            
            entries = allEntries
            aggregatedMetrics = aggregateEntries(allEntries)
            isLoading = false
            
        } catch {
            isLoading = false
            errorMessage = "Failed to load data. Please try again."
            print("LeaderboardManager: Error fetching data: \(error)")
        }
    }
    
    /// Fetch entries for a specific manager within the date range
    private func fetchEntriesForManager(managerUid: String) async throws -> [ShiftManagerEntry] {
        let (startDate, endDate) = dateRange()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Generate all dates in range
        var dates: [String] = []
        var currentDate = startDate
        let calendar = Calendar.current
        
        while currentDate <= endDate {
            dates.append(dateFormatter.string(from: currentDate))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate.addingTimeInterval(86400)
        }
        
        var allEntries: [ShiftManagerEntry] = []
        
        // Fetch each day's report (online only, no cache)
        for dateStr in dates {
            do {
                let docRef = db.collection("managers")
                    .document(managerUid)
                    .collection("shiftManagerReports")
                    .document(dateStr)
                
                let snapshot = try await docRef.getDocument(source: .server)
                
                guard snapshot.exists, let data = snapshot.data() else {
                    continue
                }
                
                // Get store NSN from the report
                let storeNsn = data["location"] as? String ?? ""
                
                // Parse entries
                if let entriesData = data["entries"] as? [[String: Any]] {
                    for entryData in entriesData {
                        if var entry = parseEntry(from: entryData) {
                            entry.storeNsn = storeNsn
                            entry.reportDate = dateStr
                            entry.managerUid = managerUid
                            allEntries.append(entry)
                        }
                    }
                }
            } catch {
                // Continue on individual date fetch errors
                print("LeaderboardManager: Error fetching \(dateStr): \(error)")
            }
        }
        
        return allEntries
    }
    
    /// Parse a single entry from Firestore data
    private func parseEntry(from data: [String: Any]) -> ShiftManagerEntry? {
        guard let employeeId = data["employeeId"] as? Int,
              let timeSlice = data["timeSlice"] as? String else {
            return nil
        }
        
        return ShiftManagerEntry(
            employeeId: employeeId,
            managerName: data["managerName"] as? String ?? "",
            timeSlice: timeSlice,
            allNetSales: data["allNetSales"] as? Double,
            numberOfShifts: data["numberOfShifts"] as? Int,
            gc: data["gc"] as? Double,
            dtPulledForwardPct: data["dtPulledForwardPct"] as? Double,
            kvsHealthyUsage: data["kvsHealthyUsage"] as? Double,
            oepe: data["oepe"] as? Double,
            punchLaborPct: data["punchLaborPct"] as? Double,
            dtGc: data["dtGc"] as? Double,
            tpph: data["tpph"] as? Double,
            averageCheck: data["averageCheck"] as? Double,
            actVsNeed: data["actVsNeed"] as? Double,
            r2p: data["r2p"] as? Double
        )
    }
    
    // MARK: - Aggregation
    
    /// Aggregate entries by employeeId + storeNsn + timeSlice, computing averages
    private func aggregateEntries(_ entries: [ShiftManagerEntry]) -> [AggregatedMetric] {
        // Group by composite key
        var groups: [String: [ShiftManagerEntry]] = [:]
        
        for entry in entries {
            // Filter by time slice if not "All"
            if selectedTimeSlice != .all {
                guard entry.timeSlice.lowercased() == selectedTimeSlice.rawValue.lowercased() else {
                    continue
                }
            }
            
            let key = "\(entry.employeeId)-\(entry.storeNsn)-\(entry.timeSlice)"
            groups[key, default: []].append(entry)
        }
        
        // Compute averages for each group
        var results: [AggregatedMetric] = []
        
        for (_, groupEntries) in groups {
            guard let first = groupEntries.first else { continue }
            
            var aggregated = AggregatedMetric(
                employeeId: first.employeeId,
                storeNsn: first.storeNsn,
                managerUid: first.managerUid,
                timeSlice: first.timeSlice
            )
            
            // Calculate averages for each metric
            let oepeValues = groupEntries.compactMap { $0.oepe }
            if !oepeValues.isEmpty {
                aggregated.oepeAverage = oepeValues.reduce(0, +) / Double(oepeValues.count)
                aggregated.oepeCount = oepeValues.count
            }
            
            let kvsValues = groupEntries.compactMap { $0.kvsHealthyUsage }
            if !kvsValues.isEmpty {
                aggregated.kvsHealthyUsageAverage = kvsValues.reduce(0, +) / Double(kvsValues.count)
                aggregated.kvsHealthyUsageCount = kvsValues.count
            }
            
            let tpphValues = groupEntries.compactMap { $0.tpph }
            if !tpphValues.isEmpty {
                aggregated.tpphAverage = tpphValues.reduce(0, +) / Double(tpphValues.count)
                aggregated.tpphCount = tpphValues.count
            }
            
            let r2pValues = groupEntries.compactMap { $0.r2p }
            if !r2pValues.isEmpty {
                aggregated.r2pAverage = r2pValues.reduce(0, +) / Double(r2pValues.count)
                aggregated.r2pCount = r2pValues.count
            }
            
            results.append(aggregated)
        }
        
        return results
    }
    
    // MARK: - Filtered Data
    
    /// Get aggregated metrics for a specific employee (for "My Metrics" view)
    func metricsForEmployee(employeeId: Int) -> [AggregatedMetric] {
        aggregatedMetrics.filter { $0.employeeId == employeeId }
    }
    
    /// Get leaderboard entries for the selected metric and time slice
    func leaderboardEntries() -> [LeaderboardEntry] {
        let currentEmployeeId = authManager.employeeLocalId
        
        // Filter by time slice and group by employee+store
        var metricsByEmployeeStore: [String: (employeeId: Int, storeNsn: String, managerUid: String, value: Double, count: Int)] = [:]
        
        for metric in aggregatedMetrics {
            guard let value = metric.average(for: selectedMetric) else { continue }
            
            let key = "\(metric.employeeId)-\(metric.storeNsn)"
            
            if let existing = metricsByEmployeeStore[key] {
                // Weighted average across time slices
                let totalCount = existing.count + metric.count(for: selectedMetric)
                let weightedValue = (existing.value * Double(existing.count) + value * Double(metric.count(for: selectedMetric))) / Double(totalCount)
                metricsByEmployeeStore[key] = (metric.employeeId, metric.storeNsn, metric.managerUid, weightedValue, totalCount)
            } else {
                metricsByEmployeeStore[key] = (metric.employeeId, metric.storeNsn, metric.managerUid, value, metric.count(for: selectedMetric))
            }
        }
        
        // Sort by metric value
        let sorted = metricsByEmployeeStore.values.sorted { a, b in
            if selectedMetric.sortAscending {
                return a.value < b.value  // Lower is better
            } else {
                return a.value > b.value  // Higher is better
            }
        }
        
        // Create ranked entries
        return sorted.enumerated().map { index, item in
            LeaderboardEntry(
                rank: index + 1,
                employeeId: item.employeeId,
                storeNsn: item.storeNsn,
                managerUid: item.managerUid,
                metricValue: item.value,
                metric: selectedMetric,
                entryCount: item.count,
                isCurrentUser: item.employeeId == currentEmployeeId
            )
        }
    }
    
    /// Get unique time slices from current data
    func availableTimeSlices() -> [String] {
        let slices = Set(entries.map { $0.timeSlice })
        return Array(slices).sorted()
    }
}
