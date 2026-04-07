# Playback Cam

Playback Cam is a SwiftUI iOS app for recording and reviewing motion on the spot. It is built around two camera workflows:

- `Slow-mo recording`: Record a clip, review it immediately, then play it back at `0.25x`, `0.5x`, or `1x`.
- `Delayed playback`: Watch the camera feed with a configurable delay of `1`, `2`, `5`, `10`, or `20` seconds.

After recording, the app can save a retimed version of the clip to the system Photo Library and show saved clips in an in-session gallery where they can also be deleted again.

## Features

- Back-camera capture with wide and ultra-wide selection when available
- Immediate review flow after recording
- Frame stepping, scrubbing, and variable playback speed
- Delayed playback mode for movement review without recording
- Session gallery for clips saved during the current app session
- Photo Library save and delete support
- iPhone and iPad layouts with orientation-aware playback UI

## Permissions

The app requests only the permissions it needs:

- `Camera`: Required to capture live video and record clips
- `Photo Library (Add Only)`: Required to save clips to Photos
- `Photo Library (Read/Write)`: Required only when deleting saved clips from Photos through the in-app gallery

If camera access is denied, the app shows a prompt that links to iOS Settings.

## Screenshots

### iOS
<p float="left">
  <img src="/Resources/Screenshots/ios-slowmo.png" width="250" />
  <img src="/Resources/Screenshots/ios-delayed.png" width="250" />
  <img src="/Resources/Screenshots/ios-playback.png" width="250" />
</p>
