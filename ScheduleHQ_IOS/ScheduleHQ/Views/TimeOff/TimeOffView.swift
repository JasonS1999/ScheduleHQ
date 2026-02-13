import SwiftUI

/// Time off view with requests and upcoming time off
struct TimeOffView: View {
    @State private var selectedTab = 0
    @State private var showNewRequestSheet = false
    @State private var entryToEdit: TimeOffEntry?
    @State private var groupToDelete: TimeOffGroup?
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
                    if let group = groupToDelete {
                        deleteGroup(group)
                    }
                }
            } message: {
                if let group = groupToDelete {
                    if group.isMultiDay {
                        Text("Delete your \(group.timeOffType.displayName) request for \(group.formattedStartDate) - \(group.formattedEndDate) (\(group.dayCount) days)?")
                    } else {
                        Text("Delete your \(group.timeOffType.displayName) request for \(group.formattedStartDate)?")
                    }
                }
            }
        }
    }

    // MARK: - Requests List

    private var requestsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Queued entries section (offline) - group these too
                if offlineQueueManager.hasQueuedRequests {
                    let queuedGroups = TimeOffGroup.grouped(from: offlineQueueManager.queuedRequests)
                    Section {
                        ForEach(queuedGroups) { group in
                            TimeOffGroupCard(group: group, isQueued: true)
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

                // Pending requests (grouped)
                if !timeOffManager.pendingGroups.isEmpty {
                    Section {
                        ForEach(timeOffManager.pendingGroups) { group in
                            SwipeableTimeOffGroupCard(
                                group: group,
                                canEdit: !group.isMultiDay,
                                canDelete: true,
                                onEdit: { entryToEdit = group.primaryEntry },
                                onDelete: {
                                    groupToDelete = group
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    } header: {
                        sectionHeader("Pending", count: timeOffManager.pendingGroups.count)
                    }
                }

                // Approved requests (grouped)
                if !timeOffManager.approvedGroups.isEmpty {
                    Section {
                        ForEach(timeOffManager.approvedGroups) { group in
                            TimeOffGroupCard(group: group)
                        }
                    } header: {
                        sectionHeader("Approved", count: timeOffManager.approvedGroups.count)
                    }
                }

                // Denied requests (grouped)
                if !timeOffManager.deniedGroups.isEmpty {
                    Section {
                        ForEach(timeOffManager.deniedGroups) { group in
                            SwipeableTimeOffGroupCard(
                                group: group,
                                canEdit: false,
                                canDelete: true,
                                onEdit: { },
                                onDelete: {
                                    groupToDelete = group
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    } header: {
                        sectionHeader("Denied", count: timeOffManager.deniedGroups.count)
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
                if timeOffManager.upcomingGroups.isEmpty {
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
                    ForEach(timeOffManager.upcomingGroups) { group in
                        UpcomingTimeOffGroupCard(group: group)
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

    private func deleteGroup(_ group: TimeOffGroup) {
        Task {
            // Delete all entries in the group
            for entry in group.entries {
                do {
                    try await timeOffManager.deleteTimeOff(entry)
                } catch {
                    print("Failed to delete entry \(entry.documentId ?? "unknown"): \(error)")
                }
            }
        }
    }
}

/// Card for upcoming approved time off (grouped)
struct UpcomingTimeOffGroupCard: View {
    let group: TimeOffGroup

    var body: some View {
        HStack(spacing: 16) {
            // Date column
            VStack(spacing: 4) {
                Text(group.startDate.dayAbbreviation)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(group.startDate.dayNumber)
                    .font(.title)
                    .fontWeight(.bold)

                Text(group.startDate.monthDay.split(separator: " ").first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)

            // Details
            VStack(alignment: .leading, spacing: 8) {
                TimeOffTypeBadge(type: group.timeOffType)

                if group.isMultiDay {
                    Text("\(group.formattedStartDate) - \(group.formattedEndDate)")
                        .font(.subheadline)
                    Text("\(group.dayCount) days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let entry = group.primaryEntry
                    HStack {
                        Text("\(entry.hours) hours")
                            .font(.subheadline)

                        if !entry.isAllDay, let timeRange = entry.timeRangeDisplay {
                            Text("\u{2022}")
                                .foregroundStyle(.secondary)
                            Text(timeRange)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Days until
            if let daysUntil = daysUntilStart {
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

    private var daysUntilStart: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.startOfDay(for: group.startDate)
        let components = calendar.dateComponents([.day], from: today, to: startDate)
        return components.day
    }
}

// MARK: - Swipeable Time Off Group Card

struct SwipeableTimeOffGroupCard: View {
    let group: TimeOffGroup
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
            TimeOffGroupCard(group: group)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if totalButtonWidth > 0 {
                                let dragAmount = value.translation.width
                                if dragAmount < 0 {
                                    offset = max(dragAmount, -totalButtonWidth - 20)
                                } else if isSwiped {
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
