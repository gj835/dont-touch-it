# Don't Touch It

A native macOS menu bar prototype for testing touch interception on macOS 27.

## Build

Requires macOS 27 and the Swift toolchain.

```sh
./Scripts/build-app.sh
open "dist/Don't Touch It.app"
```

## Test with Sidecar

1. Connect an iPad with Sidecar using macOS 27 and iPadOS 27.
2. Move a normal Mac app window to the iPad display.
3. Launch Don't Touch It and choose **Start Touch Guard** from the menu bar.
4. Touch the iPad screen over a control in the underlying app. Check whether the red warning appears and whether the underlying control remains inactive.
5. While Touch Guard remains active, test mouse clicks, trackpad clicks, drags, and scrolling on the underlying app.
6. Verify that mouse and trackpad input still operates the underlying app while Touch Guard is active. The **Pointer events** counter should increase.
7. Stop Touch Guard from the menu bar.

Touch Guard keeps its overlay touch-sensitive while idle. When a mouse or trackpad button or scroll event arrives, an Input Monitoring event tap briefly makes the overlay transparent to mouse events. It delays the initial event so the WindowServer can apply that change first; during the delay it keeps only the latest drag position or queues the initial scroll events. Subsequent drag and scroll events pass through the original stream without per-event replay delays. Trackpad gesture events (pinch, rotate, smart zoom, swipe, and pressure) are also watched: while they keep arriving, the overlay stays transparent for 400 ms after the last one, and the events themselves are not delayed or replayed. The app needs Input Monitoring and Accessibility (Post Event) permissions for this routing. Local builds use a stable code-signing identifier. Sidecar can validate AppKit direct-touch gesture recognition and mouse pass-through; it does not validate the built-in touchscreen's device or HID routing.

Touch Guard's local diagnostic log is stored at `~/Library/Logs/Don't Touch It/TouchGuard.log`. It records permission checks, guard start/stop, per-session touch and pointer counts, and generic errors. It does not record individual touch times, pointer coordinates, application names, process or window IDs, window titles, screen contents, or typed input, and the app does not upload the log. The file is capped at 256 KiB; it is cleared and reused when the cap is reached. Older logs from the previous, more detailed format are cleared the first time this version opens the log. Use **Reveal Touch Guard Log…** to view it or **Clear Touch Guard Log…** to delete it.

## Current prototype limits

- The touch warning uses a short-duration press recognizer as an early prototype; measure its response time and whether it suppresses the underlying action on device.
- Mouse and trackpad pass-through briefly makes the overlay ignore pointer events and re-posts only the initial event when needed. Verify that direct touches are recognized while idle and that clicks, drags, scrolling, full-screen apps, and multiple displays work as expected.
- The warning overlay uses a high window level and joins full-screen spaces. Test normal window use and system gestures before relying on it.
- The prototype does not disable the system touch hardware.
- Custom warning images are loaded from a local file path in the current user account.
