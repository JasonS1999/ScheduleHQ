import SwiftUI

/// Time off view with requests and upcoming time off
struct TimeOffView: View {
    @State private var selectedTab = 0
    @State private var showNewRequestSheet = false
    @State private var entryToEdit: TimeOffEntry?
    @State private var entryToDelete: TimeOffEntry?
    @State private var showDeleteConfirmation = false
    
    @ObservedObject private var timeOffManager = TimeOffManager.shared
    @ObservedObject private var offlineQueueManager = OfflineQueueManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                AppBackgroundGradient()
                    .ignoresSafeArea()
                
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
            .sheet(item: $entryToEdit) { entry in
                TimeOffRequestSheet(editingEntry: entry)
            }
            .alert("Delete Request?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        deleteEntry(entry)
                    }
                }
            } message: {
                if let entry = entryToDelete {
                    Text("Delete your \(entry.timeOffType.displayName) request for \(entry.formattedDate)?")
                }
            }
        }
    }
    
    // MARK: - Requests List
    
    private var requestsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Queued entries section (offline)
                if offlineQueueManager.hasQueuedRequests {
                    Section {
                        ForEach(offlineQueueManager.queuedRequests) { entry in
                            TimeOffEntryCard(entry: entry, isQueued: true)
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
                        ForEach(timeOffManager.pendingRequests) { entry in
                            SwipeableTimeOffCard(
                                entry: entry,
                                canEdit: true,
                                canDelete: true,
                                onEdit: { entryToEdit = entry },
                                onDelete: {
                                    entryToDelete = entry
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    } header: {
                        sectionHeader("Pending", count: timeOffManager.pendingRequests.count)
                    }
                }
                
                // Approved requests
                if !timeOffManager.approvedRequests.isEmpty {
                    Section {
                        ForEach(timeOffManager.approvedRequests) { entry in
                            SwipeableTimeOffCard(
                                entry: entry,
                                canEdit: false,
                                canDelete: false,
                                onEdit: { },
                                onDelete: { }
                            )
                        }
                    } header: {
                        sectionHeader("Approved", count: timeOffManager.approvedRequests.count)
                    }
                }
                
                // Denied requests
                if !timeOffManager.deniedRequests.isEmpty {
                    Section {
                        ForEach(timeOffManager.deniedRequests) { entry in
                            SwipeableTimeOffCard(
                                entry: entry,
                                canEdit: false,
                                canDelete: true,
                                onEdit: { },
                                onDelete: {
                                    entryToDelete = entry
                                    showDeleteConfirmation = true
                                }
                            )
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
    
    private func deleteEntry(_ entry: TimeOffEntry) {
        Task {
            try? await timeOffManager.deleteTimeOff(entry)
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

// MARK: - Swipeable Time Off Card

struct SwipeableTimeOffCard: View {
    let entry: TimeOffEntry
    let canEdit: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    
    private let buttonWidth: CGFloat = 70
    private var totalButtonWidth: CGFloat {
        var width: CGFloat = 0
        if canEdit { width += buttonWidth }
        if canDelete { width += buttonWidth }
        return width
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Action buttons (revealed on swipe)
            HStack(spacing: 0) {
                if canEdit {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            offset = 0
                            isSwiped = false
                        }
                        onEdit()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.title2)
                            Text("Edit")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: buttonWidth, height: 80)
                        .background(Color.blue)
                    }
                }
                
                if canDelete {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            offset = 0
                            isSwiped = false
                        }
                        onDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.title2)
                            Text("Delete")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: buttonWidth, height: 80)
                        .background(Color.red)
                    }
                }
            }
            .cornerRadius(12)
            
            // Main card content
            TimeOffEntryCard(entry: entry)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if totalButtonWidth > 0 {
                                let dragAmount = value.translation.width
                                if dragAmount < 0 {
                                    // Swiping left (revealing buttons)
                                    offset = max(dragAmount, -totalButtonWidth - 20)
                                } else if isSwiped {
                                    // Swiping right (hiding buttons)
                                    offset = min(-totalButtonWidth + dragAmount, 0)
                                }
                            }
                        }
                        .onEnded { value in
                            if totalButtonWidth > 0 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if value.translation.width < -50 {
                                        offset = -totalButtonWidth
                                        isSwiped = true
                                    } else {
                                        offset = 0
                                        isSwiped = false
                                    }
                                }
                            }
                        }
                )
                .onTapGesture {
                    if isSwiped {
                        withAnimation(.spring(response: 0.3)) {
                            offset = 0
                            isSwiped = false
                        }
                    }
                }
        }
    }
}

#Preview {
    TimeOffView()
}
