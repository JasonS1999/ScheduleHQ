//
//  MyMetricsView.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import SwiftUI

/// Displays the current user's personal metrics grouped by shift label
struct MyMetricsView: View {
    @ObservedObject var leaderboardManager: LeaderboardManager
    
    private let authManager = AuthManager.shared
    
    /// Aggregated metrics for Week/Month/Quarter views
    private var myMetrics: [AggregatedMetric] {
        guard let employeeId = authManager.employeeLocalId else { return [] }
        return leaderboardManager.metricsForEmployee(employeeId: employeeId)
            .sorted { $0.shiftLabel < $1.shiftLabel }
    }
    
    /// Daily entries for Day view - grouped by date, filtered by shift type
    private var dailyEntries: [(date: String, entries: [ShiftManagerEntry])] {
        guard let employeeId = authManager.employeeLocalId else { return [] }
        
        let filtered = leaderboardManager.entries.filter { entry in
            entry.employeeId == employeeId &&
            (leaderboardManager.selectedShiftType == .all || 
             entry.shiftLabel.lowercased() == leaderboardManager.selectedShiftType.label.lowercased() ||
             entry.shiftType.lowercased() == leaderboardManager.selectedShiftType.key.lowercased())
        }
        
        let grouped = Dictionary(grouping: filtered) { $0.reportDate }
        return grouped.map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        if leaderboardManager.selectedDateRangeType == .day {
            dayView
        } else {
            aggregatedView
        }
    }
    
    // MARK: - Day View (Individual Day Cards)
    
    private var dayView: some View {
        Group {
            if dailyEntries.isEmpty {
                emptyDayView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(dailyEntries, id: \.date) { dayData in
                            ForEach(dayData.entries, id: \.id) { entry in
                                DailyMetricCard(entry: entry)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
            }
        }
    }
    
    private var emptyDayView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppTheme.Gradients.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.Gradients.primary)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Shifts Found")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text("You have ran no shifts during this time period. If this is incorrect, please contact administrator.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxxl)
    }
    
    // MARK: - Aggregated View (Week/Month/Quarter)
    
    private var aggregatedView: some View {
        Group {
            if myMetrics.isEmpty {
                emptyPersonalMetricsView
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.md) {
                        ForEach(myMetrics) { metric in
                            MetricShiftLabelCard(metric: metric)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)
                }
            }
        }
    }
    
    private var emptyPersonalMetricsView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppTheme.Gradients.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.Gradients.primary)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Personal Metrics")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text("You have ran no shifts during this time period. If this is incorrect, please contact administrator.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxxl)
    }
}

// MARK: - Daily Metric Card

/// Card displaying all metrics for a single day/shift entry
struct DailyMetricCard: View {
    let entry: ShiftManagerEntry
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = inputFormatter.date(from: entry.reportDate) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "MMM d, yyyy"
            return outputFormatter.string(from: date)
        }
        return entry.reportDate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header: Date and Shift
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: shiftLabelIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(shiftLabelColor)
                        
                        Text(entry.shiftLabel)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                if !entry.storeNsn.isEmpty {
                    Text("#\(entry.storeNsn)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.backgroundSecondary)
                        )
                }
            }
            
            // Metrics rows - 7 metrics in 2 rows
            VStack(spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    DailyMetricBadge(metric: .oepe, value: entry.oepe)
                    DailyMetricBadge(metric: .kvsHealthyUsage, value: entry.kvsHealthyUsage)
                    DailyMetricBadge(metric: .kvsTimePerItem, value: entry.kvsTimePerItem)
                    DailyMetricBadge(metric: .tpph, value: entry.tpph)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    DailyMetricBadge(metric: .r2p, value: entry.r2p)
                    DailyMetricBadge(metric: .punchLaborPct, value: entry.punchLaborPct)
                    DailyMetricBadge(metric: .dtPullForwardPct, value: entry.dtPullForwardPct)
                    Spacer()
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(
                    color: colorScheme == .dark ? .clear : Color.black.opacity(0.05),
                    radius: 8,
                    y: 2
                )
        )
    }
    
    private var shiftLabelIcon: String {
        switch entry.shiftLabel.lowercased() {
        case "open": return "sunrise"
        case "mid": return "sun.max"
        case "close": return "sunset"
        default: return "clock"
        }
    }
    
    private var shiftLabelColor: Color {
        switch entry.shiftLabel.lowercased() {
        case "open": return AppTheme.Colors.shiftMorning
        case "mid": return AppTheme.Colors.shiftDay
        case "close": return AppTheme.Colors.shiftEvening
        default: return AppTheme.Colors.primaryGradientStart
        }
    }
}

