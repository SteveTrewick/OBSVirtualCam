import Foundation
import Combine
import OBSCamPlugin

struct CameraChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let position: Int
    let rawValue: JSONValue
}

struct CameraControlConfiguration: Equatable {
    var values: [String: JSONValue]

    func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        values[key]?.bool ?? defaultValue
    }

    func number(_ key: String, default defaultValue: Double = 0) -> Double {
        values[key]?.number ?? defaultValue
    }

    func string(_ key: String, default defaultValue: String = "") -> String {
        values[key]?.string ?? defaultValue
    }

    func strings(_ key: String) -> [String] {
        values[key]?.array?.compactMap(\.string) ?? []
    }

    var cameras: [CameraChoice] {
        values["cameras"]?.array?.compactMap { value in
            guard let object = value.object,
                  let id = object["id"]?.string,
                  let title = object["title"]?.string
            else { return nil }
            return CameraChoice(
                id: id,
                title: title,
                position: Int(object["position"]?.number ?? 0),
                rawValue: value
            )
        } ?? []
    }

    var selectedCameraID: String {
        values["selectedCamera"]?.object?["id"]?.string ?? ""
    }

    var focusConfiguration: [String: JSONValue] {
        values["focusConfiguration"]?.object ?? [:]
    }

    var isManualFocus: Bool {
        let mode = focusConfiguration["focusMode"]?.object ?? [:]
        return mode["lockedLensPosition"] != nil || mode["locked"] != nil
    }
}

@MainActor
final class CameraControlModel: ObservableObject {
    enum State: Equatable {
        case disconnected, connecting, connected, failed(String)

        var label: String {
            switch self {
            case .disconnected: "Controls disconnected"
            case .connecting: "Connecting controls…"
            case .connected: "Controls connected over USB"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var configuration: CameraControlConfiguration?

    private let client = OBSCamControlClient()
    private var connectionAttempt = UUID()

    init() {
        client.eventHandler = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func connect(deviceID: Int) {
        let attempt = UUID()
        connectionAttempt = attempt
        state = .connecting
        configuration = nil
        client.connect(id: deviceID)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.connectionAttempt == attempt, self.state == .connecting else { return }
            self.client.disconnect()
            self.state = .failed("Timed out connecting camera controls. Check that OBS Camera's control server is running.")
        }
    }

    func disconnect() {
        connectionAttempt = UUID()
        client.disconnect()
        configuration = nil
        state = .disconnected
    }

    func set(_ key: String, _ value: JSONValue) {
        guard var configuration else { return }
        configuration.values[key] = value
        publish(configuration)
    }

    func selectCamera(id: String) {
        guard let camera = configuration?.cameras.first(where: { $0.id == id }) else { return }
        set("selectedCamera", camera.rawValue)
    }

    func setManualFocus(_ enabled: Bool) {
        guard var configuration else { return }
        var focus = configuration.focusConfiguration
        let lensPosition = focus["lensPosition"]?.number ?? 0
        focus["focusMode"] = enabled
            ? .object(["lockedLensPosition": .number(lensPosition)])
            : .object(["auto": .number(0)])
        if var crosshair = focus["crosshairMode"]?.object,
           var combined = crosshair["combined"]?.object {
            combined["isLocked"] = .bool(enabled)
            crosshair["combined"] = .object(combined)
            focus["crosshairMode"] = .object(crosshair)
        }
        configuration.values["focusConfiguration"] = .object(focus)
        publish(configuration)
    }

    func setLensPosition(_ position: Double) {
        guard var configuration else { return }
        var focus = configuration.focusConfiguration
        focus["lensPosition"] = .number(position)
        if configuration.isManualFocus {
            focus["focusMode"] = .object(["lockedLensPosition": .number(position)])
        }
        configuration.values["focusConfiguration"] = .object(focus)
        publish(configuration)
    }

    private func publish(_ newConfiguration: CameraControlConfiguration) {
        configuration = newConfiguration
        do {
            let content = try JSONEncoder().encode(newConfiguration.values)
            guard let contentString = String(data: content, encoding: .utf8) else { return }
            let envelope = ControlEnvelope(messageType: "setDeviceConfiguration", content: contentString)
            let message = try JSONEncoder().encode(envelope)
            if let text = String(data: message, encoding: .utf8) { client.send(text: text) }
        } catch {
            state = .failed("Could not encode camera setting: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: OBSCamControlClient.Event) {
        switch event {
        case .connected:
            state = .connected
        case .disconnected:
            if case .failed = state { return }
            configuration = nil
            state = .disconnected
        case .failure(let message):
            state = .failed(message)
        case .message(let text):
            receive(text)
        }
    }

    private func receive(_ text: String) {
        do {
            let envelope = try JSONDecoder().decode(ControlEnvelope.self, from: Data(text.utf8))
            guard envelope.messageType == "setDeviceConfiguration" else { return }
            let values = try JSONDecoder().decode([String: JSONValue].self, from: Data(envelope.content.utf8))
            configuration = CameraControlConfiguration(values: values)
            state = .connected
        } catch {
            state = .failed("Could not read camera settings: \(error.localizedDescription)")
        }
    }
}

private struct ControlEnvelope: Codable {
    let messageType: String
    let content: String
}
