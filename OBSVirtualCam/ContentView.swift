import SwiftUI

struct ContentView: View {
    @StateObject private var model = CameraModel()

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                SampleBufferPreview(layer: model.previewLayer)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                Divider()
                ConnectionStatusPanel(model: model)
            }
            .frame(minWidth: 620)
            CameraControlPanel(model: model.controls)
                .frame(minWidth: 310, idealWidth: 340, maxWidth: 420)
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}

private struct ConnectionStatusPanel: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusDot(active: model.isConnected)
                Text(model.state.label).lineLimit(2)
                Spacer()
                Button(model.isConnected ? "Disconnect" : "Connect Phone", action: toggleConnection)
                    .keyboardShortcut(.defaultAction)
            }
            HStack {
                StatusDot(active: model.virtualCameraStatus.hasPrefix("Streaming"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(CameraConstants.deviceName).font(.headline)
                    Text(model.virtualCameraStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry Output", action: model.startVirtualCamera)
                    .disabled(!model.isConnected)
            }
            Text("Uses OBS's installed camera extension; OBS itself can remain closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }

    private func toggleConnection() {
        model.isConnected ? model.disconnect() : model.connect()
    }
}

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle().fill(active ? Color.green : Color.secondary).frame(width: 9, height: 9)
    }
}

#Preview { ContentView() }
