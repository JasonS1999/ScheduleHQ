import SwiftUI

/// Card view for time off requests
struct TimeOffRequestCard: View {
    let request: TimeOffRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with type and status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: request.timeOffType.iconName)
                        .foregroundStyle(typeColor)
                    
                    Text(request.timeOffType.displayName)
                        .font(.headline)
                }
                
                Spacer()
                
                if request.isQueued {
                    QueuedBadge()
                } else {
                    StatusBadge(status: request.status)
                }
            }
            
            // Date and hours
            HStack {
                Label(request.formattedDate, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(request.hours) hours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Time range for partial days
            if !request.isAllDay, let start = request.startTime, let end = request.endTime {
                HStack {
                    Label("\(start.formattedTime ?? start) - \(end.formattedTime ?? end)", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Notes if present
            if let notes = request.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // Denial reason if denied
            if request.status == .denied, let reason = request.denialReason, !reason.isEmpty {
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
            HStack {
                Text("Requested \(request.formattedRequestedAt)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                if request.autoApproved {
                    Text("• Auto-approved")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
    
    private var typeColor: Color {
        switch request.timeOffType {
        case .pto: return .purple
        case .vacation: return .blue
        case .sick: return .red
        case .dayOff: return .orange
        case .requestedOff: return .gray
        }
    }
}

#Preview {
    VStack {
        TimeOffRequestCard(request: TimeOffRequest(
            employeeId: 1,
            employeeEmail: "test@example.com",
            employeeName: "John Doe",
            date: Date(),
            timeOffType: .pto,
            hours: 8,
            status: .pending
        ))
        
        TimeOffRequestCard(request: TimeOffRequest(
            employeeId: 1,
            employeeEmail: "test@example.com",
            employeeName: "John Doe",
            date: Date(),
            timeOffType: .vacation,
            hours: 8,
            status: .approved,
            autoApproved: true
        ))
        
        TimeOffRequestCard(request: TimeOffRequest(
            employeeId: 1,
            employeeEmail: "test@example.com",
            employeeName: "John Doe",
            date: Date(),
            timeOffType: .dayOff,
            hours: 4,
            isAllDay: false,
            startTime: "09:00",
            endTime: "13:00",
            status: .denied,
            denialReason: "Too many employees already off"
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
