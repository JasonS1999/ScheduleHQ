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
    
    private var myMetrics: [AggregatedMetric] {
        guard let employeeId = authManager.employeeLocalId else { return [] }
        return leaderboardManager.metricsForEmployee(employeeId: employeeId)
            .sorted { $0.timeSlice < $1.timeSlice }
    }
    
    var body: some View {
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
                
                Text("Contact your administrator if you believe data should be present for this time period.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(AppTheme.Spacing.xxxl)
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
