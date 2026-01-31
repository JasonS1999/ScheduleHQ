import SwiftUI

/// Banner shown when the device is offline
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
            
            Text("You're offline")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            Text("Changes will sync when connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.9))
        .foregroundColor(.white)
    }
}

/// Badge showing request status (pending, approved, denied)
struct StatusBadge: View {
    let status: TimeOffRequestStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.caption2)
            
            Text(status.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .denied: return .red
        }
    }
}

/// Badge for queued (offline) requests
struct QueuedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "icloud.slash")
                .font(.caption2)
            
            Text("Queued")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .foregroundColor(.gray)
        .cornerRadius(6)
    }
}

/// Loading overlay view
struct LoadingOverlay: View {
    let message: String
    
    init(_ message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
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
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if let action = action, let actionTitle = actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

/// Section header for dates in schedule
struct DateHeader: View {
    let date: Date
    let isToday: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Date box
            VStack(spacing: 2) {
                Text(date.dayAbbreviation)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isToday ? .white : .secondary)
                
                Text(date.dayNumber)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(isToday ? .white : .primary)
            }
            .frame(width: 50, height: 55)
            .background(isToday ? Color.blue : Color(.systemGray5))
            .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                if isToday {
                    Text("TODAY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
                
                Text(date.fullDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// Time off type pill/badge
struct TimeOffTypeBadge: View {
    let type: TimeOffType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.iconName)
                .font(.caption2)
            
            Text(type.shortLabel)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(typeColor.opacity(0.15))
        .foregroundColor(typeColor)
        .cornerRadius(6)
    }
    
    private var typeColor: Color {
        switch type {
        case .pto: return .purple
        case .vacation: return .blue
        case .sick: return .red
        case .dayOff: return .orange
        case .requestedOff: return .gray
        }
    }
}

/// Job code label pill
struct JobCodeBadge: View {
    let jobCode: String
    
    var body: some View {
        Text(jobCode)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }
}

// MARK: - Previews

#Preview("Status Badges") {
    VStack(spacing: 16) {
        StatusBadge(status: .pending)
        StatusBadge(status: .approved)
        StatusBadge(status: .denied)
        QueuedBadge()
    }
    .padding()
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "calendar.badge.exclamationmark",
        title: "No Shifts Scheduled",
        message: "You don't have any shifts scheduled for this week.",
        action: {},
        actionTitle: "Go to Current Week"
    )
}

#Preview("Date Header") {
    VStack {
        DateHeader(date: Date(), isToday: true)
        DateHeader(date: Date().nextWeekStart, isToday: false)
    }
    .padding()
}

#Preview("Offline Banner") {
    OfflineBanner()
}
