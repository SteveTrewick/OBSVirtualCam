import CoreMedia
import CoreMediaIO
import Foundation

final class VirtualCameraSink {
    enum SinkError: LocalizedError {
        case property(OSStatus, String)
        case deviceUnavailable
        case sinkUnavailable
        case queueUnavailable(OSStatus)
        case startFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .property(let status, let name): "Core Media I/O could not read \(name) (\(status))."
            case .deviceUnavailable: "OBS Virtual Camera is not active. Open OBS once, click Start Virtual Camera, approve it in System Settings if asked, then quit OBS and retry here."
            case .sinkUnavailable: "The virtual camera's input stream is unavailable."
            case .queueUnavailable(let status): "The virtual camera queue could not be opened (\(status))."
            case .startFailed(let status): "The virtual camera input could not start (\(status))."
            }
        }
    }

    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var bufferQueue: CMSimpleQueue?

    var isRunning: Bool { bufferQueue != nil }

    func start() throws {
        guard !isRunning else { return }
        deviceID = try findDevice()
        var streamAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let streams: [CMIOStreamID] = try readArray(
            objectID: deviceID,
            address: &streamAddress,
            name: "camera streams"
        )
        guard streams.count >= 2 else { throw SinkError.sinkUnavailable }
        streamID = streams[1]

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let queueStatus = CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &unmanagedQueue)
        guard queueStatus == noErr, let unmanagedQueue else { throw SinkError.queueUnavailable(queueStatus) }
        let queue = unmanagedQueue.takeRetainedValue()
        let startStatus = CMIODeviceStartStream(deviceID, streamID)
        guard startStatus == noErr else { throw SinkError.startFailed(startStatus) }
        bufferQueue = queue
    }

    func stop() {
        guard isRunning else { return }
        CMIODeviceStopStream(deviceID, streamID)
        bufferQueue = nil
        deviceID = 0
        streamID = 0
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard let bufferQueue else { return }
        let retained = Unmanaged.passRetained(sampleBuffer).toOpaque()
        let status = CMSimpleQueueEnqueue(bufferQueue, element: retained)
        if status != noErr { Unmanaged<CMSampleBuffer>.fromOpaque(retained).release() }
    }

    private func findDevice() throws -> CMIODeviceID {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let devices: [CMIODeviceID] = try readArray(
            objectID: CMIOObjectID(kCMIOObjectSystemObject),
            address: &devicesAddress,
            name: "camera devices"
        )

        for device in devices {
            var uidAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var uid: Unmanaged<CFString>?
            var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &uid) { pointer in
                CMIOObjectGetPropertyData(device, &uidAddress, 0, nil, dataSize, &dataSize, pointer)
            }
            guard status == noErr, let uid else { continue }
            let value = uid.takeRetainedValue() as String
            if value.caseInsensitiveCompare(CameraConstants.deviceUUID.uuidString) == .orderedSame {
                return device
            }
        }
        throw SinkError.deviceUnavailable
    }

    private func readArray<Element: FixedWidthInteger>(
        objectID: CMIOObjectID,
        address: inout CMIOObjectPropertyAddress,
        name: String
    ) throws -> [Element] {
        var byteCount: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(objectID, &address, 0, nil, &byteCount)
        guard status == noErr else { throw SinkError.property(status, name) }
        let count = Int(byteCount) / MemoryLayout<Element>.stride
        var values = [Element](repeating: .zero, count: count)
        status = values.withUnsafeMutableBytes { bytes in
            CMIOObjectGetPropertyData(objectID, &address, 0, nil, byteCount, &byteCount, bytes.baseAddress!)
        }
        guard status == noErr else { throw SinkError.property(status, name) }
        return values
    }
}
