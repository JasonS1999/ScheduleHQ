import SwiftUI

/// A reusable avatar view that displays an employee's profile image or falls back to their initial
struct EmployeeAvatarView: View {
    /// The URL of the profile image (optional)
    let imageURL: String?
    
    /// The initial to display as fallback (usually first letter of name)
    let initial: String
    
    /// The size of the avatar (width and height)
    let size: CGFloat
    
    /// The accent color for the fallback circle (defaults to blue)
    var accentColor: Color = .blue
    
    /// Whether to show a gradient on the fallback circle
    var showGradient: Bool = true
    
    var body: some View {
        if let urlString = imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    // Loading state
                    ZStack {
                        fallbackCircle
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(size > 60 ? 1.0 : 0.6)
                    }
                case .success(let image):
                    // Successfully loaded image
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure:
                    // Failed to load - show fallback
                    fallbackCircle
                @unknown default:
                    fallbackCircle
                }
            }
        } else {
            // No URL provided - show fallback
            fallbackCircle
        }
    }
    
    /// The fallback circle with initial
    private var fallbackCircle: some View {
        ZStack {
            if showGradient {
                Circle()
                    .fill(accentColor.gradient)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: size, height: size)
            }
            
            Text(initial)
                .font(.system(size: initialFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(showGradient ? .white : accentColor)
        }
        .frame(width: size, height: size)
    }
    
    /// Calculate appropriate font size based on avatar size
    private var initialFontSize: CGFloat {
        size * 0.4
    }
}

// MARK: - Convenience Initializers

extension EmployeeAvatarView {
    /// Initialize with an Employee object
    init(employee: Employee, size: CGFloat, accentColor: Color = .blue, showGradient: Bool = true) {
        self.imageURL = employee.profileImageURL
        self.initial = employee.initial
        self.size = size
        self.accentColor = accentColor
        self.showGradient = showGradient
    }
    
    /// Initialize with a name (extracts initial automatically)
    init(imageURL: String?, name: String, size: CGFloat, accentColor: Color = .blue, showGradient: Bool = true) {
        self.imageURL = imageURL
        self.initial = String(name.prefix(1)).uppercased()
        self.size = size
        self.accentColor = accentColor
        self.showGradient = showGradient
    }
}

// MARK: - Preview

#Preview("With Image URL") {
    EmployeeAvatarView(
        imageURL: "https://picsum.photos/200",
        initial: "J",
        size: 100
    )
}

#Preview("Without Image URL") {
    EmployeeAvatarView(
        imageURL: nil,
        initial: "J",
        size: 100
    )
}

#Preview("Small Size") {
    EmployeeAvatarView(
        imageURL: nil,
        initial: "A",
        size: 36,
        accentColor: .orange,
        showGradient: false
    )
}

#Preview("Various Sizes") {
    HStack(spacing: 16) {
        EmployeeAvatarView(imageURL: nil, initial: "S", size: 32)
        EmployeeAvatarView(imageURL: nil, initial: "M", size: 48)
        EmployeeAvatarView(imageURL: nil, initial: "L", size: 64)
        EmployeeAvatarView(imageURL: nil, initial: "X", size: 100)
    }
    .padding()
}
