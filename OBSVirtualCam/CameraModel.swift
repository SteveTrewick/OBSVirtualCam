import AVFoundation
import Combine
import OBSCamPlugin
import USBmuxd
import VideoTools

private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

@MainActor
final class CameraModel: ObservableObject {
    enum State: Equatable {
        case disconnected, discovering
        case connecting(String), streaming(String), failed(String)

        var label: String {
            switch self {
            case .disconnected: "Disconnected"
            case .discovering: "Looking for a USB-connected phone…"
            case .connecting(let name): "Connecting to \(name)…"
            case .streaming(let name): "Streaming from \(name)"
            case .failed(let message): message
            }
        }
    }

    let previewLayer = AVSampleBufferDisplayLayer()
    private nonisolated(unsafe) let previewRenderer: AVSampleBufferVideoRenderer
    let controls = CameraControlModel()
    @Published private(set) var state: State = .disconnected
    @Published private(set) var virtualCameraStatus = "Ready to use the installed OBS Virtual Camera"

    private let enumerator = DeviceEnumerator()
    private let connector = Connector()
    private let capture = OBSCamCapture()
    private nonisolated(unsafe) let sink = VirtualCameraSink()
    private let frameQueue = DispatchQueue(label: "steve.OBSVirtualCam.frames", qos: .userInteractive)
    private nonisolated(unsafe) var converter: FrameConverter?
    private var connectedDeviceName: String?

    init() {
        previewRenderer = previewLayer.sampleBufferRenderer
        do { converter = try FrameConverter() }
        catch { state = .failed(error.localizedDescription) }
        capture.videoHandler = { [weak self] result in self?.handle(result) }
    }

    var isConnected: Bool { connectedDeviceName != nil }

    func connect() {
        guard !isConnected else { return }
        state = .discovering
        enumerator.enumerateDevices(.usb) { [weak self] descriptors in
            guard let self else { return }
            Task { @MainActor in
                guard let descriptor = descriptors.first else {
                    self.state = .failed("No USB-connected iPhone was found.")
                    return
                }
                self.state = .connecting(descriptor.name)
                self.connector.connect(id: descriptor.device.deviceID, retry: 10) { result in
                    Task { @MainActor in
                        switch result {
                        case .failure(let error):
                            self.state = .failed("Could not connect to OBS Camera: \(String(describing: error))")
                        case .success(let socket):
                            self.connectedDeviceName = descriptor.name
                            self.capture.from(socket: socket)
                            self.controls.connect(deviceID: descriptor.device.deviceID)
                            self.state = .streaming(descriptor.name)
                            self.startVirtualCamera()
                        }
                    }
                }
            }
        }
    }

    func disconnect() {
        guard isConnected else { return }
        capture.stop()
        controls.disconnect()
        connectedDeviceName = nil
        sink.stop()
        virtualCameraStatus = "Not running"
        previewLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        state = .disconnected
    }

    func startVirtualCamera() {
        do {
            try sink.start()
            virtualCameraStatus = "Streaming 1280×720 at 30 fps"
        } catch {
            virtualCameraStatus = error.localizedDescription
        }
    }

    private nonisolated func handle(_ result: Decompressor.Result) {
        switch result {
        case .error(let error):
            Task { @MainActor in self.state = .failed("Video decoder error: \(String(describing: error))") }
        case .format:
            break
        case .frame(let pixelBuffer):
            let pixelBuffer = SendablePixelBuffer(value: pixelBuffer)
            frameQueue.async { [weak self] in
                guard let self, let converter = self.converter else { return }
                do {
                    let sampleBuffer = try converter.makeSampleBuffer(from: pixelBuffer.value)
                    self.sink.enqueue(sampleBuffer)
                    if self.previewRenderer.status == .failed { self.previewRenderer.flush() }
                    self.previewRenderer.enqueue(sampleBuffer)
                } catch {
                    Task { @MainActor in self.state = .failed(error.localizedDescription) }
                }
            }
        }
    }
}
