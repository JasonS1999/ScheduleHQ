//
//  ShiftManagerReport.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import Foundation

// MARK: - Date Range Type

enum DateRangeType: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    
    var id: String { rawValue }
    
    /// Date range types available for the Leaderboard view (Month, Quarter only)
    static var leaderboardCases: [DateRangeType] {
        [.month, .quarter]
    }
    
    /// Date range types available for My Metrics view (Day, Week, Month, Quarter)
    static var myMetricsCases: [DateRangeType] {
        [.day, .week, .month, .quarter]
    }
}

// MARK: - Leaderboard Metric

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case oepe = "OEPE"
    case kvsHealthyUsage = "KVS Healthy Usage"
    case tpph = "TPPH"
    case r2p = "R2P"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .kvsHealthyUsage:
            return "Side 2 %"
        default:
            return rawValue
        }
    }
    
    /// True if lower values are better (sort ascending), false if higher is better (sort descending)
    var sortAscending: Bool {
        switch self {
        case .oepe, .r2p:
            return true  // Lower is better (time-based metrics)
        case .tpph, .kvsHealthyUsage:
            return false // Higher is better
        }
    }
    
    var unit: String {
        switch self {
        case .oepe, .r2p:
            return "sec"
        case .tpph:
            return ""
        case .kvsHealthyUsage:
            return "%"
        }
    }
    
    /// Format a metric value for display
    func format(_ value: Double) -> String {
        switch self {
        case .oepe, .r2p:
            return String(format: "%.1f", value)
        case .tpph:
            return String(format: "%.2f", value)
        case .kvsHealthyUsage:
            return String(format: "%.1f%%", value)
        }
    }
}

// MARK: - Time Slice

enum TimeSlice: String, CaseIterable, Identifiable {
    case all = "All"
    case breakfast = "Breakfast(7am-9am)"
    case lunch = "Lunch(11am-2pm)"
    case dinner = "Dinner(5pm-7pm)"
    
    var id: String { rawValue }
    
    /// Display name for the UI (shorter, more readable)
    var displayName: String {
        switch self {
        case .all: return "All"
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }
}

// MARK: - Shift Manager Entry

/// Represents a single entry from the shiftManagerReports Firestore collection
struct ShiftManagerEntry: Codable, Identifiable, Equatable {
    var id: String { "\(employeeId)-\(timeSlice)-\(reportDate)" }
    
    let employeeId: Int
    let managerName: String
    let timeSlice: String
    let allNetSales: Double?
    let numberOfShifts: Int?
    let gc: Double?
    let dtPulledForwardPct: Double?
    let kvsHealthyUsage: Double?
    let oepe: Double?
    let punchLaborPct: Double?
    let dtGc: Double?
    let tpph: Double?
    let averageCheck: Double?
    let actVsNeed: Double?
    let r2p: Double?
    
    // Additional context fields (added during fetch)
    var storeNsn: String = ""
    var reportDate: String = ""
    var managerUid: String = ""
    
    enum CodingKeys: String, CodingKey {
        case employeeId
        case managerName
        case timeSlice
        case allNetSales
        case numberOfShifts
        case gc
        case dtPulledForwardPct
        case kvsHealthyUsage
        case oepe
        case punchLaborPct
        case dtGc
        case tpph
        case averageCheck
        case actVsNeed
        case r2p
    }
    
    /// Get the value for a specific metric
    func value(for metric: LeaderboardMetric) -> Double? {
        switch metric {
        case .oepe: return oepe
        case .kvsHealthyUsage: return kvsHealthyUsage
        case .tpph: return tpph
        case .r2p: return r2p
        }
    }
}

// MARK: - Shift Manager Report

/// Represents a daily report document from Firestore
struct ShiftManagerReport: Codable, Identifiable {
    var id: String { reportDate }
    
    let importedAt: Date?
    let fileName: String?
    let location: String?
    let reportDate: String
    let totalEntries: Int?
    let unmatchedEntries: Int?
    let entries: [ShiftManagerEntry]
    
    enum CodingKeys: String, CodingKey {
        case importedAt
        case fileName
        case location
        case reportDate
        case totalEntries
        case unmatchedEntries
        case entries
    }
}

// MARK: - Aggregated Metric

/// Represents computed averages for an employee, keyed by employeeId + storeNsn
struct AggregatedMetric: Identifiable, Equatable {
    /// Composite key: "employeeId-storeNsn-timeSlice"
    var id: String { "\(employeeId)-\(storeNsn)-\(timeSlice)" }
    
    let employeeId: Int
    let storeNsn: String
    let managerUid: String
    let timeSlice: String
    
    // Averages for each metric
    var oepeAverage: Double?
    var kvsHealthyUsageAverage: Double?
    var tpphAverage: Double?
    var r2pAverage: Double?
    
    // Entry counts for weighted averaging
    var oepeCount: Int = 0
    var kvsHealthyUsageCount: Int = 0
    var tpphCount: Int = 0
    var r2pCount: Int = 0
    
    /// Get the average value for a specific metric
    func average(for metric: LeaderboardMetric) -> Double? {
        switch metric {
        case .oepe: return oepeAverage
        case .kvsHealthyUsage: return kvsHealthyUsageAverage
        case .tpph: return tpphAverage
        case .r2p: return r2pAverage
        }
    }
    
    /// Get the entry count for a specific metric
    func count(for metric: LeaderboardMetric) -> Int {
        switch metric {
        case .oepe: return oepeCount
        case .kvsHealthyUsage: return kvsHealthyUsageCount
        case .tpph: return tpphCount
        case .r2p: return r2pCount
        }
    }
}

// MARK: - Leaderboard Entry

/// A ranked entry for display in the leaderboard
struct LeaderboardEntry: Identifiable, Equatable {
    var id: String { "\(employeeId)-\(storeNsn)" }
    
    let rank: Int
    let employeeId: Int
    let storeNsn: String
    let managerUid: String
    let metricValue: Double
    let metric: LeaderboardMetric
    let entryCount: Int
    
    var isCurrentUser: Bool = false
}
