//
//  MyMetricsView.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import SwiftUI

/// Displays the current user's personal metrics grouped by time slice
struct MyMetricsView: View {
    @ObservedObject var leaderboardManager: LeaderboardManager
    
    private let authManager = AuthManager.shared
    
    /// Aggregated metrics for Week/Month/Quarter views
    private var myMetrics: [AggregatedMetric] {
        guard let employeeId = authManager.employeeLocalId else { return [] }
        return leaderboardManager.metricsForEmployee(employeeId: employeeId)
            .sorted { $0.timeSlice < $1.timeSlice }
    }
    
    /// Daily entries for Day view - grouped by date, filtered by time slice
    private var dailyEntries: [(date: String, entries: [ShiftManagerEntry])] {
        guard let employeeId = authManager.employeeLocalId else { return [] }
        
        // Filter entries for this employee and selected time slice
        let filtered = leaderboardManager.entries.filter { entry in
            entry.employeeId == employeeId &&
            (leaderboardManager.selectedTimeSlice == .all || 
             entry.timeSlice == leaderboardManager.selectedTimeSlice.rawValue)
        }
        
        // Group by date
        let grouped = Dictionary(grouping: filtered) { $0.reportDate }
        
        // Sort by date (oldest first)
        return grouped.map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date < $1.date }
    }
    
    var body: some View {
        if leaderboardManager.selectedDateRangeType == .day {
            // Day view - show individual day cards
            dayView
        } else {
            // Week/Month/Quarter view - show aggregated metrics by time slice
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
                            MetricTimeSliceCard(metric: metric)
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

/// Card displaying all 4 metrics for a single day/shift entry
struct DailyMetricCard: View {
    let entry: ShiftManagerEntry
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var formattedDate: String {
        // Parse the reportDate and format nicely
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        if let date = inputFormatter.date(from: entry.reportDate) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "MMM d, yyyy"
            return outputFormatter.string(from: date)
        }
        return entry.reportDate
    }
    
    private var timeSliceDisplayName: String {
        // Convert raw time slice to display name
        if let slice = TimeSlice(rawValue: entry.timeSlice) {
            return slice.displayName
        }
        return entry.timeSlice
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
                        Image(systemName: timeSliceIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(timeSliceColor)
                        
                        Text(timeSliceDisplayName)
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                // Store badge (for future multi-store support)
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
            
            // Metrics row
            HStack(spacing: AppTheme.Spacing.sm) {
                DailyMetricBadge(metric: .oepe, value: entry.oepe)
                DailyMetricBadge(metric: .kvsHealthyUsage, value: entry.kvsHealthyUsage)
                DailyMetricBadge(metric: .tpph, value: entry.tpph)
                DailyMetricBadge(metric: .r2p, value: entry.r2p)
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
    
    private var timeSliceIcon: String {
        switch entry.timeSlice.lowercased() {
        case let s where s.contains("breakfast"): return "sunrise"
        case let s where s.contains("lunch"): return "sun.max"
        case let s where s.contains("dinner"): return "sunset"
        case let s where s.contains("overnight"): return "moon.stars"
        default: return "clock"
        }
    }
    
    private var timeSliceColor: Color {
        switch entry.timeSlice.lowercased() {
        case let s where s.contains("breakfast"): return AppTheme.Colors.shiftMorning
        case let s where s.contains("lunch"): return AppTheme.Colors.shiftDay
        case let s where s.contains("dinner"): return AppTheme.Colors.shiftEvening
        case let s where s.contains("overnight"): return AppTheme.Colors.shiftNight
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

// MARK: - Metric Time Slice Card

/// Card displaying all 4 metrics for a single time slice
struct MetricTimeSliceCard: View {
    let metric: AggregatedMetric
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Time slice header
            HStack {
                Image(systemName: timeSliceIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(timeSliceColor)
                
                Text(metric.timeSlice)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                // Store badge (for future multi-store support)
                if !metric.storeNsn.isEmpty {
                    Text("#\(metric.storeNsn)")
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
            
            // Metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppTheme.Spacing.md),
                GridItem(.flexible(), spacing: AppTheme.Spacing.md)
            ], spacing: AppTheme.Spacing.md) {
                MetricCell(
                    metric: .oepe,
                    value: metric.oepeAverage,
                    count: metric.oepeCount
                )
                
                MetricCell(
                    metric: .kvsHealthyUsage,
                    value: metric.kvsHealthyUsageAverage,
                    count: metric.kvsHealthyUsageCount
                )
                
                MetricCell(
                    metric: .tpph,
                    value: metric.tpphAverage,
                    count: metric.tpphCount
                )
                
                MetricCell(
                    metric: .r2p,
                    value: metric.r2pAverage,
                    count: metric.r2pCount
                )
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
    
    private var timeSliceIcon: String {
        switch metric.timeSlice.lowercased() {
        case "breakfast": return "sunrise"
        case "lunch": return "sun.max"
        case "dinner": return "sunset"
        case "overnight": return "moon.stars"
        default: return "clock"
        }
    }
    
    private var timeSliceColor: Color {
        switch metric.timeSlice.lowercased() {
        case "breakfast": return AppTheme.Colors.shiftMorning
        case "lunch": return AppTheme.Colors.shiftDay
        case "dinner": return AppTheme.Colors.shiftEvening
        case "overnight": return AppTheme.Colors.shiftNight
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
