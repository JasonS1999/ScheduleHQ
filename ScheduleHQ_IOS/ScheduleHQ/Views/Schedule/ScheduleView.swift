import SwiftUI

/// Main schedule view with week navigation
struct ScheduleView: View {
    private let scheduleManager = ScheduleManager.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if scheduleManager.isLoading {
                    ProgressView("Loading schedule...")
                } else {
                    scheduleList
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    weekNavigationToolbar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !scheduleManager.isViewingCurrentWeek {
                        Button {
                            scheduleManager.goToCurrentWeek()
                        } label: {
                            Text("Today")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .refreshable {
                await scheduleManager.refresh()
            }
        }
    }
    
    // MARK: - Week Navigation
    
    private var weekNavigationToolbar: some View {
        HStack(spacing: 16) {
            Button {
                scheduleManager.goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
            }
            
            Text(scheduleManager.weekRangeDisplay)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(minWidth: 150)
            
            Button {
                scheduleManager.goToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }
    
    // MARK: - Schedule List
    
    private var scheduleList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(scheduleManager.shiftsByDate, id: \.date) { dayData in
                    Section {
                        dayContent(for: dayData)
                    } header: {
                        DateHeader(date: dayData.date, isToday: dayData.date.isToday)
                            .padding(.horizontal)
                            .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Day Content
    
    @ViewBuilder
    private func dayContent(for dayData: (date: Date, shifts: [Shift], timeOff: [TimeOffEntry])) -> some View {
        VStack(spacing: 8) {
            // Time off entries
            ForEach(dayData.timeOff) { entry in
                TimeOffCard(entry: entry)
                    .padding(.horizontal)
            }
            
            // Shifts
            ForEach(dayData.shifts) { shift in
                ShiftCard(shift: shift)
                    .padding(.horizontal)
            }
            
            // Empty state for the day
            if dayData.shifts.isEmpty && dayData.timeOff.isEmpty {
                HStack {
                    Text("No shifts scheduled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    ScheduleView()
}
