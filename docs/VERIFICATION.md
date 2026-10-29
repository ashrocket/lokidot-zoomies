# Verification

Version 1.2 adds a common SpritePack loader used by the standalone CLI, app importer, and build gate. It supports a flexible three-state Zoomies pack and the complete pet-v2 atlas. Unknown fields, executable hooks, URLs, path traversal, symlinks, nonregular files, corrupt or truncated PNG containers, invalid checksums, empty frames, opaque backgrounds, oversized data, bad grids, overlaps, and missing states are rejected.

## Automated checks

**25 XCTest cases passed with zero failures** on an Apple Silicon Mac using the installed Swift compiler. Tests generate synthetic image data and cover:

- Route bounds, closure, heading, pacing, invalid progress, and multiple display geometries.
- Wide and tall custom artwork, plus three staggered route phases without discontinuities.
- Complete native packs with different direction counts and rates; canonical packaging and round-trip loading.
- Complete v2 packs with all 73 poses, required state/count mappings, and transparent unused cells.
- The malformed, incomplete, corrupt, and unsafe inputs listed above.

## Build and CLI integration

All three ready default packs, Robot Loki, Beagle, and Whippet, passed the actual standalone validator.

The validator returned exit 0 for a complete synthetic pack and exit 1 with an actionable missing-direction error for an incomplete pack. The same incomplete pack failed the build gate and left the existing archive and app-path file unchanged.

A customized Sample app compiled successfully, used its declared display name and bundle id, contained only the normalized manifest and PNG from the input folder, passed strict code-signature verification, and exported three GIF previews without opening a desktop window. Unrelated input files were not bundled.

The default app compiled successfully, packaged all three ready characters, and passed strict code-signature verification. The build operates in a new staging directory and does not replace or quit a running app.

## Runtime behavior and limits

The version 1.2 app was opened with --all-ready on the connected Apple Silicon Mac. Its own diagnostics reported three characters, a visible click-through window, an active lap animation, and gentle repeat enabled. Native window captures taken at different times showed Loki, Beagle, and Whippet together, with changed positions and running poses, followed by their resting poses. The app was left running. Individual menu interactions still require separate desktop verification.

All ready characters share one click-through panel and one Core Animation clock. Only one animation-completion callback schedules the group's rest timer. Character selection and imported folder choices are stored locally. No current Dot-avatar state is changed.

The structural validator cannot prove artistic identity, gait quality, correct gaze, or smooth semantic transitions. Beagle's visual-review notes about approximate intermediate gazes and two direction transitions are retained in ARTWORK.md. In-place circling and prancing-hop playback are planned follow-up work and are not implemented.

Physical multi-display hot-plug, VoiceOver interaction, Intel execution, every supported macOS version, individual menu interactions, and Instruments frame-time or energy measurements remain unverified. No sustained FPS, memory, or energy-use claim is made.