// MARK: - Daily Metric Badge

/// Compact badge for displaying a single metric value
struct DailyMetricBadge: View {
    let metric: LeaderboardMetric
    let value: Double?
    
    var body: some View {
        VStack(spacing: 2) {
            Text(metric.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if let value = value {
                Text(metric.format(value))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(AppTheme.Colors.backgroundSecondary)
        )
    }
}

// MARK: - Metric Shift Label Card

/// Card displaying all 7 metrics for a single shift label (aggregated)
struct MetricShiftLabelCard: View {
    let metric: AggregatedMetric
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Shift label header
            HStack {
                Image(systemName: shiftLabelIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(shiftLabelColor)
                
                Text(metric.shiftLabel)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                if !metric.storeNsn.isEmpty {
                    Text("#\(metric.storeNsn)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(Capsule().fill(AppTheme.Colors.backgroundSecondary))
                }
            }
            
            // Metrics grid - 7 metrics
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppTheme.Spacing.md),
                GridItem(.flexible(), spacing: AppTheme.Spacing.md)
            ], spacing: AppTheme.Spacing.md) {
                MetricCell(metric: .oepe, value: metric.oepeAverage, count: metric.oepeCount)
                MetricCell(metric: .kvsHealthyUsage, value: metric.kvsHealthyUsageAverage, count: metric.kvsHealthyUsageCount)
                MetricCell(metric: .kvsTimePerItem, value: metric.kvsTimePerItemAverage, count: metric.kvsTimePerItemCount)
                MetricCell(metric: .tpph, value: metric.tpphAverage, count: metric.tpphCount)
                MetricCell(metric: .r2p, value: metric.r2pAverage, count: metric.r2pCount)
                MetricCell(metric: .punchLaborPct, value: metric.punchLaborPctAverage, count: metric.punchLaborPctCount)
                MetricCell(metric: .dtPullForwardPct, value: metric.dtPullForwardPctAverage, count: metric.dtPullForwardPctCount)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.05), radius: 8, y: 2)
        )
    }
    
    private var shiftLabelIcon: String {
        switch metric.shiftLabel.lowercased() {
        case "open": return "sunrise"
        case "mid": return "sun.max"
        case "close": return "sunset"
        default: return "clock"
        }
    }
    
    private var shiftLabelColor: Color {
        switch metric.shiftLabel.lowercased() {
        case "open": return AppTheme.Colors.shiftMorning
        case "mid": return AppTheme.Colors.shiftDay
        case "close": return AppTheme.Colors.shiftEvening
        default: return AppTheme.Colors.primaryGradientStart
        }
    }
}

// MARK: - Metric Cell

/// Individual metric display cell
struct MetricCell: View {
    let metric: LeaderboardMetric
    let value: Double?
    let count: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(metric.displayName)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            
            if let value = value {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                    Text(metric.format(value))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    if !metric.unit.isEmpty && !metric.displayName.contains("%") {
                        Text(metric.unit)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
                
                Text("\(count) shift\(count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(AppTheme.Colors.backgroundSecondary)
        )
    }
}

#Preview {
    MyMetricsView(leaderboardManager: LeaderboardManager.shared)
}
