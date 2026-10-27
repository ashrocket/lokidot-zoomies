# Verification

The initial release was built on Apple Silicon with Xcode 26.6 / Swift 6.3.3 and a macOS 13 deployment target.

## Automated checks

Seven XCTest cases pass, covering more than 30,000 on-screen poses, rotated artwork bounds across five display geometries, continuous start/end tangents, left-first choreography, arc-length pacing, smooth heading changes, monotonic easing, and invalid progress.

`scripts/test.sh` uses the installed XCTest frameworks and returns a failing exit code for any failing assertion or an empty test suite. `swift test` is an alternative outside environments that disallow nested package-manifest sandboxes.

## Runtime and visual checks

The native app was launched and its named overlay window and rendered running whippet were inspected through native computer-use screenshots. Both supplied whippet videos were accessible as motion references; no video assets were copied. The original drawing uses gathered/extended poses and paired-leg motion.

The implementation uses a non-key, non-main panel with `ignoresMouseEvents = true`, a floating window level, native menu items, and system Reduce Motion detection. No screen-reading or accessibility API is used by the app. Pause freezes the parent layer's clock; rest removes its animations. The only recurring behavior is a single rest timer between laps.

## Coverage limits

Physical multi-display hot-plug, VoiceOver interaction, the complete appearance/contrast matrix, and Instruments frame-time measurements have not been verified. Synthetic display geometries are covered by the tests. No measured frame-rate or energy-use claim is made. The macOS 13 minimum is a compile target; the app has not been run on every supported OS version or an Intel Mac.

A SwiftUI-oriented static scanner flagged the AppKit Reduce Motion API and the read-only `animation(forKey:)` diagnostic call. Both are scanner mismatches: this app uses `NSWorkspace.accessibilityDisplayShouldReduceMotion`, and its animation groups are explicit Core Animation objects.

The expressive profile applies to the mascot only; controls use ordinary AppKit menus. Provisional native-interface rubric: platform 13/15, layout 13/15, semantics 14/15, interaction 17/20, motion 13/15, accessibility 7/10, implementation 7/10 (84/100). This is capped by the unverified assistive-technology and performance coverage, not a claim of Apple endorsement.
