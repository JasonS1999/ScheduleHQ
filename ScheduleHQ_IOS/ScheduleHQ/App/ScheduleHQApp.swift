import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct ScheduleHQApp: App {
    // Initialize Firebase
    init() {
        FirebaseApp.configure()
        
        // Enable Firestore offline persistence
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024 as NSNumber) // 100 MB cache
        Firestore.firestore().settings = settings
    }
    
    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .withAlertManager(AlertManager.shared)
        }
    }
}

/// Root view that handles authentication state
struct AuthGateView: View {
    private let authManager = AuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    
    var body: some View {
        Group {
            if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isLoading)
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}

/// Loading view shown while checking auth state
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("ScheduleHQ")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 10)
        }
    }
}

#Preview {
    AuthGateView()
}
