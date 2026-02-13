import SwiftUI

/// Banner shown when the device is offline
struct OfflineBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
            
            Text("You're offline")
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
            
            Spacer()
            
            Text("Changes will sync when connected")
                .font(AppTheme.Typography.caption)
                .opacity(0.8)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [Color(hex: "F97316"), Color(hex: "EA580C")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .foregroundColor(.white)
    }
}

/// Badge showing request status (pending, approved, denied)
struct StatusBadge: View {
    let status: TimeOffRequestStatus
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: status.iconName)
                .font(.system(size: 10, weight: .semibold))
            
            Text(status.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.3)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(statusColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
        )
        .foregroundColor(statusColor)
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return AppTheme.Colors.warning
        case .approved: return AppTheme.Colors.success
        case .denied: return AppTheme.Colors.error
        }
    }
}

/// Badge for queued (offline) requests
struct QueuedBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 10, weight: .semibold))
            
            Text("QUEUED")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.3)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.25 : 0.15))
        )
        .foregroundColor(.gray)
    }
}

/// Loading overlay view
struct LoadingOverlay: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(colorScheme == .dark ? .white : AppTheme.Colors.primaryGradientStart)
                
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.extraLarge)
                    .fill(.ultraThinMaterial)
            )
            .shadow(
                color: AppTheme.Shadows.elevated.color,
                radius: AppTheme.Shadows.elevated.radius,
                x: AppTheme.Shadows.elevated.x,
                y: AppTheme.Shadows.elevated.y
            )
        }
    }
}

/// Empty state view for lists
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AppTheme.Gradients.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.Gradients.primary)
            }
            
            VStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text(message)
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(
                            Capsule()
                                .fill(AppTheme.Gradients.primary)
                                .shadow(
                                    color: AppTheme.Colors.primaryGradientStart.opacity(0.3),
                                    radius: 8,
                                    y: 4
                                )
                        )
                }
                .padding(.top, AppTheme.Spacing.sm)
            }
        }
        .padding(AppTheme.Spacing.xxxl)
    }
}

/// Modern section header for dates in schedule with working indicator
struct DateHeader: View {
    let date: Date
    let isToday: Bool
    var shift: Shift? = nil
    var hasTimeOff: Bool = false
    var dailyNote: String? = nil  // Daily schedule note
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isWorking: Bool {
        guard let shift = shift else { return false }
        return !shift.isOff
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Date box with gradient for today
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
                    .shadow(
                        color: isToday ? AppTheme.Colors.primaryGradientStart.opacity(0.3) : Color.clear,
                        radius: isToday ? 8 : 0,
                        y: isToday ? 4 : 0
                    )
            )
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // Date label row
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(AppTheme.Gradients.today)
                            )
                    }
                    
                    Text(date.fullDate)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                
                // Status indicators (time off only - day off and runner moved to card)
                if hasTimeOff {
                    TimeOffIndicatorBadge()
                }
                
                // Daily note if exists
                if let note = dailyNote, !note.isEmpty {
                    DailyNoteIndicator(note: note)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

/// Badge showing user is RUNNER for a shift
struct RunnerIndicatorBadge: View {
    var shiftType: String? = nil  // e.g., "close", "open", "lunch", "dinner"
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayText: String {
        if let type = shiftType {
            return "RUNNER (\(type.uppercased()))"
        }
        return "RUNNER"
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "figure.run")
                .font(.system(size: 10, weight: .semibold))
            
            Text(displayText)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(hex: "F97316"), Color(hex: "EA580C")],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        )
    }
}

/// Daily note indicator
struct DailyNoteIndicator: View {
    let note: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "note.text")
                .font(.system(size: 10))
            
            Text(note)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.Colors.textSecondary)
        .padding(.top, 2)
    }
}

