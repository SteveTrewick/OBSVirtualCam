# OBSVirtualCam

An experimental macOS SwiftUI app that receives video from the **OBS Camera** iPhone app over USB, shows a live preview and camera controls, and feeds **OBS Virtual Camera** without keeping OBS Studio open. The virtual-camera output is **1280×720 with 30 fps sample timing**. This is a personal prototype, not a polished or supported webcam product.

## What you need

- macOS 15.7 or later, as set by the Xcode project, and Xcode to build the app.
- An iPhone connected by USB, trusted by the Mac, with the OBS Camera iOS app running and streaming.
- [OBSCamPlugin](https://github.com/SteveTrewick/OBSCamPlugin), fetched by Xcode from GitHub at the exact `1.0.0` release tag.
- OBS Studio installed with its macOS virtual-camera extension. **One-time setup:** open OBS, start its Virtual Camera, approve/enable the camera extension in System Settings if prompted, then stop the virtual camera and quit OBS. On later runs, OBS itself can remain closed.

Open `OBSVirtualCam.xcodeproj`, build and run the app, then click **Connect Phone**. The app selects the first USB-connected device it finds. Once the phone stream connects, it starts feeding the installed OBS Virtual Camera automatically; choose **OBS Virtual Camera** in Zoom or another camera client. **Retry Output** retries the virtual-camera connection if the extension was not available at first. The controls use a separate USB connection to the phone's control server, so they may appear a little after the picture.

## How it works

`OBSCamPlugin` handles usbmuxd transport and video decoding. The app scales/crops decoded frames to 1280×720, displays them with `AVSampleBufferDisplayLayer`, and writes the same frames to OBS's Core Media I/O camera-extension sink. Camera settings—such as lens, resolution, frame rate, exposure, white balance, zoom, and focus where supported by the phone—are sent over the plugin's USB-tunneled control connection. No phone Wi-Fi address is needed.

## Limitations and caveats

- **OBS's extension is required.** This app does not install, activate, or contain a virtual-camera extension of its own. It targets the OBS Virtual Camera device UUID used by the tested OBS 31.0.3 installation and assumes the extension's second stream is its input sink. OBS updates may break either assumption.
- **Video only.** The app does not forward the phone's audio to Zoom or another client; select a separate microphone.
- **Fixed output format.** Frames are converted to 1280×720 with 30 fps sample timing, regardless of the phone's selected capture resolution or frame rate. The app does not pace or resample incoming frames, so actual delivery cadence follows the phone stream. Aspect-fill scaling may crop the image.
- **USB-first and single-device.** It chooses the first USB device returned by discovery. There is no device picker, Wi-Fi transport, or automatic recovery from a dropped connection; disconnect and reconnect manually if needed.
- **Experimental control protocol.** The control panel depends on the OBS Camera app's current control-server messages and available settings. Controls can connect slowly or fail independently of video; not every control is supported by every phone/camera mode.
- **Local development setup.** The Xcode project fetches `OBSCamPlugin` from GitHub but has app-specific bundle/signing settings. Adjust those settings for your machine. This is not a distributable, self-contained build.

This project is not affiliated with OBS Studio or the OBS Camera iOS app.

## Performance note: stepped sliders can freeze window resizing

If resizing is smooth before connecting the phone but beachballs after the camera controls appear, inspect the controls before blaming the video preview. A live `sample` capture during a roughly 20-second resize stall showed the main thread spending about nine seconds in `NSSlider` layout, especially `NSSliderTickMarks _rebuildTickMarks`.

The phone reported ISO 35–4375 and zoom 1–171.875. Passing `step: 1` and `step: 0.05` respectively to SwiftUI's `Slider(value:in:step:)` made AppKit manage thousands of discrete tick positions and rebuild them during live window layout. The virtual camera stream was not the cause of this stall.

`LabeledSlider` in `OBSVirtualCam/CameraControlPanel.swift` now uses a continuous native slider and rounds the binding value to the requested increment. Keep that distinction if adding new controls: quantize the value in the binding instead of passing a fine step to the native slider over a large range. If a similar freeze returns, capture the process with `sample <pid> 20 -file <path>` while actively resizing; an idle capture misses the relevant stack.

## Credits

Created by **Steve Trewick**, with implementation and documentation assistance from **OpenAI Codex**. Thanks to the OBS Studio contributors for the virtual-camera extension that this prototype reuses.
