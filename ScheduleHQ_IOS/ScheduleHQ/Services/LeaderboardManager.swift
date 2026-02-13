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
final class LeaderboardManager: ObservableObject {
    static let shared = LeaderboardManager()
    
    private let db = Firestore.firestore()
    private let authManager = AuthManager.shared
    
    // MARK: - Published State
    
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var entries: [ShiftManagerEntry] = []
    @Published private(set) var aggregatedMetrics: [AggregatedMetric] = []
    @Published private(set) var shiftTypes: [ShiftType] = [.all]
    
    // MARK: - Filters
    
    @Published var selectedDateRangeType: DateRangeType = .month
    @Published var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @Published var selectedShiftType: ShiftType = .all
    @Published var selectedMetric: LeaderboardMetric = .oepe
    
    private init() {}

    /// Whether shift types have been loaded (avoids redundant fetches)
    private var shiftTypesLoaded = false
    
    // MARK: - Date Range Calculations
    
    func dateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        switch selectedDateRangeType {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            return (start, start)
            
        case .week:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
            components.weekday = 1
            let sunday = calendar.date(from: components) ?? selectedDate
            let saturday = calendar.date(byAdding: .day, value: 6, to: sunday) ?? selectedDate
            return (calendar.startOfDay(for: sunday), calendar.startOfDay(for: saturday))
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            let firstOfMonth = calendar.date(from: components) ?? selectedDate
            let lastOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfMonth) ?? selectedDate
            return (calendar.startOfDay(for: firstOfMonth), calendar.startOfDay(for: lastOfMonth))
            
        case .quarter:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            let month = components.month ?? 1
            let year = components.year ?? 2024
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = quarterStartMonth
            startComponents.day = 1
            
