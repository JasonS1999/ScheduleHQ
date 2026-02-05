import SwiftUI
import PhotosUI

/// Profile view showing employee information and settings
struct ProfileView: View {
    @State private var showSignOutConfirmation = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var timeOffManager = TimeOffManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    
    private let alertManager = AlertManager.shared
    private let profileImageService = ProfileImageService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                AppBackgroundGradient()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Profile header
                        profileHeader
                        
                        // Vacation balance card
                        if let employee = authManager.employee {
                            VacationBalanceCard(employee: employee)
                        }
                        
                        // PTO summary card
                        if let summary = timeOffManager.currentTrimesterSummary {
                            PTOSummaryCard(summary: summary)
                        }
                        
                        // Sign out button
                        signOutSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog(
                "Sign Out",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .refreshable {
                await authManager.refreshEmployeeData()
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar with photo picker
            if let employee = authManager.employee {
                ZStack {
                    EmployeeAvatarView(employee: employee, size: 100)
                    
                    // Upload progress overlay
                    if isUploadingPhoto {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 100, height: 100)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Camera button overlay
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .disabled(!networkMonitor.isConnected || isUploadingPhoto)
                    .opacity(networkMonitor.isConnected && !isUploadingPhoto ? 1 : 0.5)
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    if let newItem = newItem {
                        Task {
                            await handlePhotoSelection(newItem)
                        }
                    }
                }
                
                // Offline indicator for photo upload
                if !networkMonitor.isConnected {
                    Text("Go online to change photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Name and job code
                VStack(spacing: 8) {
                    Text(employee.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !employee.jobCode.isEmpty {
                        JobCodeBadge(jobCode: employee.jobCode)
                    }
                }
                
                // Email
                if let email = employee.email {
                    Label(email, systemImage: "envelope")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Debug info when employee not loaded
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Employee data not loaded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    if let appUser = authManager.appUser {
                        Text("User loaded: managerUid=\(appUser.managerUid), employeeId=\(appUser.employeeId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("AppUser not loaded")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if let uid = authManager.currentUser?.uid {
                        Text("Auth UID: \(uid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // MARK: - Photo Handling
    
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        // Clear selection to allow re-selecting same photo
        selectedPhotoItem = nil
        
        guard let managerUid = authManager.managerUid,
              let employeeId = authManager.appUser?.employeeId else {
            alertManager.showError(ProfileImageError.noEmployeeId)
            return
        }
        
        let employeeDocId = String(employeeId)
        isUploadingPhoto = true
        
        do {
            // Load image data from PhotosPickerItem
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw ProfileImageError.compressionFailed
            }
            
            // Upload the image
            _ = try await profileImageService.uploadProfileImage(image, for: employeeDocId, managerUid: managerUid)
            
            // Refresh employee data to get updated URL
            await authManager.refreshEmployeeData()
            
        } catch {
            alertManager.showError(error)
        }
        
        isUploadingPhoto = false
    }
    
    // MARK: - Sign Out Section
    
    private var signOutSection: some View {
        Button {
            showSignOutConfirmation = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions
    
    private func signOut() {
        try? authManager.signOut()
    }
}

// MARK: - Vacation Balance Card

struct VacationBalanceCard: View {
    let employee: Employee
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
                Text("Vacation Balance")
                    .fontWeight(.semibold)
            }
            
            // Stats
            HStack {
                VStack(spacing: 4) {
                    Text("\(employee.vacationWeeksUsed)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("Used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text("\(employee.vacationWeeksRemaining)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - PTO Summary Card

struct PTOSummaryCard: View {
    let summary: TrimesterSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(.purple)
                Text("PTO - \(summary.label)")
                    .fontWeight(.semibold)
                
                Spacer()
                
                if summary.isCurrent {
                    Text("Current")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                }
            }
            
            // Date range
            Text(summary.formattedDateRange)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Stats - Used, Remaining, and Available
            HStack {
                VStack(spacing: 4) {
                    Text("\(summary.used)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("Used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text("\(summary.remaining)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.purple)
                    Text("Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text("\(summary.available)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary.opacity(0.7))
                    Text("Total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Progress bar showing usage
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.purple)
                        .frame(width: geometry.size.width * summary.usageProgress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ProfileView()
}
