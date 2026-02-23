import CameraDomain
import Foundation
import RingClient

/// Phase-2 adapter placeholder.
/// Ring remains in-repo but is not wired into the runtime provider registry in phase 1.
public final class RingProviderAdapter: CameraProvider, @unchecked Sendable {
    public let id = "ring"
    public let displayName = "Ring (Phase 2)"

    public init() {}

    public func loadSetupSummary() async throws -> CameraSetupSummary? {
        nil
    }

    public func saveSetup(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws {
        throw CameraProviderError.unsupported("Ring provider adapter is not enabled in phase 1.")
    }

    public func clearSetup() async throws {}

    public func testConnection(
        host: String,
        username: String,
        password: String,
        cloudPassword: String,
        profile: CameraStreamProfile,
        rtspPort: Int,
        onvifPort: Int
    ) async throws {
        throw CameraProviderError.unsupported("Ring provider adapter is not enabled in phase 1.")
    }

    public func currentConnectionState() async -> CameraConnectionState {
        .unconfigured
    }

    public func connect() async throws {
        throw CameraProviderError.unsupported("Ring provider adapter is not enabled in phase 1.")
    }

    public func disconnect() async {}

    public func fetchDevices() async throws -> [CameraDevice] {
        throw CameraProviderError.unsupported("Ring provider adapter is not enabled in phase 1.")
    }

    public func fetchRecentEvents(limit: Int) async throws -> [CameraEvent] {
        []
    }

    public func startLiveSession(deviceId: String) async throws -> any CameraLiveSession {
        throw CameraProviderError.unsupported("Ring provider adapter is not enabled in phase 1.")
    }

    public func stopLiveSession(deviceId: String) async {}

    public func startEventMonitoring(
        onEvent: @escaping @Sendable (CameraEvent) -> Void,
        onStatusChange: @escaping @Sendable (CameraConnectionState) -> Void
    ) async {
        onStatusChange(.unconfigured)
    }

    public func stopEventMonitoring() async {}
}
