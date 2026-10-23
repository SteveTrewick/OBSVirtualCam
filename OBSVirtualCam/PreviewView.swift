import AVFoundation
import SwiftUI

struct SampleBufferPreview: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> SampleBufferView {
        SampleBufferView(displayLayer: layer)
    }

    func updateNSView(_ nsView: SampleBufferView, context: Context) {}
}

final class SampleBufferView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        displayLayer.videoGravity = .resizeAspect
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeBackingLayer() -> CALayer { displayLayer }
}
