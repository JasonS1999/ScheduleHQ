import SwiftUI

/// Combined day card - shows date box on left, shift info on right in one compact card
struct CombinedDayCard: View {
    let date: Date
    let shifts: [Shift]
    let timeOff: [TimeOffEntry]
    var isRunner: Bool = false
    var runnerShiftType: String? = nil
    var dailyNote: String? = nil
    var onLongPress: ((Date) -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var shift: Shift? { shifts.first }
    private var isToday: Bool { date.isToday }
    
    private var shiftType: ShiftTimeType {
        shift?.shiftTimeType ?? .off
    }
    
    private var accentGradient: LinearGradient {
        if isRunner {
            return LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EA580C")], startPoint: .top, endPoint: .bottom)
        }
        return shiftType.gradient
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            accentGradient
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            HStack(spacing: AppTheme.Spacing.md) {
                // Date box on left
                dateBox
                
                // Shift info on right
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    // Top row: badges and duration
                    HStack(alignment: .center) {
                        // Show appropriate badge on left (runner or time off, but NOT day off)
                        if isRunner {
                            RunnerIndicatorBadge(shiftType: runnerShiftType)
                        } else if !timeOff.isEmpty {
                            TimeOffBadgeCompact()
                        }
                        
                        Spacer()
                        
                        // Right side: Day off badge OR duration for working shifts
                        if shift?.isOff == true {
                            DayOffBadge()
                        } else if let shift = shift, !shift.isOff {
                            Text(shift.formattedDuration)
                                .font(AppTheme.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .padding(.vertical, AppTheme.Spacing.xs)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                        }
                    }
                    
                    // Shift time or day off message
                    if let shift = shift {
                        if shift.isOff {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.Colors.success)
                                    .font(.system(size: 14))
                                
                                Text("Enjoy your day off!")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        } else {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(shiftType.color)
                                
                                Text(shift.formattedTimeRange)
                                    .font(AppTheme.Typography.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                            }
                        }
                    } else if !timeOff.isEmpty {
                        // Time off entry
                        if let entry = timeOff.first {
                            Text(entry.timeOffType.rawValue)
                                .font(AppTheme.Typography.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    } else {
                        // No shift scheduled
                        Text("No shift scheduled")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                    
                    // Daily note if exists
                    if let note = dailyNote, !note.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                            Text(note)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    
                    // Shift notes
                    if let notes = shift?.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10))
                            Text(notes)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.md)
                .padding(.trailing, AppTheme.Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(
                    color: AppTheme.Shadows.card.color,
                    radius: AppTheme.Shadows.card.radius,
                    x: AppTheme.Shadows.card.x,
                    y: AppTheme.Shadows.card.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .strokeBorder(
                    isToday ? AppTheme.Colors.primaryGradientStart.opacity(0.5) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear),
                    lineWidth: isToday ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onLongPress?(date)
        }
    }
    
    private var dateBox: some View {
        VStack(spacing: 2) {
            Text(date.dayAbbreviation.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(isToday ? .white : AppTheme.Colors.textSecondary)
            
            Text(date.dayNumber)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? .white : AppTheme.Colors.textPrimary)
        }
        .frame(width: 52, height: 58)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(isToday ? AnyShapeStyle(AppTheme.Gradients.today) : AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6)))
        )
        .padding(.leading, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

/// Compact time off badge for combined card
struct TimeOffBadgeCompact: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .semibold))
            
            Text("TIME OFF")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.Colors.pto)
        )
    }
}

/// Modern card view displaying a shift's details with shift type indicator
struct ShiftCard: View {
    let shift: Shift
    var isRunner: Bool = false
    var runnerShiftType: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    private var shiftType: ShiftTimeType {
        shift.shiftTimeType
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar with gradient - orange if runner
            (isRunner ? LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EA580C")], startPoint: .top, endPoint: .bottom) : shiftType.gradient)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                // Header row with runner badge (if runner) or day off badge, and duration
                HStack(alignment: .center) {
                    // Show RUNNER badge if user is running a shift
                    if isRunner {
                        RunnerIndicatorBadge(shiftType: runnerShiftType)
                    } else if shift.isOff {
                        // Show DAY OFF badge
                        DayOffBadge()
                    }
                    
                    Spacer()
                    
                    if !shift.isOff {
                        // Duration pill
                        Text(shift.formattedDuration)
                            .font(AppTheme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                    }
                }
                
                if shift.isOff {
                    // Off day content - no extra badge, just the message
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.Colors.success)
                            .font(.system(size: 16))
                        
                        Text("Enjoy your day off!")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                } else {
                    // Working shift content
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        // Time display
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(shiftType.color)
                            
                            Text(shift.formattedTimeRange)
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                        }
                    }
                }
                
                // Notes section
                if let notes = shift.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                        
                        Text(notes)
                            .font(AppTheme.Typography.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(
                    color: AppTheme.Shadows.card.color,
                    radius: AppTheme.Shadows.card.radius,
                    x: AppTheme.Shadows.card.x,
                    y: AppTheme.Shadows.card.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

/// Badge showing DAY OFF inside the shift card
struct DayOffBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10, weight: .semibold))
            
            Text("DAY OFF")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(colorScheme == .dark ? .white : AppTheme.Colors.shiftOff)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? AppTheme.Colors.shiftOff : AppTheme.Colors.shiftOff.opacity(0.15))
        )
    }
}

