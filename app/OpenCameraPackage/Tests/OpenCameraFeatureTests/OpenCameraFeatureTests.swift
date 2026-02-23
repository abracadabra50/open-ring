import Testing
@testable import OpenCameraFeature
@testable import CameraDomain
@testable import CameraProviders

@Test func tapoConfigBuildsExpectedRtspURL() async throws {
    let config = TapoSetupConfig(
        host: "192.168.1.20",
        username: "user",
        profile: .sub,
        rtspPort: 8554,
        onvifPort: 2020
    )

    #expect(config.rtspURL?.absoluteString == "rtsp://192.168.1.20:8554/stream2")
    #expect(config.deviceId == "tapo-c220-192.168.1.20")
}

@Test func notificationManagerDetectsRecentUnseenEvents() async throws {
    let now = Date()
    let oldId = UUID().uuidString
    let newId = UUID().uuidString
    let oldEvents: [CameraEvent] = [
        CameraEvent(id: oldId, deviceId: "device", deviceName: "Front Door", kind: .motion, createdAt: now.addingTimeInterval(-30), source: "onvif")
    ]

    let newEvents: [CameraEvent] = [
        CameraEvent(id: oldId, deviceId: "device", deviceName: "Front Door", kind: .motion, createdAt: now.addingTimeInterval(-30), source: "onvif"),
        CameraEvent(id: newId, deviceId: "device", deviceName: "Front Door", kind: .person, createdAt: now.addingTimeInterval(-10), source: "onvif"),
    ]

    let detected = NotificationManager.shared.detectNewEvents(old: oldEvents, new: newEvents)
    #expect(detected.count == 1)
    #expect(detected.first?.id == newId)
}

@Test func cameraEventKindsExposeDisplayNames() async throws {
    #expect(CameraEventKind.motion.displayName == "Motion detected")
    #expect(CameraEventKind.person.displayName == "Person detected")
}
