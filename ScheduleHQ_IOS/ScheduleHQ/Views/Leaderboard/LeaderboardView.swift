//
//  LeaderboardView.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import SwiftUI

/// Main container view for the Leaderboard tab
/// Provides toggle between "My Metrics" and "Leaderboard" views
struct LeaderboardView: View {
    @ObservedObject private var leaderboardManager = LeaderboardManager.shared
    @State private var selectedTab: Int = 0 // 0 = My Metrics, 1 = Leaderboard
    
    private let authManager = AuthManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View toggle
                Picker("View", selection: $selectedTab) {
                    Text("My Metrics").tag(0)
                    Text("Leaderboard").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.md)
                
                // Filters
                filtersSection
                
                Divider()
                    .padding(.top, AppTheme.Spacing.sm)
                
                // Content
                Group {
                    if leaderboardManager.isLoading {
                        loadingView
                    } else if let errorMessage = leaderboardManager.errorMessage {
                        errorView(message: errorMessage)
                    } else if leaderboardManager.aggregatedMetrics.isEmpty {
                        emptyStateView
                    } else {
                        if selectedTab == 0 {
                            MyMetricsView(leaderboardManager: leaderboardManager)
                        } else {
                            MetricLeaderboardView(leaderboardManager: leaderboardManager)
                        }
                    }
                }
            }
            .background(AppTheme.Colors.backgroundGrouped)
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        leaderboardManager.goToToday()
                        Task {
                            await leaderboardManager.fetchData()
                        }
                    } label: {
                        Text("Today")
                            .font(AppTheme.Typography.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .task {
                await EmployeeCache.shared.loadEmployees()
                await leaderboardManager.fetchData()
            }
            .onChange(of: leaderboardManager.selectedDateRangeType) { _ in
                Task {
                    await leaderboardManager.fetchData()
                }
            }
            .onChange(of: leaderboardManager.selectedDate) { _ in
                Task {
                    await leaderboardManager.fetchData()
                }
            }
            .onChange(of: leaderboardManager.selectedTimeSlice) { _ in
                // Re-aggregate with new time slice filter
                leaderboardManager.recomputeAggregation()
            }
            .onChange(of: selectedTab) { _ in
                // When switching tabs, ensure date range type is valid for the new view
                let validRanges = selectedTab == 0 ? DateRangeType.myMetricsCases : DateRangeType.leaderboardCases
                if !validRanges.contains(leaderboardManager.selectedDateRangeType) {
                    leaderboardManager.selectedDateRangeType = validRanges.first ?? .month
                }
            }
        }
    }
    
    // MARK: - Filters Section
    
    /// Get the available date range types based on the current view
    private var availableDateRangeTypes: [DateRangeType] {
        selectedTab == 0 ? DateRangeType.myMetricsCases : DateRangeType.leaderboardCases
    }
    
    private var filtersSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Date range type picker
            Picker("Range", selection: $leaderboardManager.selectedDateRangeType) {
                ForEach(availableDateRangeTypes) { rangeType in
                    Text(rangeType.rawValue).tag(rangeType)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            // Date navigation
            HStack(spacing: AppTheme.Spacing.lg) {
                Button {
                    leaderboardManager.goToPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.primaryGradientStart)
                }
                
                Spacer()
                
                Text(leaderboardManager.dateRangeDisplay())
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    leaderboardManager.goToNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.primaryGradientStart)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
            
            // Time slice and metric filters (only show metric picker in leaderboard mode)
            HStack(spacing: AppTheme.Spacing.md) {
                // Time slice picker
                Menu {
                    ForEach(TimeSlice.allCases) { slice in
                        Button {
                            leaderboardManager.selectedTimeSlice = slice
                        } label: {
                            HStack {
                                Text(slice.displayName)
                                if leaderboardManager.selectedTimeSlice == slice {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(leaderboardManager.selectedTimeSlice.displayName)
                            .font(AppTheme.Typography.caption)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(AppTheme.Colors.backgroundSecondary)
                    )
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                
                // Metric picker (leaderboard mode only)
                if selectedTab == 1 {
                    Menu {
                        ForEach(LeaderboardMetric.allCases) { metric in
                            Button {
                                leaderboardManager.selectedMetric = metric
                            } label: {
                                HStack {
                                    Text(metric.displayName)
                                    if leaderboardManager.selectedMetric == metric {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 12))
                            Text(leaderboardManager.selectedMetric.displayName)
                                .font(AppTheme.Typography.caption)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.backgroundSecondary)
                        )
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundPrimary)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading metrics...")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.error.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.error)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Unable to Load")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await leaderboardManager.fetchData()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(
                    Capsule()
                        .fill(AppTheme.Gradients.primary)
                )
            }
            .padding(.top, AppTheme.Spacing.sm)
            
            Spacer()
        }
        .padding(AppTheme.Spacing.xxxl)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "chart.bar.xaxis",
            title: "No Data Available",
            message: "Contact your administrator if you believe data should be present for this time period."
        )
    }
}

#Preview {
    LeaderboardView()
}
