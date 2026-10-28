# LokiDot Zoomies

A small native macOS desktop pet that plays your existing Loki sprite animation along a curved zoomies route: left, lower and right, down through a loop, then left and up again.

Version 1.1 uses the original sprite-sheet frames. The earlier substitute drawing has been removed. **This repository contains code only; personal avatar artwork stays on your Mac.**

## Build and run

Requires macOS 13 or later and Xcode 15 or later with its command-line tools selected. No packages or downloads are needed by the build.

```sh
git clone https://github.com/ashrocket/lokidot-zoomies.git
cd lokidot-zoomies
./scripts/test.sh
./scripts/run.sh
```

Without bundled artwork, find **🐾 Loki → Choose Loki Artwork…** and select your local PNG. The app waits quietly until artwork is loaded. The selection lasts for this session.

To include your own sheet in a private local build:

```sh
mkdir -p local-assets
cp /path/to/your/spritesheet.png local-assets/LokiSpriteSheet.png
./scripts/run.sh
```

Alternatively, set `LOKIDOT_SPRITESHEET` to a local PNG path when running the build script. The supported atlas has eight columns and eleven rows; a 1536 × 2288 sheet has 192 × 208 cells. Row 0 supplies six idle poses, row 1 eight right-running poses, and row 2 eight left-running poses. Frames retain their original registration, proportions, and sequence. Running playback uses 80 milliseconds per frame; resting uses a still idle pose.

`local-assets/`, `.build/`, and `dist/` are ignored by Git. A local app or ZIP built with artwork **does contain that private artwork**; the MIT code license does not grant rights to redistribute it.

`scripts/build.sh` creates an optimized app for the current Mac architecture, prints its temporary staging path, and saves `dist/LokiDot Zoomies.zip`. `scripts/run.sh` opens that app. For a permanent installation, unzip the archive and move the app to Applications in Finder. Staging outside synced folders keeps File Provider metadata from invalidating the local ad-hoc signature. The app is not Developer ID signed or notarized; respect any macOS security prompt. The scripts do not remove quarantine attributes or change security settings.

## Controls and behavior

- A 16-second lap starts when artwork is available. **Repeat gently** defaults to on, with 24 seconds of rest between laps. Uncheck it for a single lap.
- **Pause / Resume** freezes and resumes travel and running poses together. **Zoomies!** starts a lap when resting and cannot stack simultaneous animations.
- **Display** chooses a connected screen. The pet stays in its usable area, clear of the menu bar and Dock. Display changes recalculate the route.
- macOS **Reduce Motion** keeps the pet still and disables Zoomies. Screen sleep and inactive login sessions hide and pause it; waking resumes it unless it was manually paused.
- Quit with **🐾 Loki → Quit LokiDot Zoomies**. Quit intentionally has no keyboard shortcut. The menu keeps stable item positions while a lap finishes.

The overlay is transparent, nonactivating, and click-through above ordinary windows. It has no Dock icon, login item, network listener, telemetry, third-party dependency, Accessibility requirement, or screen-recording requirement. It does not change the existing Dot avatar or any other app.

## Implementation and checks

AppKit owns one panel. Core Animation composites original bitmap frames along precomputed position and orientation keyframes. Both authored running directions are used; changing direction never reverses the temporal frame sequence. There is no per-frame Swift timer. Resting removes all animations and uses one cancellable timer.

The route uses closed cubic Bézier curves, an arc-length lookup table, and smooth acceleration and deceleration. A conservative radius keeps the full banked sprite on screen, including its taller original frame geometry.

Eleven XCTest cases cover route bounds, continuity, direction, pacing, invalid progress, atlas row order, authored frame counts, cell boundaries, and malformed image dimensions.

```sh
./scripts/test.sh
./scripts/build.sh
# Export private animated previews without opening the desktop overlay:
"$(cat dist/app-path.txt)/Contents/MacOS/LokiDotZoomies" --render-preview local-assets/previews
```

The Swift package can also be opened in Xcode or tested with `swift test`. The direct compiler scripts avoid a package-manifest sandbox and external dependencies.

Optional `--spritesheet /path/to/sheet.png` overrides the bundled image. `--reduce-motion` exercises the still branch without changing system preferences. `--diagnostics /path/to/report.json` writes one local report after two seconds and never transmits it. Quit an existing instance before using launch flags.

See [verification notes](docs/VERIFICATION.md) for coverage and limitations.

## License

Original code is [MIT licensed](LICENSE). Avatar artwork is supplied separately by its owner and is not included in this repository. This is an independent desktop toy, not an official OpenAI app.
