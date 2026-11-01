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

## Calendar alarm source build (2026-11-01)

- `./lokidot test`: 61 XCTest cases passed, including 13 calendar scheduler cases; all 8 staged-update verification checks passed.
- `./lokidot build`: app, ZIP, and current-user Mac PKG built successfully on Apple silicon. The app's strict code-signature verification passed; all four bundled packs validated. The sandboxed attempt compiled but icon packaging failed; the normal host build completed.
- Live Mac check: `lokidot calendars` opened the calendar window without a permission prompt. Alarms were off, event titles hidden, and the enable control disabled until permission. **Try a pet alarm** displayed the nonactivating test card; **Dismiss** removed it. No calendar event was created.
- Calendar tests use synthetic events and cover recurrence, moved occurrences, Apple/Google calendar selection, snooze across restart, cancellation/removal, expiry, duplicate prevention, the two-minute catch-up limit, and DST fallback.
- Live Apple/Google event delivery remains to be checked after the owner connects calendars. No calendar permission was granted during verification, and no personal events were read. Sleep/session UI behavior is implemented but was not exercised by putting the owner's Mac to sleep.
- No Windows calendar integration or new public installer release is claimed by this change.

## Saved pet library source build (2026-11-01)

- All 71 XCTest cases passed, including 10 new library cases. All 8 staged-update checks also passed. The Mac app, ZIP, and PKG built; all four bundled packs validated.
- Live Mac check with a synthetic Library Test Pet: imported it, moved the original folder, quit and reopened the app, and verified the saved pet was selected and running. No original-path dependency remained.
- Unload pet changed its status to Unloaded; that state survived a restart. Load pet restored it. Whole-pack mode included loaded imports. Put pets away cleared the overlay and remained in effect after another restart.
- Remove saved copy showed a confirmation and moved only the synthetic managed copy to Trash. The saved-pet list no longer contained it; the moved original still passed the sprite validator. The existing personal imported pack was preserved and migrated into the library.
- Library tests cover canonical deduplication, identical manifest IDs with different artwork, original-file preservation, failed Trash operations, symlink/foreign-path rejection, broken entries, damaged-copy preservation, and private storage permissions.
- The library implementation and live checks are Mac-only. No Windows persistence behavior or new public installer version is claimed.
