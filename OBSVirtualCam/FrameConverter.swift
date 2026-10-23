import AVFoundation
import CoreImage
import CoreVideo

final class FrameConverter {
    enum ConversionError: LocalizedError {
        case poolCreation(CVReturn)
        case pixelBufferCreation(CVReturn)
        case formatCreation(OSStatus)
        case sampleBufferCreation(OSStatus)

        var errorDescription: String? {
            switch self {
            case .poolCreation(let status): "Could not create the 720p pixel-buffer pool (\(status))."
            case .pixelBufferCreation(let status): "Could not allocate a 720p frame (\(status))."
            case .formatCreation(let status): "Could not describe the 720p frame format (\(status))."
            case .sampleBufferCreation(let status): "Could not create a video sample (\(status))."
            }
        }
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pool: CVPixelBufferPool
    private let formatDescription: CMVideoFormatDescription

    init() throws {
        let attributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: CameraConstants.width,
            kCVPixelBufferHeightKey: CameraConstants.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var createdPool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary,
            attributes as CFDictionary,
            &createdPool
        )
        guard poolStatus == kCVReturnSuccess, let createdPool else {
            throw ConversionError.poolCreation(poolStatus)
        }
        pool = createdPool

        var description: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: CameraConstants.width,
            height: CameraConstants.height,
            extensions: nil,
            formatDescriptionOut: &description
        )
        guard formatStatus == noErr, let description else {
            throw ConversionError.formatCreation(formatStatus)
        }
        formatDescription = description
    }

    func makeSampleBuffer(from source: CVPixelBuffer) throws -> CMSampleBuffer {
        var destination: CVPixelBuffer?
        let bufferStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
        guard bufferStatus == kCVReturnSuccess, let destination else {
            throw ConversionError.pixelBufferCreation(bufferStatus)
        }

        let image = CIImage(cvPixelBuffer: source)
        let outputWidth = CGFloat(CameraConstants.width)
        let outputHeight = CGFloat(CameraConstants.height)
        let scale = max(outputWidth / image.extent.width, outputHeight / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (outputWidth - scaled.extent.width) / 2 - scaled.extent.minX
        let y = (outputHeight - scaled.extent.height) / 2 - scaled.extent.minY
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
        let bounds = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        context.render(positioned.cropped(to: bounds), to: destination, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())

        var timing = CMSampleTimingInfo(
            duration: CameraConstants.frameDuration,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: destination,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw ConversionError.sampleBufferCreation(sampleStatus)
        }
        return sampleBuffer
    }
}
