import SwiftUI

/// Sheet displaying all employees working on a specific day
struct DayTeamScheduleSheet: View {
    let date: Date
    let teamShifts: [ScheduleManager.TeamShift]
    let dailyNote: String?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    // Header with count
                    HStack {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.Colors.primaryGradientStart)
                        
                        Text("\(teamShifts.count) \(teamShifts.count == 1 ? "person" : "people") working")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                    
                    // Daily note if exists
                    if let note = dailyNote, !note.isEmpty {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "note.text")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.Colors.warning)
                            
                            Text(note)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            
                            Spacer()
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .fill(AppTheme.Colors.warning.opacity(0.1))
                        )
                        .padding(.horizontal, AppTheme.Spacing.lg)
                    }
                    
                    // Team shifts list
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(teamShifts) { teamShift in
                            TeamShiftRow(
                                employeeName: teamShift.employeeName,
                                shift: teamShift.shift,
                                runnerShiftType: teamShift.runnerShiftType
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                }
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .background(AppTheme.Colors.backgroundPrimary)
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Row displaying a single employee's shift
struct TeamShiftRow: View {
    let employeeName: String
    let shift: Shift
    let runnerShiftType: String?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var shiftType: ShiftTimeType {
        shift.shiftTimeType
    }
    
    /// Format runner shift type for display (e.g., "lunch" -> "RUNNER (LUNCH)")
    private var runnerBadgeText: String? {
        guard let type = runnerShiftType else { return nil }
        return "RUNNER (\(type.uppercased()))"
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Shift type indicator - use orange for runners
            (runnerShiftType != nil ? LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EA580C")], startPoint: .top, endPoint: .bottom) : shiftType.gradient)
                .frame(width: 4, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            // Employee avatar
            ZStack {
                Circle()
                    .fill((runnerShiftType != nil ? Color(hex: "F97316") : shiftType.color).opacity(0.15))
                
                Text(employeeName.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(runnerShiftType != nil ? Color(hex: "F97316") : shiftType.color)
            }
            .frame(width: 36, height: 36)
            
            // Name and time
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(employeeName)
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    // Shift notes next to name
                    if let notes = shift.notes, !notes.isEmpty {
                        Text("• \(notes)")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(runnerShiftType != nil ? Color(hex: "F97316") : shiftType.color)
                    
                    Text(shift.formattedTimeRange)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Runner badge (only shown for runners)
            if let badgeText = runnerBadgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EA580C")], startPoint: .leading, endPoint: .trailing))
                    )
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(
                    color: AppTheme.Shadows.card.color,
                    radius: AppTheme.Shadows.card.radius,
                    x: AppTheme.Shadows.card.x,
                    y: AppTheme.Shadows.card.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
}

#Preview {
    DayTeamScheduleSheet(
        date: Date(),
        teamShifts: [
            ScheduleManager.TeamShift(
                employeeName: "Jason Sjogren",
                shift: Shift(
                    documentId: "1",
                    id: 1,
                    employeeId: 1,
                    employeeUid: "abc123",
                    startTime: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!,
                    endTime: Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: Date())!,
                    dateString: "2026-02-01",
                    label: nil,
                    notes: "Training new hire"
                ),
                runnerShiftType: "lunch"
            ),
            ScheduleManager.TeamShift(
                employeeName: "Jane Doe",
                shift: Shift(
                    documentId: "2",
                    id: 2,
                    employeeId: 2,
                    employeeUid: "def456",
                    startTime: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!,
                    endTime: Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!,
                    dateString: "2026-02-01",
                    label: nil,
                    notes: nil
                ),
                runnerShiftType: nil
            )
        ],
        dailyNote: "$8 and $5 EVM deals end"
    )
}
