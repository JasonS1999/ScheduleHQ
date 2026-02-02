import SwiftUI

/// Modern schedule view with week navigation and shift indicators
struct ScheduleView: View {
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    // State for team schedule sheet
    @State private var showTeamSchedule = false
    @State private var selectedDate: Date = Date()
    @State private var teamShifts: [ScheduleManager.TeamShift] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient - lighter and more vibrant
                AppBackgroundGradient()
                    .ignoresSafeArea()
                
                Group {
                    if scheduleManager.isLoading {
                        loadingView
                    } else {
                        scheduleList
                    }
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    weekNavigationToolbar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !scheduleManager.isViewingCurrentWeek {
                        todayButton
                    }
                }
            }
            .refreshable {
                await scheduleManager.refresh()
            }
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        // Swipe left (negative x) = next week
                        // Swipe right (positive x) = previous week
                        let horizontalAmount = value.translation.width
                        let verticalAmount = value.translation.height
                        
                        // Only trigger if horizontal swipe is dominant
                        if abs(horizontalAmount) > abs(verticalAmount) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if horizontalAmount < 0 {
                                    // Swipe left - go to next week
                                    scheduleManager.goToNextWeek()
                                } else {
                                    // Swipe right - go to previous week
                                    scheduleManager.goToPreviousWeek()
                                }
                            }
                        }
                    }
            )
            .sheet(isPresented: $showTeamSchedule) {
                DayTeamScheduleSheet(date: selectedDate, teamShifts: teamShifts)
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(AppTheme.Colors.primaryGradientStart)
            
            Text("Loading schedule...")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
    
    // MARK: - Today Button
    
    private var todayButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scheduleManager.goToCurrentWeek()
            }
        } label: {
            Text("Today")
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(
                    Capsule()
                        .fill(AppTheme.Gradients.primary)
                )
        }
    }
    
    // MARK: - Week Navigation
    
    private var weekNavigationToolbar: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scheduleManager.goToPreviousWeek()
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
            
            Text(scheduleManager.weekRangeDisplay)
                .font(AppTheme.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(minWidth: 140)
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scheduleManager.goToNextWeek()
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
    
    // MARK: - Schedule List
    
    private var scheduleList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.md) {
                // Week summary card at the top
                weekSummaryCard
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                
                // Combined day cards - date + shift info in one card
                ForEach(scheduleManager.shiftsByDate, id: \.date) { dayData in
                    let runnerInfo = scheduleManager.isCurrentUserRunnerForDate(dayData.date)
                    let dailyNote = scheduleManager.getScheduleNote(forDate: dayData.date)
                    
                    CombinedDayCard(
                        date: dayData.date,
                        shifts: dayData.shifts,
                        timeOff: dayData.timeOff,
                        isRunner: runnerInfo.isRunner,
                        runnerShiftType: runnerInfo.shiftType,
                        dailyNote: dailyNote,
                        onLongPress: { date in
                            Task {
                                let shifts = await scheduleManager.fetchTeamShiftsForDate(date)
                                // Only show sheet if someone is working
                                if !shifts.isEmpty {
                                    await MainActor.run {
                                        selectedDate = date
                                        teamShifts = shifts
                                        showTeamSchedule = true
                                    }
                                }
                            }
                        }
                    )
                    .padding(.horizontal, AppTheme.Spacing.lg)
                }
            }
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
    }
    
    // MARK: - Week Summary Card
    
    private var weekSummaryCard: some View {
        let totalHours = scheduleManager.shiftsByDate
            .flatMap { $0.shifts }
            .filter { !$0.isOff }
            .reduce(0.0) { $0 + $1.durationHours }
        
        let workingDays = scheduleManager.shiftsByDate
            .filter { dayData in
                dayData.shifts.contains { !$0.isOff }
            }
            .count
        
        let timeOffDays = scheduleManager.shiftsByDate
            .filter { !$0.timeOff.isEmpty }
            .count
        
        return HStack(spacing: AppTheme.Spacing.lg) {
            // Hours stat
            WeekStatView(
                icon: "clock.fill",
                value: String(format: "%.1f", totalHours),
                label: "Hours",
                gradient: AppTheme.Gradients.day
            )
            
            // Working days stat
            WeekStatView(
                icon: "briefcase.fill",
                value: "\(workingDays)",
                label: "Days",
                gradient: AppTheme.Gradients.primary
            )
            
            // Time off stat
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
    
    // MARK: - Day Content
    
    @ViewBuilder
    private func dayContent(for dayData: (date: Date, shifts: [Shift], timeOff: [TimeOffEntry]), isRunner: Bool = false, runnerShiftType: String? = nil) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Time off entries
            ForEach(dayData.timeOff) { entry in
                TimeOffCard(entry: entry)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            
            // Shifts - pass runner info
            ForEach(dayData.shifts) { shift in
                ShiftCard(shift: shift, isRunner: isRunner, runnerShiftType: runnerShiftType)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            
            // Empty state for the day
            if dayData.shifts.isEmpty && dayData.timeOff.isEmpty {
                emptyDayView
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
        .padding(.bottom, AppTheme.Spacing.md)
    }
    
    // MARK: - Empty Day View
    
    private var emptyDayView: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.Colors.textTertiary)
            
            Text("No shifts scheduled")
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
                    style: StrokeStyle(lineWidth: 1, dash: [5])
                )
        )
    }
}

/// Stat view for the week summary card
struct WeekStatView: View {
    let icon: String
    let value: String
    let label: String
    let gradient: LinearGradient
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(gradient.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(gradient)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Schedule View") {
    ScheduleView()
}

#Preview("Schedule View - Dark Mode") {
    ScheduleView()
        .preferredColorScheme(.dark)
}