/// Badge showing user's actual role for the day (like "Runner", "Daily Notes") - only shows if label exists
struct WorkingIndicatorBadge: View {
    let shiftType: ShiftTimeType
    var shiftLabel: String? = nil  // Actual label from DB like "Runner"
    var shiftTime: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Only show the role badge if there's an actual label from DB
            if let label = shiftLabel, !label.isEmpty {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                    
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.5)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(shiftType.gradient)
                )
            }
            
            // Always show the time
            if let time = shiftTime {
                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(shiftType.color)
            }
        }
    }
}

/// Badge showing user has time off
struct TimeOffIndicatorBadge: View {
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

/// Badge showing day off
struct DayOffIndicatorBadge: View {
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

/// Time off type pill/badge (legacy - kept for compatibility)
struct TimeOffTypeBadge: View {
    let type: TimeOffType
    @Environment(\.colorScheme) private var colorScheme
    
    private var typeColor: Color {
        switch type {
        case .pto: return AppTheme.Colors.pto
        case .vacation: return AppTheme.Colors.vacation
        case .requested: return AppTheme.Colors.requested
        }
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: type.iconName)
                .font(.system(size: 10, weight: .semibold))
            
            Text(type.shortLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.3)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(typeColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
        )
        .foregroundColor(typeColor)
    }
}

/// Job code label pill (legacy - kept for compatibility)
struct JobCodeBadge: View {
    let jobCode: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 9))
            
            Text(jobCode)
                .font(AppTheme.Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(AppTheme.Colors.info)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(AppTheme.Colors.info.opacity(colorScheme == .dark ? 0.2 : 0.1))
        )
    }
}

// MARK: - Previews

#Preview("Modern Status Badges") {
    VStack(spacing: 16) {
        StatusBadge(status: .pending)
        StatusBadge(status: .approved)
        StatusBadge(status: .denied)
        QueuedBadge()
    }
    .padding()
    .background(AppTheme.Colors.backgroundGrouped)
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "calendar.badge.exclamationmark",
        title: "No Shifts Scheduled",
        message: "You don't have any shifts scheduled for this week.",
        action: {},
        actionTitle: "Go to Current Week"
    )
    .background(AppTheme.Colors.backgroundGrouped)
}

#Preview("Date Header - Working") {
    VStack(spacing: 0) {
        DateHeader(
            date: Date(),
            isToday: true,
            shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
            )
        )
        .padding(.horizontal)
        .background(AppTheme.Colors.backgroundGrouped)
        
        DateHeader(
            date: Date().addingTimeInterval(86400),
            isToday: false,
            shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
            )
        )
        .padding(.horizontal)
        .background(AppTheme.Colors.backgroundGrouped)
        
        DateHeader(
            date: Date().addingTimeInterval(86400 * 2),
            isToday: false,
            shift: Shift(
                employeeId: 1,
                startTime: Date(),
                endTime: Date(),
                label: "OFF"
            )
        )
        .padding(.horizontal)
        .background(AppTheme.Colors.backgroundGrouped)
        
        DateHeader(
            date: Date().addingTimeInterval(86400 * 3),
            isToday: false,
            hasTimeOff: true
        )
        .padding(.horizontal)
        .background(AppTheme.Colors.backgroundGrouped)
    }
}

#Preview("Date Header - Dark Mode") {
    VStack(spacing: 0) {
        DateHeader(
            date: Date(),
            isToday: true,
            shift: Shift(
                employeeId: 1,
                startTime: Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!,
                endTime: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
            )
        )
        .padding(.horizontal)
        
        DateHeader(
            date: Date().addingTimeInterval(86400),
            isToday: false,
            shift: Shift(
                employeeId: 1,
                startTime: Date(),
                endTime: Date(),
                label: "OFF"
            )
        )
        .padding(.horizontal)
    }
    .background(AppTheme.Colors.backgroundGrouped)
    .preferredColorScheme(.dark)
}

#Preview("Offline Banner") {
    OfflineBanner()
}
