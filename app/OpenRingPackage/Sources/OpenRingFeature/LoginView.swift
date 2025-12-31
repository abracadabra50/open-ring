import SwiftUI
import DesignSystem
import RingClient

// MARK: - Login View

public struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showTwoFactor = false
    @State private var twoFactorPrompt = ""
    @State private var isEmailFocused = false
    @State private var isPasswordFocused = false
    @State private var isCodeFocused = false

    let onLoginSuccess: () -> Void

    public init(onLoginSuccess: @escaping () -> Void) {
        self.onLoginSuccess = onLoginSuccess
    }

    public var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle accent glow at top
            RadialGradient(
                colors: [
                    Color.Ring.accent.opacity(0.15),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Logo/Header
                VStack(spacing: Spacing.md) {
                    // Ring icon with glow
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(Color.Ring.accent.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .blur(radius: 20)

                        Image(systemName: "bell.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.Ring.accent)
                            .shadow(color: Color.Ring.accent.opacity(0.5), radius: 10)
                    }

                    Text("Open Ring")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Sign in with your Ring account")
                        .font(.Ring.body)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, Spacing.lg)

                if showTwoFactor {
                    twoFactorView
                } else {
                    loginFormView
                }

                // Error message
                if let error = errorMessage {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(.Ring.caption)
                    }
                    .foregroundStyle(Color.Ring.error)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.Ring.error.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                // Footer
                HStack {
                    // Settings button (left)
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")

                    Spacer()

                    // App name (center)
                    Text("open-ring")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))

                    Spacer()

                    // Placeholder for balance (right) - invisible to center the text
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.clear)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
            }
            .padding(.horizontal, Spacing.xl)
        }
        .frame(width: Layout.Popover.width, height: 480)
    }

    // MARK: - Login Form

    private var loginFormView: some View {
        VStack(spacing: Spacing.md) {
            // Email field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Email")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.6))

                DarkTextField(
                    placeholder: "your@email.com",
                    text: $email,
                    isFocused: $isEmailFocused,
                    icon: "envelope.fill"
                )
                .textContentType(.emailAddress)
                .disabled(isLoading)
            }

            // Password field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Password")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.6))

                DarkSecureField(
                    placeholder: "Password",
                    text: $password,
                    isFocused: $isPasswordFocused,
                    icon: "lock.fill"
                )
                .textContentType(.password)
                .disabled(isLoading)
            }

            // Login button
            Button {
                Task {
                    await performLogin()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                            .frame(width: 16, height: 16)
                    }
                    Text(isLoading ? "Signing in..." : "Sign In")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Group {
                        if canLogin {
                            LinearGradient(
                                colors: [Color.Ring.accent, Color.Ring.accent.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                )
                .foregroundStyle(canLogin ? .white : .white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: canLogin ? Color.Ring.accent.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!canLogin || isLoading)
            .padding(.top, Spacing.sm)
            .animation(.easeOut(duration: 0.2), value: canLogin)
        }
    }

    // MARK: - Two Factor View

    private var twoFactorView: some View {
        VStack(spacing: Spacing.md) {
            // Lock icon
            ZStack {
                Circle()
                    .fill(Color.Ring.accent.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.Ring.accent)
            }

            Text(twoFactorPrompt)
                .font(.Ring.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Code field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Verification Code")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.6))

                DarkTextField(
                    placeholder: "000000",
                    text: $twoFactorCode,
                    isFocused: $isCodeFocused,
                    icon: "number",
                    isCode: true
                )
                .disabled(isLoading)
            }

            // Verify button
            Button {
                Task {
                    await submitTwoFactor()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                            .frame(width: 16, height: 16)
                    }
                    Text(isLoading ? "Verifying..." : "Verify")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Group {
                        if twoFactorCode.count >= 6 {
                            LinearGradient(
                                colors: [Color.Ring.accent, Color.Ring.accent.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                )
                .foregroundStyle(twoFactorCode.count >= 6 ? .white : .white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: twoFactorCode.count >= 6 ? Color.Ring.accent.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(twoFactorCode.count < 6 || isLoading)

            // Back button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTwoFactor = false
                    twoFactorCode = ""
                    errorMessage = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back to login")
                        .font(.Ring.caption)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xs)
        }
    }

    // MARK: - Helpers

    private var canLogin: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private func performLogin() async {
        isLoading = true
        errorMessage = nil

        do {
            try await RingClient.shared.login(email: email, password: password)
            await MainActor.run {
                onLoginSuccess()
            }
        } catch let error as RingAuthError {
            await MainActor.run {
                switch error {
                case .requiresTwoFactor(let prompt):
                    twoFactorPrompt = prompt
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showTwoFactor = true
                    }
                default:
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                print("Login error: \(error)")
                errorMessage = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func submitTwoFactor() async {
        isLoading = true
        errorMessage = nil

        do {
            try await RingClient.shared.submitTwoFactorCode(twoFactorCode)
            await MainActor.run {
                onLoginSuccess()
            }
        } catch let error as RingAuthError {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "An unexpected error occurred"
                isLoading = false
            }
        }
    }
}

// MARK: - Dark Text Field

private struct DarkTextField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var icon: String? = nil
    var isCode: Bool = false

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(isCode ? .system(size: 18, weight: .medium, design: .monospaced) : .Ring.body)
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .multilineTextAlignment(isCode ? .center : .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    fieldFocused ? Color.Ring.accent.opacity(0.6) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .onChange(of: fieldFocused) { _, newValue in
            isFocused = newValue
        }
    }
}

// MARK: - Dark Secure Field

private struct DarkSecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var icon: String? = nil
    @State private var isRevealed = false

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20)
            }

            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.Ring.body)
            .foregroundStyle(.white)
            .focused($fieldFocused)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    fieldFocused ? Color.Ring.accent.opacity(0.6) : Color.white.opacity(0.1),
                    lineWidth: 1
                )
        )
        .onChange(of: fieldFocused) { _, newValue in
            isFocused = newValue
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Login") {
    LoginView(onLoginSuccess: {})
}

#Preview("Login - Two Factor") {
    LoginView(onLoginSuccess: {})
}
#endif
