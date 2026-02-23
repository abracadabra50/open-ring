import Foundation
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

@Test func onvifKeywordParsingMatchesTapoPatterns() async throws {
    // Tapo C220 motion XML uses CellMotionDetector topic with IsMotion value
    let tapoMotionXml = """
    <tt:Message UtcTime="2026-02-23T21:00:00Z">
      <tt:Source><tt:SimpleItem Name="VideoSourceConfigurationToken" Value="vsconf"/></tt:Source>
      <tt:Data><tt:SimpleItem Name="IsMotion" Value="true"/></tt:Data>
    </tt:Message>
    """.lowercased()

    // Tapo C220 person XML uses MyRuleDetector/People topic
    let tapoPersonXml = """
    <tt:Message UtcTime="2026-02-23T21:00:00Z">
      <tt:Source><tt:SimpleItem Name="VideoSourceConfigurationToken" Value="vsconf"/></tt:Source>
      <tt:Key><tt:SimpleItem Name="Rule" Value="MyRuleDetector/People"/></tt:Key>
      <tt:Data><tt:SimpleItem Name="IsPeople" Value="true"/></tt:Data>
    </tt:Message>
    """.lowercased()

    // Empty response with no events
    let emptyXml = """
    <tev:PullMessagesResponse>
      <tev:CurrentTime>2026-02-23T21:00:00Z</tev:CurrentTime>
      <tev:TerminationTime>2026-02-23T21:01:00Z</tev:TerminationTime>
    </tev:PullMessagesResponse>
    """.lowercased()

    // Motion keywords should match Tapo motion XML
    #expect(OnvifEventMonitor.containsPositiveSignal(keywords: ["motion", "is_motion", "ismotion", "cellmotion"], in: tapoMotionXml) == true)

    // Person keywords should match Tapo people XML
    #expect(OnvifEventMonitor.containsPositiveSignal(keywords: ["person", "human", "people"], in: tapoPersonXml) == true)

    // Neither should match empty response
    #expect(OnvifEventMonitor.containsPositiveSignal(keywords: ["motion", "is_motion", "ismotion", "cellmotion"], in: emptyXml) == false)
    #expect(OnvifEventMonitor.containsPositiveSignal(keywords: ["person", "human", "people"], in: emptyXml) == false)
}

@Test func tapoAudioPolicyMutesAllWhenGlobalMuteEnabled() async throws {
    let result = TapoStreamManager.resolvedMutedStates(
        deviceIds: ["cam-a", "cam-b", "cam-c"],
        isMuted: true,
        activeDeviceId: "cam-b"
    )

    #expect(result["cam-a"] == true)
    #expect(result["cam-b"] == true)
    #expect(result["cam-c"] == true)
}

@Test func tapoAudioPolicyUnmutesOnlyActiveDeviceWhenUnmuted() async throws {
    let result = TapoStreamManager.resolvedMutedStates(
        deviceIds: ["cam-a", "cam-b", "cam-c"],
        isMuted: false,
        activeDeviceId: "cam-b"
    )

    #expect(result["cam-a"] == true)
    #expect(result["cam-b"] == false)
    #expect(result["cam-c"] == true)
}

@Test func tapoAudioPolicyMutesAllWhenNoActiveDeviceSelected() async throws {
    let result = TapoStreamManager.resolvedMutedStates(
        deviceIds: ["cam-a", "cam-b", "cam-c"],
        isMuted: false,
        activeDeviceId: nil
    )

    #expect(result["cam-a"] == true)
    #expect(result["cam-b"] == true)
    #expect(result["cam-c"] == true)
}

@Test func tapoAudioPolicySwitchesUnmutedDeviceWhenActiveChanges() async throws {
    let firstState = TapoStreamManager.resolvedMutedStates(
        deviceIds: ["cam-a", "cam-b"],
        isMuted: false,
        activeDeviceId: "cam-a"
    )
    let secondState = TapoStreamManager.resolvedMutedStates(
        deviceIds: ["cam-a", "cam-b"],
        isMuted: false,
        activeDeviceId: "cam-b"
    )

    #expect(firstState["cam-a"] == false)
    #expect(firstState["cam-b"] == true)
    #expect(secondState["cam-a"] == true)
    #expect(secondState["cam-b"] == false)
}
