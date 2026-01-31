import SwiftUI

/// Sheet for creating new time off requests
struct TimeOffRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var requestType: TimeOffType = .pto
    @State private var selectedDate = Date()
    @State private var endDate = Date()
    @State private var isAllDay = true
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    @State private var notes = ""
    @State private var isSubmitting = false
    
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var offlineQueueManager = OfflineQueueManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    
    // Supported request types for employees
    private let availableTypes: [TimeOffType] = [.pto, .vacation, .dayOff]
    
    var body: some View {
        NavigationStack {
            Form {
                // Request type
                Section("Type") {
                    Picker("Request Type", selection: $requestType) {
                        ForEach(availableTypes, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Date selection
                Section("Date") {
                    if requestType == .vacation {
                        DatePicker("Start Date", selection: $selectedDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, in: selectedDate..., displayedComponents: .date)
                    } else {
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    }
                }
                
                // Time selection (for partial days)
                Section("Time") {
                    Toggle("All Day", isOn: $isAllDay)
                    
                    if !isAllDay {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
                
                // Hours summary
                Section {
                    HStack {
                        Text("Hours")
                        Spacer()
                        Text("\(calculatedHours)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                } footer: {
                    if requestType == .pto {
                        if let summary = TimeOffManager.shared.currentTrimesterSummary {
                            Text("PTO remaining this trimester: \(summary.remaining) hours")
                        }
                    }
                }
                
                // Notes
                Section("Notes (Optional)") {
                    TextField("Add any notes for your manager...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Offline indicator
                if !networkMonitor.isConnected {
                    Section {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundStyle(.orange)
                            Text("You're offline. This request will be queued and submitted when you're back online.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitRequest()
                    }
                    .disabled(isSubmitting || calculatedHours <= 0)
                }
            }
            .overlay {
                if isSubmitting {
                    LoadingOverlay("Submitting...")
                }
            }
        }
    }
    
    // MARK: - Calculated Hours
    
    private var calculatedHours: Int {
        if isAllDay {
            if requestType == .vacation {
                // Calculate days between dates
                let calendar = Calendar.current
                let components = calendar.dateComponents([.day], from: selectedDate, to: endDate)
                let days = (components.day ?? 0) + 1
                return days * 8
            }
            return 8
        } else {
            // Calculate hours from time range
            let interval = endTime.timeIntervalSince(startTime)
            let hours = max(0, Int(interval / 3600))
            return hours
        }
    }
    
    // MARK: - Submit
    
    private func submitRequest() {
        guard let employee = authManager.employee else { return }
        
        isSubmitting = true
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        Task {
            await offlineQueueManager.submitOrQueue(
                employeeId: employee.id,
                employeeEmail: employee.email ?? "",
                employeeName: employee.name,
                date: selectedDate,
                timeOffType: requestType,
                hours: calculatedHours,
                isAllDay: isAllDay,
                startTime: isAllDay ? nil : timeFormatter.string(from: startTime),
                endTime: isAllDay ? nil : timeFormatter.string(from: endTime),
                vacationGroupId: requestType == .vacation ? UUID().uuidString : nil,
                notes: notes.isEmpty ? nil : notes
            )
            
            await MainActor.run {
                isSubmitting = false
                dismiss()
            }
        }
    }
}

#Preview {
    TimeOffRequestSheet()
}
