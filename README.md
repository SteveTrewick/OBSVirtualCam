# OBSVirtualCam

## Performance note: stepped sliders can freeze window resizing

If resizing is smooth before connecting the phone but beachballs after the camera controls appear, inspect the controls before blaming the video preview. A live `sample` capture during a roughly 20-second resize stall showed the main thread spending about nine seconds in `NSSlider` layout, especially `NSSliderTickMarks _rebuildTickMarks`.

The phone reported ISO 35–4375 and zoom 1–171.875. Passing `step: 1` and `step: 0.05` respectively to SwiftUI's `Slider(value:in:step:)` made AppKit manage thousands of discrete tick positions and rebuild them during live window layout. The virtual camera stream was not the cause of this stall.

`LabeledSlider` in `OBSVirtualCam/CameraControlPanel.swift` now uses a continuous native slider and rounds the binding value to the requested increment. Keep that distinction if adding new controls: quantize the value in the binding instead of passing a fine step to the native slider over a large range. If a similar freeze returns, capture the process with `sample <pid> 20 -file <path>` while actively resizing; an idle capture misses the relevant stack.
