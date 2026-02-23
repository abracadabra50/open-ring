import AVFoundation
import CameraDomain
import CoreImage
import Foundation

private final class SnapshotMonitorCallback: @unchecked Sendable {
    private let onMotionEvent: @Sendable (CameraEvent) -> Void

    init(onMotionEvent: @escaping @Sendable (CameraEvent) -> Void) {
        self.onMotionEvent = onMotionEvent
    }

    func emitMotionEvent(_ event: CameraEvent) {
        onMotionEvent(event)
    }
}

final class SnapshotDiffEventMonitor {
    private let config: TapoSetupConfig
    private let password: String

    private var task: Task<Void, Never>?
    private let diffThreshold: Double

    init(config: TapoSetupConfig, password: String, diffThreshold: Double = 0.12) {
        self.config = config
        self.password = password
        self.diffThreshold = diffThreshold
    }

    func start(onMotionEvent: @escaping @Sendable (CameraEvent) -> Void) {
        stop()
        let config = self.config
        let password = self.password
        let diffThreshold = self.diffThreshold
        let callback = SnapshotMonitorCallback(onMotionEvent: onMotionEvent)
        let operation: @Sendable () async -> Void = { [config, password, diffThreshold, callback] in
            var previousLuma: Double?
            var lastEmittedAt = Date.distantPast
            while !Task.isCancelled {
                if let luma = await Self.captureAverageLuma(config: config, password: password) {
                    if let previousLuma {
                        let delta = abs(previousLuma - luma)
                        let now = Date()
                        let debounceOK = now.timeIntervalSince(lastEmittedAt) > 8
                        if delta >= diffThreshold && debounceOK {
                            lastEmittedAt = now
                            callback.emitMotionEvent(
                                CameraEvent(
                                    deviceId: config.deviceId,
                                    deviceName: config.deviceName,
                                    kind: .motion,
                                    source: "fallback",
                                    detail: "Snapshot-diff fallback"
                                )
                            )
                        }
                    }
                    previousLuma = luma
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
        task = Task.detached(operation: operation)
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func captureAverageLuma(config: TapoSetupConfig, password: String) async -> Double? {
        guard let url = rtspURL(config: config, password: password) else {
            return nil
        }

        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Authorization": basicAuthHeader(username: config.username, password: password),
            ]
        ]
        let asset = AVURLAsset(url: url, options: options)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)

        do {
            let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
            let ciImage = CIImage(cgImage: cgImage)
            return averageLuma(for: ciImage)
        } catch {
            return nil
        }
    }

    private static func averageLuma(for image: CIImage) -> Double? {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)

        guard let output = filter.outputImage else {
            return nil
        }

        let context = CIContext(options: nil)
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }

    private static func rtspURL(config: TapoSetupConfig, password: String) -> URL? {
        guard let baseURL = config.rtspURL else {
            return nil
        }
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        comps.user = config.username
        comps.password = password
        return comps.url
    }

    private static func basicAuthHeader(username: String, password: String) -> String {
        let credentials = "\(username):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