/// Badge showing the shift label - only shows if actual label exists in DB (like "Runner", "Daily Notes")
struct ShiftLabelBadge: View {
    let shift: Shift
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayText: String? {
        shift.displayLabel
    }
    
    private var shiftType: ShiftTimeType {
        shift.shiftTimeType
    }
    
    var body: some View {
        // Only show the badge if there's an actual label from the database
        if let text = displayText {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .semibold))
                
                Text(text.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                Capsule()
                    .fill(shiftType.gradient)
                    .shadow(
                        color: shiftType.color.opacity(0.3),
                        radius: 4,
                        y: 2
                    )
            )
        }
    }
}

/// Badge showing the shift time type (Morning, Day, Evening, Night, Off) - legacy, kept for compatibility
struct ShiftTypeBadge: View {
    let type: ShiftTimeType
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
            
            Text(type.label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(type.gradient)
                .shadow(
                    color: type.color.opacity(0.3),
                    radius: 4,
                    y: 2
                )
        )
    }
}

/// Modern job code badge
struct ModernJobCodeBadge: View {
    let jobCode: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 10))
            
            Text(jobCode)
                .font(AppTheme.Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
    }
}

/// Modern card view for time off entries
struct TimeOffCard: View {
    let entry: TimeOffEntry
    @Environment(\.colorScheme) private var colorScheme
    
    private var typeColor: Color {
        switch entry.timeOffType {
        case .pto: return AppTheme.Colors.pto
        case .vacation: return AppTheme.Colors.vacation
        case .sick: return AppTheme.Colors.sick
        case .dayOff: return AppTheme.Colors.dayOff
        case .requestedOff: return AppTheme.Colors.requestedOff
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            typeColor
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon container
                ZStack {
                    Circle()
                        .fill(typeColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: entry.timeOffType.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(typeColor)
                }
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack {
                        ModernTimeOffTypeBadge(type: entry.timeOffType, color: typeColor)
                        
                        Spacer()
                        
                        // Hours pill
                        Text("\(entry.hours) hrs")
                            .font(AppTheme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                    }
                    
                    if !entry.isAllDay, let timeRange = entry.timeRangeDisplay {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                            
                            Text(timeRange)
                                .font(AppTheme.Typography.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .fill(AppTheme.Colors.cardBackground)
                .shadow(
                    color: AppTheme.Shadows.card.color,
                    radius: AppTheme.Shadows.card.radius,
                    x: AppTheme.Shadows.card.x,
                    y: AppTheme.Shadows.card.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

/// Modern time off type badge
struct ModernTimeOffTypeBadge: View {
    let type: TimeOffType
    let color: Color
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: type.iconName)
                .font(.system(size: 10, weight: .semibold))
            
            Text(type.shortLabel.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(color)
                .shadow(
                    color: color.opacity(0.3),
                    radius: 4,
                    y: 2
                )
        )
    }
}

// MARK: - Previews

#Preview("Modern Shift Cards") {
    ScrollView {
        VStack(spacing: 16) {
            // Morning shift
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!,
                label: "Front Desk",
                notes: "Remember to check the inventory"
            ))
            
            // Day shift
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!,
                label: "Sales"
            ))
            
            // Evening shift
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
            ))
            
            // Night shift
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
            ))
            
            // Off day
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Date(),
                endTime: Date(),
                label: "OFF"
            ))
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Modern Shift Cards - Dark Mode") {
    ScrollView {
        VStack(spacing: 16) {
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!,
                label: "Front Desk",
                notes: "Remember to check the inventory"
            ))
            
            ShiftCard(shift: Shift(
                employeeId: 1,
                startTime: Date(),
                endTime: Date(),
                label: "OFF"
            ))
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}

#Preview("Modern Time Off Cards") {
    VStack(spacing: 16) {
        TimeOffCard(entry: TimeOffEntry(
            employeeId: 1,
            date: Date(),
            timeOffType: .pto,
            hours: 8
        ))
        
        TimeOffCard(entry: TimeOffEntry(
            employeeId: 1,
            date: Date(),
            timeOffType: .vacation,
            hours: 8
        ))
        
        TimeOffCard(entry: TimeOffEntry(
            employeeId: 1,
            date: Date(),
            timeOffType: .sick,
            hours: 4
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Combined Day Card") {
    VStack(spacing: 16) {
        // Regular shift
        CombinedDayCard(
            date: Date(),
            shifts: [Shift(
                id: 1,
                startTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!,
                notes: "Training session"
            )],
            timeOff: [],
            isRunner: false,
            dailyNote: "Team meeting at 2pm"
        )
        
        // Runner shift
        CombinedDayCard(
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            shifts: [Shift(
                id: 2,
                startTime: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
            )],
            timeOff: [],
            isRunner: true,
            runnerShiftType: "AM",
            dailyNote: nil
        )
        
        // Day off
        CombinedDayCard(
            date: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            shifts: [Shift(
                id: 3,
                startTime: Date(),
                endTime: Date(),
                label: "OFF"
            )],
            timeOff: [],
            isRunner: false
        )
        
        // Time off
        CombinedDayCard(
            date: Calendar.current.date(byAdding: .day, value: 3, to: Date())!,
            shifts: [],
            timeOff: [TimeOffEntry(
                employeeId: 1,
                date: Date(),
                timeOffType: .vacation,
                hours: 8
            )],
            isRunner: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
