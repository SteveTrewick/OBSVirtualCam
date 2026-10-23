import CoreMedia
import Foundation

enum CameraConstants {
    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let frameRate: Int32 = 30
    static let deviceName = "OBS Virtual Camera"
    // The signed extension bundled with OBS 31.0.3. OBS itself does not need to run.
    static let deviceUUID = UUID(uuidString: "7626645E-4425-469E-9D8B-97E0FA59AC75")!
    static let frameDuration = CMTime(value: 1, timescale: frameRate)
}
