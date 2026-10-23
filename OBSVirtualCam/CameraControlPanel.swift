import SwiftUI

struct CameraControlPanel: View {
    @ObservedObject var model: CameraControlModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ControlPanelHeader(state: model.state)
                CameraSettingsSection(model: model)
                ImageSettingsSection(model: model)
                FocusSettingsSection(model: model)
            }
            .padding(16)
        }
        .background(.background)
    }
}

private struct ControlPanelHeader: View {
    let state: CameraControlModel.State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Camera Controls").font(.title2.bold())
            HStack(spacing: 6) {
                StatusDot(active: state == .connected)
                Text(state.label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CameraSettingsSection: View {
    @ObservedObject var model: CameraControlModel

    var body: some View {
        GroupBox("Camera") {
            VStack(alignment: .leading, spacing: 10) {
                if let configuration = model.configuration {
                    Picker("Lens", selection: cameraBinding(configuration)) {
                        ForEach(configuration.cameras) { camera in
                            Text(camera.title).tag(camera.id)
                        }
                    }
                    Picker("Resolution", selection: stringBinding("resolution", configuration)) {
                        ForEach(configuration.strings("resolutions"), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Frame rate", selection: stringBinding("framerate", configuration)) {
                        ForEach(configuration.strings("framerates"), id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    Toggle("Torch", isOn: boolBinding("isTorchEnabled", configuration))
                        .disabled(!configuration.bool("isTorchAvailable"))
                    Toggle("Mirror front camera", isOn: boolBinding("isFrontCameraMirrored", configuration))
                    Toggle("Preview on phone", isOn: boolBinding("isDevicePreviewOn", configuration))
                } else {
                    Text("Connect the phone to load its available controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cameraBinding(_ configuration: CameraControlConfiguration) -> Binding<String> {
        Binding(get: { configuration.selectedCameraID }, set: model.selectCamera)
    }

    private func stringBinding(_ key: String, _ configuration: CameraControlConfiguration) -> Binding<String> {
        Binding(get: { configuration.string(key) }, set: { model.set(key, .string($0)) })
    }

    private func boolBinding(_ key: String, _ configuration: CameraControlConfiguration) -> Binding<Bool> {
        Binding(get: { configuration.bool(key) }, set: { model.set(key, .bool($0)) })
    }
}

private struct ImageSettingsSection: View {
    @ObservedObject var model: CameraControlModel

    var body: some View {
        GroupBox("Image") {
            if let configuration = model.configuration {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledSlider(
                        title: "Zoom",
                        value: numberBinding("zoomLevel", configuration),
                        range: configuration.number("zoomLevelMin")...configuration.number("zoomLevelMax"),
                        step: 0.05,
                        format: "%.2f×"
                    )
                    Picker("Exposure", selection: stringBinding("lightingMode", configuration)) {
                        Text("Automatic").tag("automatic")
                        Text("EV correction").tag("manualEV")
                        if configuration.bool("isCustomExposureModeSupported") {
                            Text("Manual").tag("manual")
                        }
                    }
                    exposureControl(configuration)
                    Picker("White balance", selection: whiteBalanceBinding(configuration)) {
                        Text("Automatic").tag(true)
                        if configuration.bool("isCustomWhiteBalanceModeSupported") {
                            Text("Manual").tag(false)
                        }
                    }
                    LabeledSlider(
                        title: "Temperature",
                        value: numberBinding("temperature", configuration),
                        range: configuration.number("temperatureMin")...configuration.number("temperatureMax"),
                        step: 50,
                        format: "%.0f K"
                    )
                    .disabled(configuration.bool("isAutomaticWhiteBalanceModeEnabled"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func exposureControl(_ configuration: CameraControlConfiguration) -> some View {
        switch configuration.string("lightingMode") {
        case "manualEV":
            LabeledSlider(
                title: "EV",
                value: numberBinding("exposureEV", configuration),
                range: configuration.number("exposureEVmin")...configuration.number("exposureEVmax"),
                step: 0.25,
                format: "%+.2f"
            )
        case "manual":
            LabeledSlider(
                title: "ISO",
                value: numberBinding("iso", configuration),
                range: configuration.number("isoMin")...configuration.number("isoMax"),
                step: 1,
                format: "%.0f"
            )
        default:
            EmptyView()
        }
    }

    private func numberBinding(_ key: String, _ configuration: CameraControlConfiguration) -> Binding<Double> {
        Binding(get: { configuration.number(key) }, set: { model.set(key, .number($0)) })
    }

    private func stringBinding(_ key: String, _ configuration: CameraControlConfiguration) -> Binding<String> {
        Binding(get: { configuration.string(key) }, set: { model.set(key, .string($0)) })
    }

    private func whiteBalanceBinding(_ configuration: CameraControlConfiguration) -> Binding<Bool> {
        Binding(
            get: { configuration.bool("isAutomaticWhiteBalanceModeEnabled") },
            set: { model.set("isAutomaticWhiteBalanceModeEnabled", .bool($0)) }
        )
    }
}

private struct FocusSettingsSection: View {
    @ObservedObject var model: CameraControlModel

    var body: some View {
        GroupBox("Focus") {
            if let configuration = model.configuration, !configuration.focusConfiguration.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: manualFocusBinding(configuration)) {
                        Text("Automatic").tag(false)
                        Text("Manual").tag(true)
                    }
                    .disabled(!(configuration.focusConfiguration["isLockingFocusWithCustomLensPositionSupported"]?.bool ?? false))
                    LabeledSlider(
                        title: "Lens position",
                        value: lensPositionBinding(configuration),
                        range: (configuration.focusConfiguration["minLensPosition"]?.number ?? 0)...(configuration.focusConfiguration["maxLensPosition"]?.number ?? 1),
                        step: 0.05,
                        format: "%.2f"
                    )
                    .disabled(!configuration.isManualFocus)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func manualFocusBinding(_ configuration: CameraControlConfiguration) -> Binding<Bool> {
        Binding(get: { configuration.isManualFocus }, set: model.setManualFocus)
    }

    private func lensPositionBinding(_ configuration: CameraControlConfiguration) -> Binding<Double> {
        Binding(
            get: { configuration.focusConfiguration["lensPosition"]?.number ?? 0 },
            set: model.setLensPosition
        )
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            // Do not pass `step` to Slider: AppKit rebuilds one tick per step during resize.
            // The phone's ISO and zoom ranges can produce thousands of ticks and freeze the UI.
            Slider(value: Binding(
                get: { value },
                set: { newValue in
                    let rounded = range.lowerBound + ((newValue - range.lowerBound) / step).rounded() * step
                    value = min(max(rounded, range.lowerBound), range.upperBound)
                }
            ), in: range)
        }
    }
}
