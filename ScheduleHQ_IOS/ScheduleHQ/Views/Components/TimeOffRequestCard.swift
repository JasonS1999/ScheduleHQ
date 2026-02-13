import SwiftUI

/// Card view for time off groups (single or multi-day)
struct TimeOffGroupCard: View {
    let group: TimeOffGroup
    var isQueued: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with type and status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: group.timeOffType.iconName)
                        .foregroundStyle(typeColor)

                    Text(group.timeOffType.displayName)
                        .font(.headline)
                }

                Spacer()

                if isQueued {
                    QueuedBadge()
                } else {
                    StatusBadge(status: group.status)
                }
            }

            // Date and day count
            if group.isMultiDay {
                HStack {
                    Label("\(group.formattedStartDate) - \(group.formattedEndDate)", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(group.dayCount) days")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            } else {
                let entry = group.primaryEntry
                HStack {
                    Label(entry.formattedDate, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if entry.hours > 0 {
                        Text("\(entry.hours) hours")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Time range for partial days
                if !entry.isAllDay, let start = entry.startTime, let end = entry.endTime {
                    HStack {
                        Label("\(start.formattedTime ?? start) - \(end.formattedTime ?? end)", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Notes if present
            if let notes = group.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Denial reason if denied
            if group.status == .denied, let reason = group.denialReason, !reason.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.caption)

                    Text("Denied: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.top, 4)
            }

            // Footer with request date
            if let requestedAt = group.formattedRequestedAt {
                HStack {
                    Text("Requested \(requestedAt)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if group.autoApproved {
                        Text("• Auto-approved")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private var typeColor: Color {
        switch group.timeOffType {
        case .pto: return .purple
        case .vacation: return .blue
        case .requested: return .orange
        }
    }
}

/// Legacy card that wraps a single entry in a group
struct TimeOffEntryCard: View {
    let entry: TimeOffEntry
    var isQueued: Bool = false

    var body: some View {
        TimeOffGroupCard(
            group: TimeOffGroup(entries: [entry]),
            isQueued: isQueued
        )
    }
}

// Keep old name for backwards compatibility
typealias TimeOffRequestCard = TimeOffEntryCard

#Preview {
    VStack {
        TimeOffEntryCard(entry: TimeOffEntry(
            employeeId: 1,
            employeeEmail: "test@example.com",
            employeeName: "John Doe",
            date: Date(),
            timeOffType: .pto,
            hours: 8,
            status: .pending,
            requestedAt: Date()
        ))

        TimeOffGroupCard(group: TimeOffGroup(entries: [
            TimeOffEntry(
                employeeId: 1, date: Date(),
                timeOffType: .vacation, hours: 8,
                vacationGroupId: "vac1", status: .approved,
                autoApproved: true, requestedAt: Date()
            ),
            TimeOffEntry(
                employeeId: 1,
                date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                timeOffType: .vacation, hours: 8,
                vacationGroupId: "vac1", status: .approved,
                autoApproved: true, requestedAt: Date()
            ),
            TimeOffEntry(
                employeeId: 1,
                date: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
                timeOffType: .vacation, hours: 8,
                vacationGroupId: "vac1", status: .approved,
                autoApproved: true, requestedAt: Date()
            )
        ]))

        TimeOffEntryCard(entry: TimeOffEntry(
            employeeId: 1,
            employeeEmail: "test@example.com",
            employeeName: "John Doe",
            date: Date(),
            timeOffType: .requested,
            hours: 4,
            isAllDay: false,
            startTime: "09:00",
            endTime: "13:00",
            status: .denied,
            requestedAt: Date(),
            denialReason: "Too many employees already off"
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
