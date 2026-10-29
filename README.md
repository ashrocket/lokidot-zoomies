# LokiDot Zoomies

A small native macOS desktop pet. Bring your own complete sprite pack, validate it locally, and build a customized app. Pets run left, dip lower, race right, curve down through a loop, then sweep left and up.

**Version 1.2 includes a standalone sprite validator, a Character menu, and Show All Ready Characters.** Loki, Beagle, and the line-drawing Whippet are complete, validated defaults.

## Validate your sprites first

Requires macOS 13+ and Xcode 15+ with its command-line tools selected. No third-party packages, downloads, server, or account are needed.

```sh
git clone https://github.com/ashrocket/lokidot-zoomies.git
cd lokidot-zoomies
./scripts/validate-pack.sh /path/to/my-pet
```

A pack is a folder containing **manifest.json plus one transparent PNG**. The validator prints VALID and exits 0 only when the entire declared set passes. Invalid packs print a specific error and exit 1; incorrect command usage exits 2. The app importer and build use this same validator.

Choose a template:

- [zoomies-v1 manifest](examples/zoomies-v1/manifest.json): requires idle, running-right, and running-left. Declare your own cell size, frame counts, and playback rates.
- [pet-v2 manifest](examples/pet-v2/manifest.json): requires all nine standard animation rows plus sixteen look directions in a 1536 × 2288 atlas.

Copy the appropriate manifest into your pack folder, set id and name, and supply the PNG named by image. **No missing poses are invented, mirrored, or replaced with Loki.** See the [complete schema, limits, examples, and error guide](docs/sprite-packs.md).

For an explicitly synthetic, MIT-licensed test pack you can replace with your own artwork:

```sh
./scripts/make-sample-pack.sh local-assets/my-pet
./scripts/validate-pack.sh local-assets/my-pet
```

## Build and open

```sh
# Validate and bundle your own pet, name, timing, and app identifier:
./scripts/build.sh --pack /path/to/my-pet

# Or build the ready defaults:
./scripts/build.sh

# Open the app when you are ready:
open "$(cat dist/app-path.txt)"

# Start all three ready characters together:
open "$(cat dist/app-path.txt)" --args --all-ready
```

Builds fail before packaging incomplete packs. A successful build creates an optimized, locally signed app at the printed staging path and saves dist/LokiDot Zoomies.zip. Building does not quit, replace, or launch a running pet. Quit the older version deliberately before opening a replacement. scripts/run.sh accepts the same --pack argument and combines build with open.

For a permanent installation, unzip the archive and move the app into Applications using Finder. Staging outside synced folders prevents File Provider metadata from invalidating the ad-hoc signature. The app is not Developer ID signed or notarized; respect macOS security prompts. No script changes security settings or removes quarantine attributes.

A customized app includes the validated pack's name, frame timing, proportions, and a separate bundle identifier derived from its id. Its archive also includes the ready defaults. Arbitrary files alongside a manifest are not copied.

## Characters and controls

- **Character → Loki / Beagle / Whippet** selects a validated default.
- **Character → Show All Ready Characters** runs the ready defaults together in one transparent window, spaced along the same route. It becomes available with at least two ready defaults. Pause, repeat, Reduce Motion, and display selection apply to the group.
- **Character → Import Sprite Pack…** validates a local pack before switching. Invalid imports keep the current character. The chosen character or imported folder is remembered locally; a missing saved pack produces an error instead of silently substituting another pet.
- **Zoomies!** starts one lap while resting. A lap takes 16 seconds; **Repeat gently** defaults on with 24 seconds of rest between laps. Uncheck it for a single lap.
- **Pause / Resume** freezes travel and sprite playback together.
- **Display** selects a connected screen and keeps each pet inside its usable bounds.
- macOS **Reduce Motion** keeps all pets still. Screen sleep and inactive login sessions pause and hide the overlay.
- Quit with the **paw menu → Quit LokiDot Zoomies**. Quit has no keyboard shortcut.

The overlay is transparent, nonactivating, and click-through. It has no login item, network listener, telemetry, third-party dependency, Accessibility requirement, or screen-recording requirement. It does not change the existing Dot avatar.

## Ready artwork and previews

| Character | Full sprite pack | Running preview |
| --- | --- | --- |
| Robot Loki | [Atlas](Resources/Characters/robot-loki/atlas.png) · [manifest](Resources/Characters/robot-loki/manifest.json) | [GIF](docs/previews/robot-loki-running.gif) |
| Beagle | [Atlas](Resources/Characters/beagle/atlas.png) · [manifest](Resources/Characters/beagle/manifest.json) | [GIF](docs/previews/beagle-running.gif) |
| Whippet | [Atlas](Resources/Characters/whippet/atlas.png) · [manifest](Resources/Characters/whippet/manifest.json) | [GIF](docs/previews/whippet-running.gif) |

See [artwork provenance and review notes](docs/ARTWORK.md). User imports remain local unless you choose to distribute the built app or archive; those bundles contain the imported artwork. local-assets/, .build/, and dist/ are ignored by Git.

## Checks and previews

```sh
./scripts/test.sh

# After a build, export declared animations without opening an overlay:
"$(cat dist/app-path.txt)/Contents/MacOS/LokiDotZoomies" \
  --pack /path/to/my-pet --render-preview local-assets/previews
```

The tests generate synthetic PNG fixtures and cover complete and incomplete packs, v2 rows, malformed JSON, unknown fields, corrupt/disguised images, symlinks, path traversal, nonregular files, transparency, bounds, size limits, and multi-pet route phases. No private test artwork is required.

The validator checks structure and pixels, not whether a gait, expression, or look direction is artistically correct. Review the GIFs and all poses yourself. This desktop app currently plays the two locomotion rows and uses the first idle frame while resting. It validates and preserves the other v2 states for portability; it does not yet animate in-place circles or prancing hops.

The Swift package also exposes SpritePackTool for Xcode / swift run. Optional app flags are --pack, --all-ready, --render-preview, --reduce-motion, and --diagnostics. --all-ready starts the bundled characters together for this launch; it cannot be combined with --pack. Raw --spritesheet and LOKIDOT_SPRITESHEET imports have been replaced by manifest-based packs.

See [verification and current limits](docs/VERIFICATION.md).

## License

Original code, synthetic fixtures, and the bundled artwork supplied for this release are [MIT licensed](LICENSE). Other artwork you import retains its own license. This is an independent desktop toy, not an official OpenAI app.
