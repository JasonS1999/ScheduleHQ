import SwiftUI

/// Main tab navigation view with Schedule, Time Off, and Profile tabs
struct MainTabView: View {
    @State private var selectedTab = 0
    
    private let networkMonitor = NetworkMonitor.shared
    private let offlineQueueManager = OfflineQueueManager.shared
    private let scheduleManager = ScheduleManager.shared
    private let timeOffManager = TimeOffManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                ScheduleView()
                    .tabItem {
                        Label("Schedule", systemImage: "calendar")
                    }
                    .tag(0)
                
                TimeOffView()
                    .tabItem {
                        Label("Time Off", systemImage: "calendar.badge.clock")
                    }
                    .badge(offlineQueueManager.queuedCount > 0 ? offlineQueueManager.queuedCount : 0)
                    .tag(1)
                
                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(2)
            }
            
            // Offline banner overlay
            if !networkMonitor.isConnected {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
        .onAppear {
            scheduleManager.startListening()
            timeOffManager.startListening()
        }
        .onDisappear {
            scheduleManager.stopListening()
            timeOffManager.stopListening()
        }
    }
}

#Preview {
    MainTabView()
}