            let firstOfQuarter = calendar.date(from: startComponents) ?? selectedDate
            let lastOfQuarter = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: firstOfQuarter) ?? selectedDate
            return (calendar.startOfDay(for: firstOfQuarter), calendar.startOfDay(for: lastOfQuarter))
        }
    }
    
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
        case .quarter:
            let calendar = Calendar.current
            let month = calendar.component(.month, from: start)
            let year = calendar.component(.year, from: start)
            let quarterNumber = ((month - 1) / 3) + 1
            return "Q\(quarterNumber) \(year)"
        }
    }
    
    func goToPrevious() {
        let calendar = Calendar.current
        switch selectedDateRangeType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        case .quarter:
            selectedDate = calendar.date(byAdding: .month, value: -3, to: selectedDate) ?? selectedDate
        }
    }
    
    func goToNext() {
        guard canGoNext else { return }
        let calendar = Calendar.current
        switch selectedDateRangeType {
        case .day:
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        case .quarter:
            selectedDate = calendar.date(byAdding: .month, value: 3, to: selectedDate) ?? selectedDate
        }
    }
    
    var canGoNext: Bool {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let (_, currentEnd) = dateRange()
        return currentEnd < calendar.startOfDay(for: yesterday)
    }
    
    func goToYesterday() {
        let calendar = Calendar.current
        selectedDate = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }
    
    // MARK: - Data Fetching
    
    @MainActor
    func recomputeAggregation() {
        aggregatedMetrics = aggregateEntries(entries)
    }
    
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
            // Fetch shift types first
            await fetchShiftTypes(managerUid: primaryManagerUid)
            
            var allEntries: [ShiftManagerEntry] = []
            
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
    
    /// Fetch shift types from managerSettings document
    @MainActor
    private func fetchShiftTypes(managerUid: String) async {
        guard !shiftTypesLoaded else { return }

        do {
            // Shift types are stored in managerSettings collection, not managers
            let docRef = db.collection("managerSettings").document(managerUid)
            let snapshot = try await docRef.getDocument(source: .default)
            
            guard let data = snapshot.data(),
                  let shiftTypesData = data["shiftTypes"] as? [[String: Any]] else {
                print("LeaderboardManager: No shiftTypes found in managerSettings/\(managerUid)")
                return
            }
            
            var types: [ShiftType] = [.all]
            for (index, typeData) in shiftTypesData.enumerated() {
                // key and label are required, id is optional (default to index)
                if let key = typeData["key"] as? String,
                   let label = typeData["label"] as? String {
                    let id = typeData["id"] as? Int ?? index
                    types.append(ShiftType(id: id, key: key, label: label))
                }
            }
            shiftTypes = types
            shiftTypesLoaded = true
            print("LeaderboardManager: Loaded \(types.count - 1) shift types: \(types.map { $0.label })")
            
        } catch {
            print("LeaderboardManager: Error fetching shift types: \(error)")
        }
    }
    
    private func fetchEntriesForManager(managerUid: String) async throws -> [ShiftManagerEntry] {
        let (startDate, endDate) = dateRange()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dates: [String] = []
        var currentDate = startDate
        let calendar = Calendar.current

        while currentDate <= endDate {
            dates.append(dateFormatter.string(from: currentDate))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate.addingTimeInterval(86400)
        }

        // Fetch all dates in parallel using TaskGroup
        return try await withThrowingTaskGroup(of: [ShiftManagerEntry].self) { group in
            for dateStr in dates {
                group.addTask {
                    try await self.fetchEntriesForDate(managerUid: managerUid, date: dateStr)
                }
            }

            var allEntries: [ShiftManagerEntry] = []
            for try await dateEntries in group {
                allEntries.append(contentsOf: dateEntries)
            }
            return allEntries
        }
    }

    /// Fetch shift runners and report entries for a single date in parallel
    private func fetchEntriesForDate(managerUid: String, date: String) async throws -> [ShiftManagerEntry] {
        // Fetch shift runners and report document in parallel
        async let shiftRunners = fetchShiftRunners(managerUid: managerUid, date: date)
        async let reportSnapshot = db.collection("managers")
            .document(managerUid)
            .collection("shiftManagerReports")
            .document(date)
            .getDocument(source: .default)

        let runners = try await shiftRunners
        let snapshot = try await reportSnapshot

        guard snapshot.exists, let data = snapshot.data() else { return [] }

        let storeNsn = data["location"] as? String ?? ""
        var entries: [ShiftManagerEntry] = []

        if let entriesData = data["entries"] as? [[String: Any]] {
            for entryData in entriesData {
                if var entry = parseEntry(from: entryData, shiftRunners: runners) {
                    entry.storeNsn = storeNsn
                    entry.reportDate = date
                    entry.managerUid = managerUid
                    entries.append(entry)
                }
            }
        }

        return entries
    }
    
    /// Fetch shift runners for a specific date to get employeeId/employeeUid
    private func fetchShiftRunners(managerUid: String, date: String) async throws -> [String: (employeeId: Int, employeeUid: String?)] {
        var runners: [String: (employeeId: Int, employeeUid: String?)] = [:]
        
        let runnersRef = db.collection("managers")
            .document(managerUid)
            .collection("shiftRunners")
        
        // Query runners for this date (document IDs are formatted as {date}_{shiftType})
        let snapshot = try await runnersRef
            .whereField("date", isEqualTo: date)
            .getDocuments(source: .default)
        
        for doc in snapshot.documents {
            let data = doc.data()
            if let shiftType = data["shiftType"] as? String,
               let employeeId = data["employeeId"] as? Int {
                let employeeUid = data["employeeUid"] as? String
                runners[shiftType.lowercased()] = (employeeId: employeeId, employeeUid: employeeUid)
                print("LeaderboardManager: Found runner for \(date)/\(shiftType): employeeId=\(employeeId), uid=\(employeeUid ?? "nil")")
            }
        }
        
        return runners
    }
    
    private func parseEntry(from data: [String: Any], shiftRunners: [String: (employeeId: Int, employeeUid: String?)]) -> ShiftManagerEntry? {
        let shiftLabel = data["shiftLabel"] as? String ?? ""
        let shiftType = data["shiftType"] as? String ?? ""
        
        // Initialize from entry data (may be incorrect/missing)
        var employeeId = data["employeeId"] as? Int
        var employeeUid = data["employeeUid"] as? String
        
        print("LeaderboardManager: Parsing entry - shiftType='\(shiftType)', shiftLabel='\(shiftLabel)', entry.employeeId=\(employeeId ?? -1)")
        
        // Look up from shiftRunners using shiftType (e.g., "open", "close")
        // ALWAYS prefer shiftRunners data since it has the correct employee linkage
        if let runner = shiftRunners[shiftType.lowercased()] {
            print("LeaderboardManager: Found matching runner - using employeeId=\(runner.employeeId), uid=\(runner.employeeUid ?? "nil")")
            employeeId = runner.employeeId
            employeeUid = runner.employeeUid
        } else {
            print("LeaderboardManager: No runner found for shiftType='\(shiftType.lowercased())'. Available runners: \(shiftRunners.keys.joined(separator: ", "))")
        }
        
        // Require at least employeeId to create an entry
        guard let finalEmployeeId = employeeId, finalEmployeeId > 0 else {
            print("LeaderboardManager: Skipping entry - no employeeId found for shiftType=\(shiftType)")
            return nil
        }
        
        return ShiftManagerEntry(
            employeeId: finalEmployeeId,
            employeeUid: employeeUid,
            runnerName: data["runnerName"] as? String ?? "",
            shiftLabel: shiftLabel,
            shiftType: data["shiftType"] as? String ?? "",
            allNetSales: data["allNetSales"] as? Double,
            gc: data["gc"] as? Double,
            stwGc: data["stwGc"] as? Double,
            dtPullForwardPct: data["dtPullForwardPct"] as? Double,
            kvsHealthyUsage: data["kvsHealthyUsage"] as? Double,
            kvsTimePerItem: data["kvsTimePerItem"] as? Double,
            oepe: data["oepe"] as? Double,
            punchLaborPct: data["punchLaborPct"] as? Double,
            tpph: data["tpph"] as? Double,
            r2p: data["r2p"] as? Double
        )
    }
    
    // MARK: - Aggregation
    
    private func aggregateEntries(_ entries: [ShiftManagerEntry]) -> [AggregatedMetric] {
        var groups: [String: [ShiftManagerEntry]] = [:]
        
        for entry in entries {
            // Filter by shift type if not "All"
            if selectedShiftType != .all {
                guard entry.shiftLabel.lowercased() == selectedShiftType.label.lowercased() ||
                      entry.shiftType.lowercased() == selectedShiftType.key.lowercased() else {
                    continue
                }
            }
            
            let key = "\(entry.employeeId)-\(entry.storeNsn)-\(entry.shiftLabel)"
            groups[key, default: []].append(entry)
        }
        
        var results: [AggregatedMetric] = []
        
        for (_, groupEntries) in groups {
            guard let first = groupEntries.first else { continue }
            
            var aggregated = AggregatedMetric(
                employeeId: first.employeeId,
                employeeUid: first.employeeUid,
                storeNsn: first.storeNsn,
                managerUid: first.managerUid,
                shiftLabel: first.shiftLabel
            )
            
            // OEPE
            let oepeValues = groupEntries.compactMap { $0.oepe }
            if !oepeValues.isEmpty {
                aggregated.oepeAverage = oepeValues.reduce(0, +) / Double(oepeValues.count)
                aggregated.oepeCount = oepeValues.count
            }
            
            // Side 2 %
            let kvsValues = groupEntries.compactMap { $0.kvsHealthyUsage }
            if !kvsValues.isEmpty {
                aggregated.kvsHealthyUsageAverage = kvsValues.reduce(0, +) / Double(kvsValues.count)
                aggregated.kvsHealthyUsageCount = kvsValues.count
            }
            
            // KVS
            let kvsTimeValues = groupEntries.compactMap { $0.kvsTimePerItem }
            if !kvsTimeValues.isEmpty {
                aggregated.kvsTimePerItemAverage = kvsTimeValues.reduce(0, +) / Double(kvsTimeValues.count)
                aggregated.kvsTimePerItemCount = kvsTimeValues.count
            }
            
            // TPPH
            let tpphValues = groupEntries.compactMap { $0.tpph }
            if !tpphValues.isEmpty {
                aggregated.tpphAverage = tpphValues.reduce(0, +) / Double(tpphValues.count)
                aggregated.tpphCount = tpphValues.count
            }
            
            // R2P
            let r2pValues = groupEntries.compactMap { $0.r2p }
            if !r2pValues.isEmpty {
                aggregated.r2pAverage = r2pValues.reduce(0, +) / Double(r2pValues.count)
                aggregated.r2pCount = r2pValues.count
            }
            
            // Labor %
            let laborValues = groupEntries.compactMap { $0.punchLaborPct }
            if !laborValues.isEmpty {
                aggregated.punchLaborPctAverage = laborValues.reduce(0, +) / Double(laborValues.count)
                aggregated.punchLaborPctCount = laborValues.count
            }
            
            // Park %
            let parkValues = groupEntries.compactMap { $0.dtPullForwardPct }
            if !parkValues.isEmpty {
                aggregated.dtPullForwardPctAverage = parkValues.reduce(0, +) / Double(parkValues.count)
                aggregated.dtPullForwardPctCount = parkValues.count
            }
            
            results.append(aggregated)
        }
        
        return results
    }
    
    // MARK: - Filtered Data
    
    func metricsForEmployee(employeeId: Int) -> [AggregatedMetric] {
        aggregatedMetrics.filter { $0.employeeId == employeeId }
    }
    
    func leaderboardEntries() -> [LeaderboardEntry] {
        let currentEmployeeId = authManager.employeeLocalId
        
        var metricsByEmployeeStore: [String: (employeeId: Int, employeeUid: String?, storeNsn: String, managerUid: String, value: Double, count: Int)] = [:]
        
        for metric in aggregatedMetrics {
            guard let value = metric.average(for: selectedMetric) else { continue }
            
            let key = "\(metric.employeeId)-\(metric.storeNsn)"
            
            if let existing = metricsByEmployeeStore[key] {
                let totalCount = existing.count + metric.count(for: selectedMetric)
                let weightedValue = (existing.value * Double(existing.count) + value * Double(metric.count(for: selectedMetric))) / Double(totalCount)
                // Keep existing employeeUid if we have it, otherwise use new one
                let uid = existing.employeeUid ?? metric.employeeUid
                metricsByEmployeeStore[key] = (metric.employeeId, uid, metric.storeNsn, metric.managerUid, weightedValue, totalCount)
            } else {
                metricsByEmployeeStore[key] = (metric.employeeId, metric.employeeUid, metric.storeNsn, metric.managerUid, value, metric.count(for: selectedMetric))
            }
        }
        
        let sorted = metricsByEmployeeStore.values.sorted { a, b in
            if selectedMetric.sortAscending {
                return a.value < b.value
            } else {
                return a.value > b.value
            }
        }
        
        return sorted.enumerated().map { index, item in
            LeaderboardEntry(
                rank: index + 1,
                employeeId: item.employeeId,
                employeeUid: item.employeeUid,
                storeNsn: item.storeNsn,
                managerUid: item.managerUid,
                metricValue: item.value,
                metric: selectedMetric,
                entryCount: item.count,
                isCurrentUser: item.employeeId == currentEmployeeId
            )
        }
    }
}
