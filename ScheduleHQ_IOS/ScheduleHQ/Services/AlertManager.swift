import SwiftUI
import Combine

/// Centralized alert management for consistent error display across the app
final class AlertManager: ObservableObject {
    static let shared = AlertManager()
    
    /// Current alert to display (nil if no alert)
    @Published var currentAlert: AlertItem?
    
    /// Whether an alert is currently showing
    var isShowingAlert: Bool {
        currentAlert != nil
    }
    
    private init() {}
    
    /// Show an error alert with a title and message
    func showError(_ title: String, message: String) {
        currentAlert = AlertItem(
            title: title,
            message: message,
            type: .error
        )
    }
    
    /// Show an error from an Error object
    func showError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showError("Error", message: message)
    }
    
    /// Show a success alert
    func showSuccess(_ title: String, message: String) {
        currentAlert = AlertItem(
            title: title,
            message: message,
            type: .success
        )
    }
    
    /// Show an info alert
    func showInfo(_ title: String, message: String) {
        currentAlert = AlertItem(
            title: title,
            message: message,
            type: .info
        )
    }
    
    /// Show a warning alert
    func showWarning(_ title: String, message: String) {
        currentAlert = AlertItem(
            title: title,
            message: message,
            type: .warning
        )
    }
    
    /// Dismiss the current alert
    func dismiss() {
        currentAlert = nil
    }
}

/// Represents an alert to be displayed
struct AlertItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let type: AlertType
    var primaryButton: AlertButton?
    var secondaryButton: AlertButton?
    
    enum AlertType {
        case error
        case success
        case info
        case warning
        
        var iconName: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .error: return .red
            case .success: return .green
            case .info: return .blue
            case .warning: return .orange
            }
        }
    }
    
    struct AlertButton: Equatable {
        let title: String
        let role: ButtonRole?
        let action: () -> Void
        
        static func == (lhs: AlertButton, rhs: AlertButton) -> Bool {
            lhs.title == rhs.title && lhs.role == rhs.role
        }
    }
    
    init(
        title: String,
        message: String,
        type: AlertType,
        primaryButton: AlertButton? = nil,
        secondaryButton: AlertButton? = nil
    ) {
        self.title = title
        self.message = message
        self.type = type
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

/// View modifier for presenting alerts from AlertManager
struct AlertModifier: ViewModifier {
    @ObservedObject var alertManager: AlertManager
    
    func body(content: Content) -> some View {
        content
            .alert(
                alertManager.currentAlert?.title ?? "",
                isPresented: Binding(
                    get: { alertManager.isShowingAlert },
                    set: { if !$0 { alertManager.dismiss() } }
                )
            ) {
                if let primary = alertManager.currentAlert?.primaryButton {
                    Button(primary.title, role: primary.role) {
                        primary.action()
                        alertManager.dismiss()
                    }
                }
                if let secondary = alertManager.currentAlert?.secondaryButton {
                    Button(secondary.title, role: secondary.role) {
                        secondary.action()
                        alertManager.dismiss()
                    }
                }
                if alertManager.currentAlert?.primaryButton == nil {
                    Button("OK", role: .cancel) {
                        alertManager.dismiss()
                    }
                }
            } message: {
                if let message = alertManager.currentAlert?.message {
                    Text(message)
                }
            }
    }
}

extension View {
    /// Apply the alert manager modifier to handle app-wide alerts
    func withAlertManager(_ alertManager: AlertManager) -> some View {
        modifier(AlertModifier(alertManager: alertManager))
    }
}
