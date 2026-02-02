import SwiftUI

/// Design system for ScheduleHQ - Modern UI with light/dark mode support
struct AppTheme {
    
    // MARK: - Colors
    
    struct Colors {
        // Primary brand colors
        static let primary = Color("AccentColor", bundle: nil) // Falls back to system blue
        static let primaryGradientStart = Color(hex: "4F46E5") // Indigo
        static let primaryGradientEnd = Color(hex: "7C3AED") // Purple
        
        // Semantic colors
        static let success = Color(hex: "10B981")
        static let warning = Color(hex: "F59E0B")
        static let error = Color(hex: "EF4444")
        static let info = Color(hex: "3B82F6")
        
        // Shift type colors
        static let shiftMorning = Color(hex: "F59E0B") // Warm orange/yellow for morning
        static let shiftDay = Color(hex: "3B82F6") // Blue for day shifts
        static let shiftEvening = Color(hex: "8B5CF6") // Purple for evening
        static let shiftNight = Color(hex: "6366F1") // Indigo for night
        static let shiftOff = Color(hex: "6B7280") // Gray for off days
        
        // Time off type colors
        static let pto = Color(hex: "8B5CF6")
        static let vacation = Color(hex: "06B6D4")
        static let sick = Color(hex: "EF4444")
        static let dayOff = Color(hex: "F97316")
        static let requestedOff = Color(hex: "6B7280")
        
        // Background colors (adapts to light/dark)
        static let backgroundPrimary = Color(uiColor: .systemBackground)
        static let backgroundSecondary = Color(uiColor: .secondarySystemBackground)
        static let backgroundTertiary = Color(uiColor: .tertiarySystemBackground)
        static let backgroundGrouped = Color(uiColor: .systemGroupedBackground)
        
        // Card backgrounds
        static let cardBackground = Color(uiColor: .systemBackground)
        static let cardBackgroundElevated = Color(uiColor: .secondarySystemBackground)
        
        // Text colors
        static let textPrimary = Color(uiColor: .label)
        static let textSecondary = Color(uiColor: .secondaryLabel)
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        
        // Border & Separator
        static let border = Color(uiColor: .separator)
        static let borderLight = Color(uiColor: .separator).opacity(0.5)
    }
    
    // MARK: - Gradients
    
