# Changelog

## 1.1

- Preserve the overlay, Metal renderer and current pose during sleep instead of destroying them.
- Ignore duplicate wake notifications and display notifications that do not change the screen geometry.
- Apply the first fresh lid angle immediately after wake.
- Keep the last real frame briefly while capture resumes; recover a failed stream separately from the window.
- Add a sleep/wake handler regression check using live capture and the physical sensor.

## 1.0

- Read the physical lid-angle HID sensor.
- Capture the built-in desktop with ScreenCaptureKit and exclude the app from capture.
- Render perspective, progressive Gaussian blur, upper-edge feathering and shadows through Metal.
- Add menu-bar controls, angle calibration, JSON settings and diagnostic commands.
