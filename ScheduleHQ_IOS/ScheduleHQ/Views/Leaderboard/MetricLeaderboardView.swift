//
//  MetricLeaderboardView.swift
//  ScheduleHQ
//
//  Created on 2026-02-04.
//

import SwiftUI

/// Displays a ranked leaderboard of employees for the selected metric
struct MetricLeaderboardView: View {
    @ObservedObject var leaderboardManager: LeaderboardManager
    
    private let employeeCache = EmployeeCache.shared
    private let authManager = AuthManager.shared
    
    private var leaderboardEntries: [LeaderboardEntry] {
        leaderboardManager.leaderboardEntries()
    }
    
    var body: some View {
        if leaderboardEntries.isEmpty {
            emptyLeaderboardView
        } else {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.sm) {
                    // Metric info header
                    metricInfoHeader
                    
                    // Leaderboard rows
                    ForEach(leaderboardEntries) { entry in
                        LeaderboardRow(entry: entry)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }
    
    // MARK: - Metric Info Header
    
    private var metricInfoHeader: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: leaderboardManager.selectedMetric.sortAscending ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .semibold))
            
            Text(leaderboardManager.selectedMetric.sortAscending ? "Lower is better" : "Higher is better")
                .font(AppTheme.Typography.caption)
            
            Spacer()
            
            Text("\(leaderboardEntries.count) employee\(leaderboardEntries.count == 1 ? "" : "s")")
                .font(AppTheme.Typography.caption)
        }
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.bottom, AppTheme.Spacing.xs)
    }
    
    // MARK: - Empty State
    
    private var emptyLeaderboardView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppTheme.Gradients.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.Gradients.primary)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("No Leaderboard Data")
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

// MARK: - Leaderboard Row

/// A single row in the leaderboard showing rank, employee info, and metric value
struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let employeeCache = EmployeeCache.shared
    
    private var employee: Employee? {
        // Try by UID first (most reliable), then by local ID
        if let uid = entry.employeeUid, let emp = employeeCache.employee(for: uid) {
            return emp
        }
        return employeeCache.employee(forId: entry.employeeId)
    }
    
    private var employeeName: String {
        employee?.name ?? "Employee #\(entry.employeeId)"
    }
    
    private var profileImageURL: String? {
        employee?.profileImageURL
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Rank indicator
            rankBadge
            
            // Employee avatar
            EmployeeAvatarView(
                imageURL: profileImageURL,
                name: employeeName,
                size: 44,
                accentColor: entry.isCurrentUser ? AppTheme.Colors.primaryGradientStart : .gray,
                showGradient: true
            )
            
            // Employee info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(employeeName)
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(entry.isCurrentUser ? .bold : .semibold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    if entry.isCurrentUser {
                        Text("You")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(AppTheme.Gradients.primary)
                            )
                    }
                }
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    // Store badge (for multi-store support)
                    if !entry.storeNsn.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "building.2")
                                .font(.system(size: 9))
                            Text("#\(entry.storeNsn)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                    
                    Text("\(entry.entryCount) shift\(entry.entryCount == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Metric value
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.metric.format(entry.metricValue))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isCurrentUser ? AppTheme.Colors.primaryGradientStart : AppTheme.Colors.textPrimary)
                
                if !entry.metric.unit.isEmpty && !entry.metric.displayName.contains("%") {
                    Text(entry.metric.unit)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(entry.isCurrentUser ? 
                    AppTheme.Colors.primaryGradientStart.opacity(colorScheme == .dark ? 0.15 : 0.08) : 
                    AppTheme.Colors.cardBackground
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                        .stroke(
                            entry.isCurrentUser ? AppTheme.Colors.primaryGradientStart.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? .clear : Color.black.opacity(0.03),
                    radius: 4,
                    y: 1
                )
        )
    }
    
    // MARK: - Rank Badge
    
    @ViewBuilder
    private var rankBadge: some View {
        ZStack {
            if entry.rank <= 3 {
                // Medal for top 3
                Circle()
                    .fill(medalColor.gradient)
                    .frame(width: 32, height: 32)
                
                Text("\(entry.rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                // Simple number for others
                Text("\(entry.rank)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 32)
            }
        }
        .frame(width: 32)
    }
    
    private var medalColor: Color {
        switch entry.rank {
        case 1: return Color(hex: "FFD700") // Gold
        case 2: return Color(hex: "C0C0C0") // Silver
        case 3: return Color(hex: "CD7F32") // Bronze
        default: return .gray
        }
    }
}

#Preview {
    MetricLeaderboardView(leaderboardManager: LeaderboardManager.shared)
}
