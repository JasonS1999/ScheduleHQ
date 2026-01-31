import SwiftUI

/// Time off view with requests and upcoming time off
struct TimeOffView: View {
    @State private var selectedTab = 0
    @State private var showNewRequestSheet = false
    
    @ObservedObject private var timeOffManager = TimeOffManager.shared
    @ObservedObject private var offlineQueueManager = OfflineQueueManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("View", selection: $selectedTab) {
                    Text("My Requests").tag(0)
                    Text("Upcoming").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                Group {
                    if selectedTab == 0 {
                        requestsListView
                    } else {
                        upcomingListView
                    }
                }
            }
            .navigationTitle("Time Off")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewRequestSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewRequestSheet) {
                TimeOffRequestSheet()
            }
        }
    }
    
    // MARK: - Requests List
    
    private var requestsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Queued requests section (offline)
                if offlineQueueManager.hasQueuedRequests {
                    Section {
                        ForEach(offlineQueueManager.queuedRequests) { request in
                            TimeOffRequestCard(request: request)
                        }
                    } header: {
                        HStack {
                            Image(systemName: "icloud.slash")
                            Text("Pending Sync")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(offlineQueueManager.queuedCount)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
                
                // Pending requests
                if !timeOffManager.pendingRequests.isEmpty {
                    Section {
                        ForEach(timeOffManager.pendingRequests) { request in
                            TimeOffRequestCard(request: request)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteRequest(request)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("Pending", count: timeOffManager.pendingRequests.count)
                    }
                }
                
                // Approved requests
                if !timeOffManager.approvedRequests.isEmpty {
                    Section {
                        ForEach(timeOffManager.approvedRequests) { request in
                            TimeOffRequestCard(request: request)
                        }
                    } header: {
                        sectionHeader("Approved", count: timeOffManager.approvedRequests.count)
                    }
                }
                
                // Denied requests
                if !timeOffManager.deniedRequests.isEmpty {
                    Section {
                        ForEach(timeOffManager.deniedRequests) { request in
                            TimeOffRequestCard(request: request)
                        }
                    } header: {
                        sectionHeader("Denied", count: timeOffManager.deniedRequests.count)
                    }
                }
                
                // Empty state
                if timeOffManager.requests.isEmpty && !offlineQueueManager.hasQueuedRequests {
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: "No Requests",
                        message: "You haven't submitted any time off requests yet.",
                        action: { showNewRequestSheet = true },
                        actionTitle: "New Request"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Upcoming List
    
    private var upcomingListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if timeOffManager.upcomingTimeOff.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.clock",
                        title: "No Upcoming Time Off",
                        message: "You don't have any approved time off coming up.",
                        action: { showNewRequestSheet = true },
                        actionTitle: "Request Time Off"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(timeOffManager.upcomingTimeOff) { entry in
                        UpcomingTimeOffCard(entry: entry)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
    
    private func deleteRequest(_ request: TimeOffRequest) {
        Task {
            try? await timeOffManager.deleteRequest(request)
        }
    }
}

/// Card for upcoming approved time off
struct UpcomingTimeOffCard: View {
    let entry: TimeOffEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Date column
            VStack(spacing: 4) {
                Text(entry.date.dayAbbreviation)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Text(entry.date.dayNumber)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(entry.date.monthDay.split(separator: " ").first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                TimeOffTypeBadge(type: entry.timeOffType)
                
                HStack {
                    Text("\(entry.hours) hours")
                        .font(.subheadline)
                    
                    if !entry.isAllDay, let timeRange = entry.timeRangeDisplay {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(timeRange)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Days until
            if let daysUntil = daysUntilEntry {
                VStack {
                    Text("\(daysUntil)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text(daysUntil == 1 ? "day" : "days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
    
    private var daysUntilEntry: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entryDate = calendar.startOfDay(for: entry.date)
        let components = calendar.dateComponents([.day], from: today, to: entryDate)
        return components.day
    }
}

#Preview {
    TimeOffView()
}
