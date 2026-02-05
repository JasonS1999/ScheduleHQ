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
    
    static var leaderboardCases: [DateRangeType] { [.month, .quarter] }
    static var myMetricsCases: [DateRangeType] { [.day, .week, .month, .quarter] }
}

// MARK: - Leaderboard Metric

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case oepe = "OEPE"
    case kvsHealthyUsage = "Side 2 %"
    case kvsTimePerItem = "KVS"
    case tpph = "TPPH"
    case r2p = "R2P"
    case punchLaborPct = "Labor %"
    case dtPullForwardPct = "Park %"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    var sortAscending: Bool {
        switch self {
        case .oepe, .r2p, .kvsTimePerItem, .punchLaborPct, .dtPullForwardPct:
            return true  // Lower is better
        case .tpph, .kvsHealthyUsage:
            return false // Higher is better
        }
    }
    
    var unit: String {
        switch self {
        case .oepe, .r2p: return "sec"
        case .tpph, .kvsTimePerItem: return ""
        case .kvsHealthyUsage, .punchLaborPct, .dtPullForwardPct: return "%"
        }
    }
    
    static var leaderboardCases: [LeaderboardMetric] {
        [.oepe, .kvsHealthyUsage, .kvsTimePerItem, .tpph, .r2p]
    }
    
    func format(_ value: Double) -> String {
        switch self {
        case .oepe, .r2p: return String(format: "%.1f", value)
        case .tpph, .kvsTimePerItem: return String(format: "%.2f", value)
        case .kvsHealthyUsage, .punchLaborPct, .dtPullForwardPct: return String(format: "%.1f%%", value)
        }
    }
}

// MARK: - Shift Type

struct ShiftType: Identifiable, Hashable, Equatable {
    let id: Int
    let key: String
    let label: String
    
    static let all = ShiftType(id: -1, key: "all", label: "All")
}

// MARK: - Shift Manager Entry

struct ShiftManagerEntry: Codable, Identifiable, Equatable {
    var id: String { "\(employeeId)-\(shiftLabel)-\(reportDate)" }
    
    let employeeId: Int
    let employeeUid: String?
    let runnerName: String
    let shiftLabel: String
    let shiftType: String
    let allNetSales: Double?
    let gc: Double?
    let stwGc: Double?
    let dtPullForwardPct: Double?
    let kvsHealthyUsage: Double?
    let kvsTimePerItem: Double?
    let oepe: Double?
    let punchLaborPct: Double?
    let tpph: Double?
    let r2p: Double?
    
    var storeNsn: String = ""
    var reportDate: String = ""
    var managerUid: String = ""
    
    enum CodingKeys: String, CodingKey {
        case employeeId, employeeUid, runnerName, shiftLabel, shiftType
        case allNetSales, gc, stwGc, dtPullForwardPct
        case kvsHealthyUsage, kvsTimePerItem, oepe, punchLaborPct, tpph, r2p
    }
    
    func value(for metric: LeaderboardMetric) -> Double? {
        switch metric {
        case .oepe: return oepe
        case .kvsHealthyUsage: return kvsHealthyUsage
        case .kvsTimePerItem: return kvsTimePerItem
        case .tpph: return tpph
        case .r2p: return r2p
        case .punchLaborPct: return punchLaborPct
        case .dtPullForwardPct: return dtPullForwardPct
        }
    }
}

// MARK: - Aggregated Metric

struct AggregatedMetric: Identifiable, Equatable {
    var id: String { "\(employeeId)-\(storeNsn)-\(shiftLabel)" }
    
    let employeeId: Int
    let employeeUid: String?
    let storeNsn: String
    let managerUid: String
    let shiftLabel: String
    
    var oepeAverage: Double?
    var kvsHealthyUsageAverage: Double?
    var kvsTimePerItemAverage: Double?
    var tpphAverage: Double?
    var r2pAverage: Double?
    var punchLaborPctAverage: Double?
    var dtPullForwardPctAverage: Double?
    
    var oepeCount: Int = 0
    var kvsHealthyUsageCount: Int = 0
    var kvsTimePerItemCount: Int = 0
    var tpphCount: Int = 0
    var r2pCount: Int = 0
    var punchLaborPctCount: Int = 0
    var dtPullForwardPctCount: Int = 0
    
    func average(for metric: LeaderboardMetric) -> Double? {
        switch metric {
        case .oepe: return oepeAverage
        case .kvsHealthyUsage: return kvsHealthyUsageAverage
        case .kvsTimePerItem: return kvsTimePerItemAverage
        case .tpph: return tpphAverage
        case .r2p: return r2pAverage
        case .punchLaborPct: return punchLaborPctAverage
        case .dtPullForwardPct: return dtPullForwardPctAverage
        }
    }
    
    func count(for metric: LeaderboardMetric) -> Int {
        switch metric {
        case .oepe: return oepeCount
        case .kvsHealthyUsage: return kvsHealthyUsageCount
        case .kvsTimePerItem: return kvsTimePerItemCount
        case .tpph: return tpphCount
        case .r2p: return r2pCount
        case .punchLaborPct: return punchLaborPctCount
        case .dtPullForwardPct: return dtPullForwardPctCount
        }
    }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable, Equatable {
    var id: String { "\(employeeId)-\(storeNsn)" }
    
    let rank: Int
    let employeeId: Int
    let employeeUid: String?
    let storeNsn: String
    let managerUid: String
    let metricValue: Double
    let metric: LeaderboardMetric
    let entryCount: Int
    var isCurrentUser: Bool = false
}
