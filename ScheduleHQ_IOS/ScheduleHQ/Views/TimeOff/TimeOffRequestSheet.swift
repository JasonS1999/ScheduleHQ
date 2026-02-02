import SwiftUI

/// Sheet for creating or editing time off requests
struct TimeOffRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    // Editing mode
    let editingEntry: TimeOffEntry?
    var isEditing: Bool { editingEntry != nil }
    
    @State private var requestType: TimeOffType = .dayOff
    @State private var selectedDate = Date()
    @State private var endDate = Date()
    @State private var ptoHours: Int = 9
    @State private var notes = ""
    @State private var isSubmitting = false
    
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var offlineQueueManager = OfflineQueueManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var timeOffManager = TimeOffManager.shared
    
    // Supported request types for employees - Day Off first
    private let availableTypes: [TimeOffType] = [.dayOff, .pto, .vacation]
    
    init(editingEntry: TimeOffEntry? = nil) {
        self.editingEntry = editingEntry
    }
    
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
                
                // Hours - only show for PTO (editable)
                if requestType == .pto {
                    Section {
                        Stepper(value: $ptoHours, in: 1...12) {
                            HStack {
                                Text("Hours")
                                Spacer()
                                Text("\(ptoHours)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    } footer: {
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
            .navigationTitle(isEditing ? "Edit Request" : "New Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Submit") {
                        if isEditing {
                            updateRequest()
                        } else {
                            submitRequest()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .onAppear {
                // Populate fields if editing
                if let entry = editingEntry {
                    requestType = entry.timeOffType
                    selectedDate = entry.date
                    endDate = entry.date
                    ptoHours = entry.hours > 0 ? entry.hours : 9
                    notes = entry.notes ?? ""
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
        switch requestType {
        case .pto:
            return ptoHours
        case .vacation:
            // Calculate days between dates, 8 hours per day
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: selectedDate, to: endDate)
            let days = (components.day ?? 0) + 1
            return days * 8
        case .dayOff:
            // Day off doesn't track hours
            return 0
        default:
            return 8
        }
    }
    
    // MARK: - Submit
    
    private func submitRequest() {
        guard let employee = authManager.employee,
              let employeeId = employee.id ?? authManager.employeeLocalId else { return }
        
        isSubmitting = true
        
        Task {
            await offlineQueueManager.submitOrQueue(
                employeeId: employeeId,
                employeeEmail: employee.email ?? "",
                employeeName: employee.name,
                date: selectedDate,
                timeOffType: requestType,
                hours: calculatedHours,
                isAllDay: true,
                startTime: nil,
                endTime: nil,
                vacationGroupId: requestType == .vacation ? UUID().uuidString : nil,
                notes: notes.isEmpty ? nil : notes
            )
            
            await MainActor.run {
                isSubmitting = false
                dismiss()
            }
        }
    }
    
    // MARK: - Update
    
    private func updateRequest() {
        guard let entry = editingEntry else { return }
        
        isSubmitting = true
        
        Task {
            do {
                try await timeOffManager.updateTimeOff(
                    entry,
                    newDate: selectedDate,
                    newType: requestType,
                    newHours: calculatedHours,
                    newNotes: notes.isEmpty ? nil : notes
                )
            } catch {
                print("Failed to update request: \(error)")
            }
            
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
