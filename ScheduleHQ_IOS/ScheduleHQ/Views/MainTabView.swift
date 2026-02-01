import SwiftUI

/// Modern main tab navigation view with Schedule, Time Off, and Profile tabs
struct MainTabView: View {
    @State private var selectedTab = 0
    
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var offlineQueueManager = OfflineQueueManager.shared
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @ObservedObject private var timeOffManager = TimeOffManager.shared
    
    @Environment(\.colorScheme) private var colorScheme
    
    init() {
        // Configure tab bar appearance for modern look
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // Use blur effect for the tab bar
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        
        // Configure item appearance
        let itemAppearance = UITabBarItemAppearance()
        
        // Normal state
        itemAppearance.normal.iconColor = UIColor.secondaryLabel
        itemAppearance.normal.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        
        // Selected state - use a vibrant purple/indigo
        let selectedColor = UIColor(Color(hex: "6366F1"))
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                ScheduleView()
                    .tabItem {
                        Label("Schedule", systemImage: selectedTab == 0 ? "calendar.circle.fill" : "calendar.circle")
                    }
                    .tag(0)
                
                TimeOffView()
                    .tabItem {
                        Label("Time Off", systemImage: selectedTab == 1 ? "clock.badge.checkmark.fill" : "clock.badge.checkmark")
                    }
                    .badge(offlineQueueManager.queuedCount > 0 ? offlineQueueManager.queuedCount : 0)
                    .tag(1)
                
                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: selectedTab == 2 ? "person.crop.circle.fill" : "person.crop.circle")
                    }
                    .tag(2)
            }
            .tint(Color(hex: "6366F1"))
            
            // Offline banner overlay
            if !networkMonitor.isConnected {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: networkMonitor.isConnected)
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

#Preview("Dark Mode") {
    MainTabView()
        .preferredColorScheme(.dark)
}
