import SwiftUI

/// Login view for email/password authentication
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showForgotPassword = false
    
    @ObservedObject private var authManager = AuthManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo and title
                    headerSection
                    
                    // Login form
                    formSection
                    
                    // Sign in button
                    signInButton
                    
                    // Forgot password
                    forgotPasswordButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordSheet(email: email)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 70))
                .foregroundStyle(.blue)
            
            Text("ScheduleHQ")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Sign in to view your schedule")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Form Section
    
    private var formSection: some View {
        VStack(spacing: 16) {
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Label("Email", systemImage: "envelope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Label("Password", systemImage: "lock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Group {
                        if showPassword {
                            TextField("Enter your password", text: $password)
                        } else {
                            SecureField("Enter your password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // MARK: - Sign In Button
    
    private var signInButton: some View {
        Button {
            signIn()
        } label: {
            Group {
                if authManager.isSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isFormValid || authManager.isSigningIn)
    }
    
    // MARK: - Forgot Password Button
    
    private var forgotPasswordButton: some View {
        Button {
            showForgotPassword = true
        } label: {
            Text("Forgot Password?")
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
    }
    
    // MARK: - Helpers
    
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }
    
    private func signIn() {
        Task {
            try? await authManager.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        }
    }
}

// MARK: - Forgot Password Sheet

struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var isSending = false
    
    @ObservedObject private var authManager = AuthManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
                
                Text("Reset Password")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your email address and we'll send you instructions to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                Button {
                    sendResetEmail()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Send Reset Email")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(!email.isEmpty ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(email.isEmpty || isSending)
                
                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func sendResetEmail() {
        isSending = true
        Task {
            try? await authManager.sendPasswordResetEmail(to: email)
            isSending = false
            dismiss()
        }
    }
}

#Preview {
    LoginView()
}
