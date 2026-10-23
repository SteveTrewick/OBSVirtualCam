# Example Swift UI driving code

## App
```swift
import SwiftUI


struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window   // << right after inserted in window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}


// OK, this is a copy paste job from https://stackoverflow.com/questions/76891046/how-to-set-aspect-ratio-of-container-window-for-macos-app-in-swiftui-not-cocoa
// I dont like that I dont know enough about this, need moar swiftui

@main
struct CALayerResizeApp: App {

  @State private var window: NSWindow?

    var body: some Scene {

        WindowGroup {

            ContentView()
              .background(WindowAccessor(window: $window))
                .onChange(of: window) { newWindow in
                  newWindow?.contentAspectRatio = NSMakeSize(1280, 720)

                  newWindow?.titlebarAppearsTransparent = true
                  newWindow?.titleVisibility = .visible
                  newWindow?.styleMask.insert(.fullSizeContentView)

                  newWindow?.level = .floating

                  newWindow?.collectionBehavior = [
                                      .managed,
                                      .participatesInCycle
                                  ]
                }
              .navigationTitle("Si5351 Calibration")
              //.edgesIgnoringSafeArea( .all )
              .edgesIgnoringSafeArea( .all )


        }


    }
}
```

## Content View

```swift


import SwiftUI
import AVFoundation
import OBSCamPlugin
import USBmuxd
import VideoTools


/*
  MARK: as of the now (Thu 26 Jun 25), this is the actual "howie diddit" version
        the actual important bit turns out to be getting the display layer
        to be the right size, which require overriding the bounds on the view
        hence the various mess below. Anyhoo, that's how you do that
        clearly needs many bells and whistles, record, etc, but hey ho, there you go.


*/




struct AVDisplayView: NSViewRepresentable {

    // make layer here

    let sublayer : AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> AVDisplayNSView {
      let view = AVDisplayNSView(sublayer: sublayer)
        return view
    }

    func updateNSView(_ nsView: AVDisplayNSView, context: Context) {
        nsView.updateLayerAppearance()
    }
}


class AVDisplayNSView: NSView {
    private let sublayer : AVSampleBufferDisplayLayer

    init(sublayer: AVSampleBufferDisplayLayer) {
        self.sublayer = sublayer
        super.init(frame: .zero)
        wantsLayer = true
        //sublayer.backgroundColor = NSColor.red.cgColor
        layer?.addSublayer(sublayer)
    }


    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // lock sublayer size to the view's bounds, otherwise we dont work at all.
        // which TBH is odd, as they are mostly 0 when we check
        sublayer.frame = bounds
       print(bounds)
    }

    func updateLayerAppearance() {
        // Optional: update background color, etc.
        //sublayer.backgroundColor = NSColor.red.cgColor
    }
}

struct ContentView: View {

    @State private var isLarge = false
    @State var layer = AVSampleBufferDisplayLayer()


    let enumerator = DeviceEnumerator()
    let connector  = Connector()
    let capture    = OBSCamCapture()
    let convertor  = SampleBufferConvertor()


    @State var frame : CMTimeValue = 1

    var body: some View {
      VStack {
            AVDisplayView(sublayer: layer)
                .aspectRatio(CGSize(width: 1280, height: 720), contentMode: .fit)
                .frame(maxWidth: 1280, maxHeight: 720)
                .border(Color.black, width:0)
                .padding(0)
                .onAppear {
                    startDisplay()
                }


      }

    }




    func startDisplay() {


      capture.videoHandler = { [self] result in
        switch result {

          case .error (let error)  : print (error)
          case .format(let format) : print (format)
          case .frame (let buffer) :

            if let samples = convertor.make (from: buffer, pts: CMTimeMake ( value: frame, timescale: 30 ) ) {
              frame += 1
              layer.enqueue(samples)
            }
        }
      }



      enumerator.enumerateDevices(.usb) { descriptors  in

        for descriptor in descriptors {
          print(descriptor)
          connector.connect(id: descriptor.device.deviceID, retry: 10) { result in
            switch result {
              case .failure(let fail)   : print(fail)
              case .success(let socket) : capture.from(socket: socket)
            }
          }
        }
    }

  }


}
```
