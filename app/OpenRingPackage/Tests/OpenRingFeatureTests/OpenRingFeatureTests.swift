import Testing
import CoreGraphics
@testable import OpenRingFeature

// The real case that was broken: a 1920x1080 doorbell stream shown in the 340x500 portrait box
private let stream = CGSize(width: 1920, height: 1080)
private let box = CGSize(width: 340, height: 500)

@Test func fitShowsWholeImageUnstretched() {
    let rect = VideoGeometry.imageRect(content: stream, container: box, fill: false, zoom: 1, pan: CGSize(width: 99, height: 99))
    #expect(rect.width == 340)
    #expect(abs(rect.width / rect.height - 16.0 / 9.0) < 0.001)
    #expect(rect.midX == 170 && rect.midY == 250)  // nothing overflows, so pan is ignored
}

@Test func fillCoversViewAndPanStopsAtImageEdge() {
    let rect = VideoGeometry.imageRect(content: stream, container: box, fill: true, zoom: 1, pan: CGSize(width: 10_000, height: 50))
    #expect(rect.height == 500)
    #expect(abs(rect.width / rect.height - 16.0 / 9.0) < 0.001)
    #expect(abs(rect.minX) < 0.001)   // dragged fully right: image's left edge sits on the view's left edge
    #expect(rect.minY == 0)           // no vertical overflow, so no vertical pan
}
