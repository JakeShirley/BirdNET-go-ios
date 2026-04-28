---
name: swift-visual-simulator-testing
description: "Use when: visually testing Swift, SwiftUI, iOS UI, station management, navigation, forms, layout, or simulator changes with xcodebuild, simctl, screenshots, and manual visual inspection in the Xcode Simulator."
argument-hint: "Swift/iOS UI change to verify"
---

# Swift Visual Simulator Testing

Use this skill when a Swift or SwiftUI change affects visible iOS behavior, layout, navigation, forms, text, empty states, toolbar items, tab selection, colors, assets, launch behavior, or any user-facing screen.

## Procedure

1. Build the app for the known simulator destination.

   ```sh
   xcodebuild -project src/Onpa.xcodeproj -scheme Onpa -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
   ```

2. Confirm the build succeeded by checking the tail of the build output for `** BUILD SUCCEEDED **`.

3. Install the freshly built app on the booted simulator.

   ```sh
   xcrun simctl install 5F8AE900-844B-4FDF-8B63-368C7751A4FE build/DerivedData/Build/Products/Debug-iphonesimulator/Onpa.app
   ```

4. Launch the app. For a specific tab, use the debug launch argument supported by the app shell.

   ```sh
   xcrun simctl launch --terminate-running-process 5F8AE900-844B-4FDF-8B63-368C7751A4FE org.odinseye.onpa --args -initialTab dashboard -debugShowStationManagement
   ```

   Supported tab values are `dashboard`, `feed`, and `species`. `stats` and `station` remain accepted as legacy aliases for `dashboard`.

5. Capture a screenshot into `build/screenshots/` with a filename that names the feature or task.

   ```sh
   xcrun simctl io 5F8AE900-844B-4FDF-8B63-368C7751A4FE screenshot build/screenshots/<feature-name>.png
   ```

6. Use the image viewer tool to inspect the screenshot. Check for:

   - blank or partially rendered screens
   - clipped text or labels that do not fit their controls
   - overlapping rows, buttons, titles, or tab bar elements
   - disabled controls that look active, or active controls that look disabled
   - incorrect initial tab, navigation title, toolbar, or empty state
   - asset, SF Symbol, tint, contrast, or spacing regressions
   - content hidden behind the tab bar, safe areas, Dynamic Island, or keyboard

7. If the visual result is off, make the smallest UI fix, rebuild, relaunch, and capture a new screenshot before reporting completion.

## Notes

- Prefer a fresh simulator screenshot over reasoning from SwiftUI code alone.
- If `simctl` cannot inject taps, add or use a narrow debug launch argument rather than relying on macOS assistive-access automation.
- Keep screenshots under `build/screenshots/`; this path is ignored by the repo's Xcode/build ignores.
- Mention any simulator or automation limitation in the final answer.