    struct Gradients {
        static let primary = LinearGradient(
            colors: [Colors.primaryGradientStart, Colors.primaryGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let morning = LinearGradient(
            colors: [Color(hex: "FCD34D"), Color(hex: "F59E0B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let day = LinearGradient(
            colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let evening = LinearGradient(
            colors: [Color(hex: "A78BFA"), Color(hex: "8B5CF6")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let night = LinearGradient(
            colors: [Color(hex: "818CF8"), Color(hex: "6366F1")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let off = LinearGradient(
            colors: [Color(hex: "9CA3AF"), Color(hex: "6B7280")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let today = LinearGradient(
            colors: [Color(hex: "4F46E5"), Color(hex: "7C3AED")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Background gradients for lighter appearance
        static let backgroundDark = LinearGradient(
            colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f0f23")],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let backgroundLight = LinearGradient(
            colors: [Color(hex: "f8fafc"), Color(hex: "e2e8f0")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        static let card = (color: Color.black.opacity(0.08), radius: 8.0, x: 0.0, y: 2.0)
        static let cardHover = (color: Color.black.opacity(0.12), radius: 12.0, x: 0.0, y: 4.0)
        static let button = (color: Color.black.opacity(0.15), radius: 4.0, x: 0.0, y: 2.0)
        static let elevated = (color: Color.black.opacity(0.2), radius: 16.0, x: 0.0, y: 8.0)
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    struct Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let extraLarge: CGFloat = 20
        static let pill: CGFloat = 100
    }
    
    // MARK: - Typography
    
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .medium, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Background Gradient

/// Reusable gradient background for all tabs
struct AppBackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if colorScheme == .dark {
                // Darker navy/purple gradient for dark mode
                LinearGradient(
                    colors: [
                        Color(hex: "1e1b4b"), // Deep indigo
                        Color(hex: "1e1b4b").opacity(0.9),
                        Color(hex: "0f172a")  // Dark slate
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Soft light gradient for light mode
                LinearGradient(
                    colors: [
                        Color(hex: "f8fafc"),
                        Color(hex: "e0e7ff").opacity(0.5),
                        Color(hex: "f1f5f9")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

// MARK: - Shift Time Classification

enum ShiftTimeType {
    case morning  // Before 11 AM
    case day      // 11 AM - 3 PM
    case evening  // 3 PM - 8 PM
    case night    // After 8 PM
    case off
    
    var label: String {
        switch self {
        case .morning: return "Morning"
        case .day: return "Day"
        case .evening: return "Evening"
        case .night: return "Night"
        case .off: return "Off"
        }
    }
    
    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        case .off: return "moon.zzz.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .morning: return AppTheme.Colors.shiftMorning
        case .day: return AppTheme.Colors.shiftDay
        case .evening: return AppTheme.Colors.shiftEvening
        case .night: return AppTheme.Colors.shiftNight
        case .off: return AppTheme.Colors.shiftOff
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .morning: return AppTheme.Gradients.morning
        case .day: return AppTheme.Gradients.day
        case .evening: return AppTheme.Gradients.evening
        case .night: return AppTheme.Gradients.night
        case .off: return AppTheme.Gradients.off
        }
    }
}

// MARK: - Shift Extension

extension Shift {
    /// Determine the shift time type based on start time
    var shiftTimeType: ShiftTimeType {
        if isOff { return .off }
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: startTime)
        
        if hour < 11 {
            return .morning
        } else if hour < 15 {
            return .day
        } else if hour < 20 {
            return .evening
        } else {
            return .night
        }
    }
    
    /// Get the display label - only uses actual label from DB (like "Runner", "Daily Notes", "Shift Notes")
    var displayLabel: String? {
        if isOff { return "Off" }
        
        // Only return the label if it exists in the database
        if let label = label, !label.isEmpty, label.uppercased() != "OFF" {
            return label
        }
        
        // No fallback to time-based labels - return nil if no custom label
        return nil
    }
    
    /// Check if this shift has a custom role/position label
    var hasCustomLabel: Bool {
        guard let label = label else { return false }
        return !label.isEmpty && label.uppercased() != "OFF"
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    let elevated: Bool
    
    func body(content: Content) -> some View {
        content
            .background(elevated ? AppTheme.Colors.cardBackgroundElevated : AppTheme.Colors.cardBackground)
            .cornerRadius(AppTheme.Radius.large)
            .shadow(
                color: AppTheme.Shadows.card.color,
                radius: AppTheme.Shadows.card.radius,
                x: AppTheme.Shadows.card.x,
                y: AppTheme.Shadows.card.y
            )
    }
}

struct GlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(AppTheme.Radius.large)
    }
}

extension View {
    func cardStyle(elevated: Bool = false) -> some View {
        modifier(CardStyle(elevated: elevated))
    }
    
    func glassStyle() -> some View {
        modifier(GlassStyle())
    }
}

// MARK: - Preview

#Preview("Theme Colors") {
    ScrollView {
        VStack(spacing: 20) {
            // Primary gradient
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.Gradients.primary)
                .frame(height: 60)
                .overlay {
                    Text("Primary Gradient")
                        .foregroundStyle(.white)
                        .font(AppTheme.Typography.headline)
                }
            
            // Shift type colors
            HStack(spacing: 12) {
                ForEach([ShiftTimeType.morning, .day, .evening, .night, .off], id: \.label) { type in
                    VStack {
                        Circle()
                            .fill(type.gradient)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: type.icon)
                                    .foregroundStyle(.white)
                            }
                        Text(type.label)
                            .font(.caption)
                    }
                }
            }
            
            // Card example
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Example")
                    .font(AppTheme.Typography.headline)
                Text("This is a card with proper styling")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.lg)
            .cardStyle()
        }
        .padding()
    }
}
