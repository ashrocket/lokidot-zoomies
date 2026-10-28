# Verification

Version 1.1 replaces the procedural substitute with playback of the owner's existing atlas. The original downloaded PNG remains outside public Git. Its visible eight-frame left/right running rows and six-frame idle row were inspected before integration. No live inspection of the Dot application was performed because the computer-use tool disallows that app.

## Automated coverage

Eleven XCTest cases cover more than 30,000 sampled poses across ordinary, portrait, tiny, and offset display geometries; the taller 144 × 156 artwork bounds; route closure and continuous heading; left-first choreography; arc-length pacing; smooth easing; invalid progress; atlas row order; exact authored frame counts; invalid image dimensions; and cell boundaries.

`scripts/test.sh` uses installed XCTest frameworks and fails for a failing assertion or empty suite. The build uses the installed Swift compiler and verifies the resulting ad-hoc code signature. The target is macOS 13, with native architecture selected at build time.

## Observed result

The corrected build compiled successfully, passed all eleven tests, and passed strict code-signature verification. The original atlas bytes in the local bundle match the downloaded source. Native screenshots showed the actual robot-whippet sprite at different positions and running poses on the route, and Activity Monitor confirmed the app process.

## Runtime design

The panel cannot become key or main and has `ignoresMouseEvents = true`. Pause freezes its parent layer clock. Rest and Reduce Motion remove animations. Menus keep their item identities while animation state changes, and Quit has no keyboard shortcut. The application delegate is retained for the whole event loop, and closing an overlay window does not terminate the menu-bar app.

An earlier instrumented desktop run completed two laps and then logged the explicit Quit action followed by normal termination. That was not evidence of a spontaneous animation crash; the source of the Quit input was unknown. No attempt is made to override a user choosing Quit.

## Coverage limits

The original Dot application's live playback timing cannot be compared through the available UI tool. This app preserves the supplied frames and uses an explicit 80 ms frame interval. Physical multi-display hot-plug, VoiceOver interaction, the full appearance/contrast matrix, Intel execution, every supported macOS version, and Instruments frame-time measurements remain unverified. No sustained FPS or energy-use claim is made.
