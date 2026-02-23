import CameraDomain
import DesignSystem
import AppKit
import SwiftUI

public struct TapoPopoverView: View {
    @EnvironmentObject private var cameraController: AppCameraController
    @StateObject private var streamManager = TapoStreamManager()
    @State private var isDrawerExpanded = true
    @State private var isMuted = true

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                liveArea
                    .frame(height: 280)

                DrawerPanel(isExpanded: $isDrawerExpanded, expandedHeight: 260) {
                    drawerContent
                }

                footerBar
            }
        }
        .frame(width: 420, height: 610)
        .task {
            streamManager.configure(provider: cameraController.provider)
            await streamManager.startAllStreams(for: cameraController.devices)
            streamManager.setActiveDevice(cameraController.selectedDevice?.id ?? cameraController.devices.first?.id)
            isMuted = true
            streamManager.setMuted(true)
            cameraController.setLiveActive(true)
        }
        .onDisappear {
            cameraController.setLiveActive(false)
            isMuted = true
            streamManager.setMuted(true)
            Task {
                await streamManager.stopAllStreams()
            }
        }
        .onChange(of: cameraController.devices) { _, newDevices in
            Task {
                await streamManager.stopAllStreams()
                await streamManager.startAllStreams(for: newDevices)
                streamManager.setActiveDevice(cameraController.selectedDevice?.id ?? newDevices.first?.id)
                streamManager.setMuted(isMuted)
            }
        }
        .onChange(of: cameraController.selectedDevice?.id) { _, newDeviceId in
            cameraController.setLiveActive(newDeviceId != nil)
            streamManager.setActiveDevice(newDeviceId)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Menu {
                ForEach(cameraController.devices) { device in
                    Button(device.name) {
                        cameraController.selectedDevice = device
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(cameraController.selectedDevice?.name ?? "No camera")
                        .font(.Ring.headline)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.black.opacity(0.8))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let selected = cameraController.selectedDevice {
            switch streamManager.state(for: selected.id) {
            case .connected:
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
            case .connecting:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("CONNECTING")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.25))
                .clipShape(Capsule())
            case .offline:
                Text("OFFLINE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.25))
                    .clipShape(Capsule())
            case .error:
                Text("ERROR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.25))
                    .clipShape(Capsule())
            case .unconfigured:
                EmptyView()
            }
        }
    }

    private var liveArea: some View {
        ZStack {
            Color.black
            if let device = cameraController.selectedDevice {
                if let session = streamManager.session(for: device.id) {
                    RtspPlayerView(session: session)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    VStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text(streamPlaceholderText(for: device))
                            .font(.Ring.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                Text("No camera selected")
                    .font(.Ring.body)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .overlay(alignment: .bottomLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cameraController.devices) { device in
                        Button {
                            cameraController.selectedDevice = device
                        } label: {
                            Text(device.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(cameraController.selectedDevice?.id == device.id ? .black : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(cameraController.selectedDevice?.id == device.id ? Color.white : Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
            }
        }
    }

    private func streamPlaceholderText(for device: CameraDevice) -> String {
        switch streamManager.state(for: device.id) {
        case .connecting:
            return "Connecting to \(device.name)…"
        case .offline:
            return "\(device.name) is offline"
        case .error(let message):
            return message
        case .connected:
            return "Loading stream…"
        case .unconfigured:
            return "Camera is not configured"
        }
    }

    private var drawerContent: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("Recent events")
                    .font(.Ring.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            if cameraController.events.isEmpty {
                Text("Waiting for motion/person events…")
                    .font(.Ring.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(cameraController.events.prefix(8)) { event in
                            eventRow(event)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                placeholderCard(
                    title: "AI Guard",
                    subtitle: "Tapo support coming in Phase 2",
                    symbol: "sparkles"
                )
                placeholderCard(
                    title: "Clip Playback",
                    subtitle: "Tapo support coming in Phase 2",
                    symbol: "play.rectangle"
                )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
    }

    private func eventRow(_ event: CameraEvent) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(timeString(event.createdAt))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 56, alignment: .leading)

            Image(systemName: event.kind == .person ? "person.fill" : "figure.walk")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.kind == .person ? Color.green : Color.yellow)
                .frame(width: 16)

            Text(event.kind.displayName)
                .font(.Ring.body)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Text(event.source.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func placeholderCard(title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footerBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                Task {
                    await cameraController.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Button {
                cameraController.toggleSnooze()
            } label: {
                Label(cameraController.isSnoozed ? "Unsnooze" : "Snooze", systemImage: "moon.fill")
            }
            .buttonStyle(.borderless)

            Button {
                isMuted.toggle()
                streamManager.setMuted(isMuted)
            } label: {
                Label(
                    isMuted ? "Unmute" : "Mute",
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, Spacing.md)
        .frame(height: 34)
        .background(.black.opacity(0.8))
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
