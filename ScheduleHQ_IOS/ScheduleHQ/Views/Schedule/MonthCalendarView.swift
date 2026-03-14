import SwiftUI

// MARK: - View Mode Enum

/// Schedule view display mode - Week list or Month calendar
enum ScheduleViewMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

// MARK: - Month Calendar View

/// Monthly calendar grid showing shifts at a glance
struct MonthCalendarView: View {
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    /// Currently selected date for detail view
    @State private var selectedDate: Date? = nil
    
    /// Team schedule sheet presentation
    @State private var teamSchedulePresentation: TeamSchedulePresentation?
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                // Month navigation
                monthNavigationBar
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                
                // Month summary card
                monthSummaryCard
                    .padding(.horizontal, AppTheme.Spacing.lg)
                
                // Day-of-week header row
                dayOfWeekHeader
                    .padding(.horizontal, AppTheme.Spacing.sm)
                
                // Calendar grid
                calendarGrid
                    .padding(.horizontal, AppTheme.Spacing.sm)
                
                // Selected day detail card
                if let selectedDate = selectedDate {
                    selectedDayDetail(for: selectedDate)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .gesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = value.translation.height
                    
                    if abs(horizontalAmount) > abs(verticalAmount) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if horizontalAmount < 0 {
                                scheduleManager.goToNextMonth()
                            } else {
                                scheduleManager.goToPreviousMonth()
                            }
                            selectedDate = nil
                        }
                    }
                }
        )
        .sheet(item: $teamSchedulePresentation) { presentation in
            DayTeamScheduleSheet(date: presentation.date, teamShifts: presentation.shifts, dailyNote: presentation.dailyNote)
        }
    }
    
    // MARK: - Month Navigation Bar
    
    private var monthNavigationBar: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scheduleManager.goToPreviousMonth()
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.primaryGradientStart)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.Colors.primaryGradientStart.opacity(0.1))
                    )
            }
            
            Spacer()
            
            Text(scheduleManager.monthDisplay)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scheduleManager.goToNextMonth()
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.primaryGradientStart)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.Colors.primaryGradientStart.opacity(0.1))
                    )
            }
        }
    }
    
    // MARK: - Day of Week Header
    
    private var dayOfWeekHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(dayLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xs)
            }
        }
    }
    
    // MARK: - Calendar Grid
    
    private var calendarGrid: some View {
        let gridDates = scheduleManager.currentMonth.calendarGridDates
        let monthData = scheduleManager.monthDataByDate
        
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(gridDates, id: \.timeIntervalSince1970) { date in
                let isInCurrentMonth = Calendar.current.isDate(date, equalTo: scheduleManager.currentMonth, toGranularity: .month)
                let dayData = monthData[Calendar.current.startOfDay(for: date)]
                
                CalendarDayCell(
                    date: date,
                    shifts: dayData?.shifts ?? [],
                    timeOff: dayData?.timeOff ?? [],
                    isRunner: dayData?.isRunner ?? false,
                    runnerShiftType: dayData?.runnerShiftType,
                    isInCurrentMonth: isInCurrentMonth,
                    isSelected: selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!),
                    isToday: date.isToday
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let current = selectedDate, Calendar.current.isDate(current, inSameDayAs: date) {
                            selectedDate = nil // Deselect if tapping same day
                        } else {
                            selectedDate = date
                        }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    Task {
                        let result = await scheduleManager.fetchTeamShiftsForDate(date)
                        if !result.shifts.isEmpty {
                            await MainActor.run {
                                teamSchedulePresentation = TeamSchedulePresentation(
                                    date: date,
                                    shifts: result.shifts,
                                    dailyNote: result.dailyNote
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Month Summary Card
    
    private var monthSummaryCard: some View {
        let totalHours = scheduleManager.monthShifts
            .filter { !$0.isOff }
            .reduce(0.0) { $0 + $1.durationHours }
        
        let workingDays = Set(
            scheduleManager.monthShifts
                .filter { !$0.isOff }
                .map { Calendar.current.startOfDay(for: $0.startTime) }
        ).count
        
        let timeOffDays = Set(
            scheduleManager.monthTimeOffEntries
                .map { Calendar.current.startOfDay(for: $0.date) }
        ).count
        
        return HStack(spacing: AppTheme.Spacing.lg) {
            WeekStatView(
                icon: "clock.fill",
                value: String(format: "%.1f", totalHours),
                label: "Hours",
                gradient: AppTheme.Gradients.day
            )
            
            WeekStatView(
                icon: "briefcase.fill",
                value: "\(workingDays)",
                label: "Days",
                gradient: AppTheme.Gradients.primary
            )
            
            if timeOffDays > 0 {
                WeekStatView(
                    icon: "calendar.badge.clock",
                    value: "\(timeOffDays)",
                    label: "Off",
                    gradient: LinearGradient(colors: [AppTheme.Colors.pto, AppTheme.Colors.vacation], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
        }
        .padding(AppTheme.Spacing.lg)
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
    
    // MARK: - Selected Day Detail
    
    @ViewBuilder
    private func selectedDayDetail(for date: Date) -> some View {
        let monthData = scheduleManager.monthDataByDate
        let dayData = monthData[Calendar.current.startOfDay(for: date)]
        let shifts = dayData?.shifts ?? []
        let timeOff = dayData?.timeOff ?? []
        let isRunner = dayData?.isRunner ?? false
        let runnerShiftType = dayData?.runnerShiftType
        let dailyNote = scheduleManager.getMonthScheduleNote(forDate: date)
        
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Date header
            HStack {
                Text(date.fullDate)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        selectedDate = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
            
            CombinedDayCard(
                date: date,
                shifts: shifts,
                timeOff: timeOff,
                isRunner: isRunner,
                runnerShiftType: runnerShiftType,
                dailyNote: dailyNote,
                onLongPress: { date in
                    Task {
                        let result = await scheduleManager.fetchTeamShiftsForDate(date)
                        if !result.shifts.isEmpty {
                            await MainActor.run {
                                teamSchedulePresentation = TeamSchedulePresentation(
                                    date: date,
                                    shifts: result.shifts,
                                    dailyNote: result.dailyNote
                                )
                            }
                        }
                    }
                }
            )
        }
        .padding(AppTheme.Spacing.lg)
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

// MARK: - Calendar Day Cell

/// Individual day cell in the calendar grid
struct CalendarDayCell: View {
    let date: Date
    let shifts: [Shift]
    let timeOff: [TimeOffEntry]
    let isRunner: Bool
    let runnerShiftType: String?
    let isInCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// The primary shift for this day (first non-off shift)
    private var primaryShift: Shift? {
        shifts.first { !$0.isOff }
    }
    
    /// Whether this is a scheduled day off
    private var isDayOff: Bool {
        !shifts.isEmpty && shifts.allSatisfy { $0.isOff }
    }
    
    /// The type of day for rendering
    private var dayType: CalendarDayType {
        if !isInCurrentMonth { return .outsideMonth }
        
        // Check time off types
        if let entry = timeOff.first {
            switch entry.timeOffType {
            case .pto: return .pto
            case .vacation: return .vacation
            case .requested: return .dayOff
            }
        }
        
        // Check shift status
        if let shift = primaryShift {
            if isRunner {
                return .runner(shiftType: shift.shiftTimeType)
            }
            return .working(shift: shift)
        }
        
        if isDayOff {
            return .dayOff
        }
        
        return .empty
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Day number
            Text(date.dayNumber)
                .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(dayNumberColor)
            
            // Content based on day type
            dayContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }
    
    // MARK: - Day Number Color
    
    private var dayNumberColor: Color {
        switch dayType {
        case .outsideMonth:
            return AppTheme.Colors.textTertiary.opacity(0.4)
        case .runner:
            return .white
        default:
            if isToday {
                return AppTheme.Colors.primaryGradientStart
            }
            return isInCurrentMonth ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary
        }
    }
    
    // MARK: - Day Content
    
    @ViewBuilder
    private var dayContent: some View {
        switch dayType {
        case .outsideMonth:
            Spacer()
            
        case .working(let shift):
            Text(shift.compactTimeRange)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(shift.shiftTimeType.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
        case .runner(let shiftType):
            if let shift = primaryShift {
                Text(shift.compactTimeRange)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
        case .dayOff:
            Circle()
                .fill(AppTheme.Colors.shiftOff)
                .frame(width: 8, height: 8)
            
        case .pto:
            Circle()
                .fill(AppTheme.Colors.pto)
                .frame(width: 8, height: 8)
            
        case .vacation:
            Circle()
                .fill(AppTheme.Colors.vacation)
                .frame(width: 8, height: 8)
            
        case .empty:
            Spacer()
        }
    }
    
    // MARK: - Cell Background
    
    private var cellBackground: Color {
        switch dayType {
        case .runner(let shiftType):
            return shiftType.color.opacity(0.85)
        default:
            if isSelected {
                return colorScheme == .dark ? Color.white.opacity(0.1) : AppTheme.Colors.primaryGradientStart.opacity(0.06)
            }
            return .clear
        }
    }
    
    // MARK: - Border
    
    private var borderColor: Color {
        if isToday {
            return AppTheme.Colors.primaryGradientStart
        }
        if isSelected {
            return AppTheme.Colors.primaryGradientStart.opacity(0.5)
        }
        return .clear
    }
    
    private var borderWidth: CGFloat {
        if isToday { return 2 }
        if isSelected { return 1.5 }
        return 0
    }
}

// MARK: - Calendar Day Type

/// Defines what type of day this is for rendering purposes
private enum CalendarDayType {
    case outsideMonth
    case working(shift: Shift)
    case runner(shiftType: ShiftTimeType)
    case dayOff
    case pto
    case vacation
    case empty
}

// MARK: - Previews

#Preview("Month Calendar") {
    NavigationStack {
        ZStack {
            AppBackgroundGradient()
                .ignoresSafeArea()
            MonthCalendarView()
        }
        .navigationTitle("Schedule")
    }
}

#Preview("Month Calendar - Dark") {
    NavigationStack {
        ZStack {
            AppBackgroundGradient()
                .ignoresSafeArea()
            MonthCalendarView()
        }
        .navigationTitle("Schedule")
    }
    .preferredColorScheme(.dark)
}
