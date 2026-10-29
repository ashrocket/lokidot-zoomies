# Verification — v1.3.0

Verified on the connected Apple Silicon Mac on 29 October 2026.

## Automated checks

**34 XCTest cases passed with zero failures.** They cover the existing strict SpritePack loader and route, plus the new motion routines and local launch requests:

- Closed paths, smooth endpoints, pacing, finite headings, portrait/offset/tiny display bounds, and three performer phases.
- Compact circles that use both authored directions, upright nonzero-width turns, six grounded prance hops, and safe invalid progress.
- Round-trip control URLs, local paths containing spaces/Unicode/query punctuation, and rejection of unknown or duplicate fields and ambiguous selections.
- Complete simple and 73-pose pet-v2 packs; image/grid/frame validation; corrupt, incomplete, oversized, nonregular, symlinked, escaping, or executable inputs.

All three bundled packs—Loki, Beagle, and Whippet—passed the actual validator with their five authored jumping poses. The original structural and custom-pack coverage is retained.

## Launcher and installation

The native app and bundled launcher compiled successfully. The app and both bundled helpers passed code-signature verification in the test build. The launcher reported version 1.3.0. The final app was installed in ~/Applications with its symlink in ~/.local/bin; both the installed launch command and playground opened successfully. The bundled setup prompt matched the canonical resource and the full guide exactly, and the native Copy setup prompt button confirmed a successful clipboard write.

A temporary installation with spaces in both app and command paths worked from outside the checkout. The symlink resolved its own app correctly. A custom starter folder containing spaces and `&` was created and validated; asking that simple pack to prance failed with an actionable missing-jumping-poses message. Existing pack contents were preserved on a repeated creation attempt. The installer refused an unrelated command and an unrelated file at the app destination, preserving both.

## Motion and desktop evidence

The playground opened as a normal Mac window with the whole pack selected and the three move choices. Commands launched prancing, paused it, and reported the running process. A native overlay capture showed all three dogs together using their jumping artwork.

The offscreen exporter rendered [little circles](previews/all-dogs-circle.gif) and [happy prancing](previews/all-dogs-prance.gif) using the same MotionRoutine poses as the live compositor. Six-frame storyboards were inspected for all three dogs. These are choreography previews, not frame-rate benchmarks.

All performers share one click-through panel, one Core Animation clock, and one completion callback. The existing sleep, display, pause, and Reduce Motion handling remains in place. A debugger check observed a normal Quit action from the paw menu, with no crash. The red window-close button removed the playground while leaving the overlay available.

## Limits

The validator cannot prove a dog's identity, artistic quality, or gait realism. The agent setup prompt explicitly requires actual dog artwork and visual review, and identifies any unperformed validation or playback check. The simple pack supports runs and circles; prancing requires a complete pet-v2 pack.

Physical multi-display hot-plug, VoiceOver interaction, Intel execution, every supported macOS version, and Instruments frame-time or energy measurements remain unverified. No sustained FPS, memory, or energy-use claim is made. The app is locally signed, not Developer ID signed or notarized.
