import CameraDomain
import DesignSystem
import SwiftUI

public struct TapoSetupView: View {
    private let onTest: (
        _ host: String,
        _ username: String,
        _ password: String,
        _ cloudPassword: String,
        _ profile: CameraStreamProfile,
        _ rtspPort: Int,
        _ onvifPort: Int
    ) async throws -> Void

    private let onSave: (
        _ host: String,
        _ username: String,
        _ password: String,
        _ cloudPassword: String,
        _ profile: CameraStreamProfile,
        _ rtspPort: Int,
        _ onvifPort: Int
    ) async -> Void

    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var cloudPassword = ""
    @State private var profile: CameraStreamProfile = .main
    @State private var rtspPort = "554"
    @State private var onvifPort = "2020"
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isTesting = false
    @State private var isSaving = false

    public init(
        summary: CameraSetupSummary? = nil,
        onTest: @escaping (
            _ host: String,
            _ username: String,
            _ password: String,
            _ cloudPassword: String,
            _ profile: CameraStreamProfile,
            _ rtspPort: Int,
            _ onvifPort: Int
        ) async throws -> Void,
        onSave: @escaping (
            _ host: String,
            _ username: String,
            _ password: String,
            _ cloudPassword: String,
            _ profile: CameraStreamProfile,
            _ rtspPort: Int,
            _ onvifPort: Int
        ) async -> Void
    ) {
        self.onTest = onTest
        self.onSave = onSave

        if let summary {
            _host = State(initialValue: summary.host)
            _username = State(initialValue: summary.username)
            _profile = State(initialValue: summary.profile)
            _rtspPort = State(initialValue: String(summary.rtspPort))
            _onvifPort = State(initialValue: String(summary.onvifPort))
        }
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.06, green: 0.07, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Set up Tapo C220")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Enter local camera details for RTSP live view and ONVIF events.")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.65))

                VStack(spacing: Spacing.sm) {
                    textField("Camera IP / Hostname", text: $host)
                    textField("Camera Account Username", text: $username)
                    SecureField("Camera Account Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    Divider()
                        .background(.white.opacity(0.2))

                    Text("TP-Link Cloud (for event detection)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    SecureField("TP-Link App Password", text: $cloudPassword)
                        .textFieldStyle(.roundedBorder)

                    Picker("Stream Profile", selection: $profile) {
                        ForEach(CameraStreamProfile.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }

                    HStack(spacing: Spacing.sm) {
                        textField("RTSP Port", text: $rtspPort)
                        textField("ONVIF Port", text: $onvifPort)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.Ring.caption)
                        .foregroundStyle(isError ? Color.red : Color.green)
                        .padding(.top, 2)
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSubmit || isSaving)

                    Button {
                        Task { await saveConfiguration() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save and Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.Ring.accent)
                    .disabled(!canSubmit || isTesting)
                }
                .padding(.top, 2)

                Spacer(minLength: 0)

                Text("Phase 1: Tapo-first backend. Ring provider remains in code for Phase 2.")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(Spacing.lg)
        }
        .frame(width: 420, height: 530)
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            Int(rtspPort) != nil &&
            Int(onvifPort) != nil
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
    }

    private func testConnection() async {
        guard let rtspPort = Int(rtspPort), let onvifPort = Int(onvifPort) else {
            statusMessage = "Ports must be numeric."
            isError = true
            return
        }

        isTesting = true
        isError = false
        statusMessage = nil
        do {
            try await onTest(host, username, password, cloudPassword, profile, rtspPort, onvifPort)
            statusMessage = "Connection test passed."
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
        isTesting = false
    }

    private func saveConfiguration() async {
        guard let rtspPort = Int(rtspPort), let onvifPort = Int(onvifPort) else {
            statusMessage = "Ports must be numeric."
            isError = true
            return
        }

        isSaving = true
        await onSave(host, username, password, cloudPassword, profile, rtspPort, onvifPort)
        isSaving = false
    }
}
