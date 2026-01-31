import SwiftUI

/// Card view displaying a shift's details
struct ShiftCard: View {
    let shift: Shift
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time row
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
                
                Text(shift.formattedTimeRange)
                    .font(.headline)
                
                Spacer()
                
                Text(shift.formattedDuration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Label and notes
            if let label = shift.label, !label.isEmpty {
                HStack {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    JobCodeBadge(jobCode: label)
                }
            }
            
            if let notes = shift.notes, !notes.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

/// Card view for time off entries
struct TimeOffCard: View {
    let entry: TimeOffEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Type indicator
            Image(systemName: entry.timeOffType.iconName)
                .font(.title2)
                .foregroundStyle(typeColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TimeOffTypeBadge(type: entry.timeOffType)
                    
                    Spacer()
                    
                    Text("\(entry.hours) hrs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if !entry.isAllDay, let timeRange = entry.timeRangeDisplay {
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(typeColor.opacity(0.08))
        .cornerRadius(12)
    }
    
    private var typeColor: Color {
        switch entry.timeOffType {
        case .pto: return .purple
        case .vacation: return .blue
        case .sick: return .red
        case .dayOff: return .orange
        case .requestedOff: return .gray
        }
    }
}

// MARK: - Previews

#Preview("Shift Card") {
    VStack {
        ShiftCard(shift: Shift(
            employeeId: 1,
            startTime: Date(),
            endTime: Date().addingTimeInterval(8 * 3600),
            label: "Front Desk",
            notes: "Remember to check the inventory"
        ))
        
        ShiftCard(shift: Shift(
            employeeId: 1,
            startTime: Date(),
            endTime: Date().addingTimeInterval(4 * 3600)
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Time Off Card") {
    VStack {
        TimeOffCard(entry: TimeOffEntry(
            employeeId: 1,
            date: Date(),
            timeOffType: .pto,
            hours: 8
        ))
        
        TimeOffCard(entry: TimeOffEntry(
            employeeId: 1,
            date: Date(),
            timeOffType: .vacation,
            hours: 8
        ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
