# Sprite packs and the standalone validator

A sprite pack is one local directory containing manifest.json and one PNG. No ZIP extraction, URLs, scripts, plugins, hooks, or executable manifest fields are supported. Unknown JSON fields are rejected.

## Commands

```sh
./scripts/validate-pack.sh /path/to/pack
./scripts/build.sh --pack /path/to/pack
```

The first command is a standalone CLI; it does not open an app or modify your pack. It compiles the dependency-free validator using the installed Swift compiler. After compilation, you can call .build/native/SpritePackTool validate /path/to/pack directly. Both use the same SpritePack loader as the app and build gate. Exit 0 means valid; invalid input exits 1; wrapper usage errors exit 2. A failed build leaves the previous dist/app-path.txt and ZIP intact.

## Schema 1: flexible Zoomies pack

Copy [examples/zoomies-v1/manifest.json](../examples/zoomies-v1/manifest.json). Its example describes a 256 × 192 PNG containing four columns and three rows of 64 × 64 cells.

```json
{
  "schemaVersion": 1,
  "format": "zoomies-v1",
  "id": "your-pet",
  "name": "Your Pet",
  "image": "atlas.png",
  "frameWidth": 64,
  "frameHeight": 64,
  "animations": {
    "idle": {
      "row": 0,
      "column": 0,
      "frameCount": 1,
      "fps": 1
    },
    "running-right": {
      "row": 1,
      "column": 0,
      "frameCount": 4,
      "fps": 12.5
    },
    "running-left": {
      "row": 2,
      "column": 0,
      "frameCount": 4,
      "fps": 12.5
    }
  }
}
```

Required root fields:

| Field | Meaning |
| --- | --- |
| schemaVersion | Exactly 1 |
| format | zoomies-v1 or pet-v2 |
| id | 1–32 lowercase letters, digits, or hyphens; starts with a letter. Choose a unique id for a separately customized app. |
| name | 1–40 printable characters without slashes; shown in the menu and customized app metadata. |
| image | One plain PNG filename inside the same folder. No paths, URLs, hidden files, or symlinks. |
| frameWidth, frameHeight | Common cell dimensions, each 8–512 pixels. Preserve consistent registration and scale inside every cell. |
| animations | The complete set required by the chosen format, and no unknown states. |

Each animation declares row, column, frameCount, and fps. Row and column start at zero at the image's top-left. Frames run left-to-right and wrap to the next row if necessary. Each state owns distinct cells; overlap is rejected. fps is 0.5–30; frameCount is 1–64 for idle and 2–64 for other states. Left and right counts and speeds may differ. Directions must be authored correctly; the renderer does not mirror or reverse their temporal sequence.

zoomies-v1 requires exactly idle, running-right, and running-left. The app holds idle frame 1 during rest to save energy; any additional idle frames are preserved and included in exported previews.

## Complete pet-v2 import

Copy [examples/pet-v2/manifest.json](../examples/pet-v2/manifest.json) beside an existing v2 PNG. Change id, name, and image as needed. Geometry and counts are fixed for this profile:

- PNG: **1536 × 2288**, eight columns and eleven rows.
- Cell: **192 × 208**.
- Required occupied cells: **73**. All fifteen unused cells must be transparent.

| Row (zero-based) | Manifest state | Required frames | Meaning |
| --- | --- | --- | --- |
| 0 | idle | 6 | Idle poses |
| 1 | running-right | 8 | Locomotion to screen-right |
| 2 | running-left | 8 | Locomotion to screen-left |
| 3 | waving | 4 | Greeting |
| 4 | jumping | 5 | Jump |
| 5 | failed | 8 | Failure reaction |
| 6 | waiting | 6 | Waiting |
| 7 | running | 6 | Task work / thinking, **not locomotion** |
| 8 | review | 6 | Review |
| 9–10 | look | 16 | Clockwise look directions |

Every state starts at column 0. look starts at row 9 and wraps across row 10. Its order is 000, 022.5, 045, 067.5, 090, 112.5, 135, 157.5, 180, 202.5, 225, 247.5, 270, 292.5, 315, 337.5 degrees. 000 means up, 090 screen-right, 180 down, and 270 screen-left. The look fps is used for the exported contact-animation GIF only; the desktop pet does not currently track gaze.

This format accepts any character design. It does not require Loki's proportions, colors, species, or illustration style.

## Pixel and file limits

- Manifest: at most 32 KiB; ordinary JSON with the documented fields and numeric types.
- Image: one static, decodable PNG, at most 16 MiB. Renamed JPEGs and animated PNGs are rejected.
- Atlas: at most 4096 pixels on either side and 8,388,608 pixels total. Dimensions must divide evenly into the declared cells.
- Every declared frame must contain visible pixels and at least one fully transparent pixel. Solid rectangular backgrounds and blank poses fail.
- Frames must stay inside the atlas and must not overlap another state. pet-v2 additionally requires every unused cell to be completely transparent.
- Manifest and PNG must be regular local files. Symlinks, pipes, nested paths, absolute paths, and URL references are rejected. The loader opens files relative to the selected directory without following file symlinks.
- Only the validated PNG snapshot and normalized manifest are bundled. Extra files in your input folder are not copied or executed.

## Error examples

| Error | Fix |
| --- | --- |
| Missing required animation(s): running-left | Supply the complete left-facing row and declare it. |
| running-left frame 2 is empty | Add the missing pose to the second declared cell. |
| frame has no transparent background | Export RGBA PNG with transparent space around the pet. |
| frames extend beyond the PNG | Correct row/column/count or enlarge the atlas. |
| overlaps another declared animation | Give each state its own cells. |
| image must be a plain PNG filename | Put the image beside manifest.json and use atlas.png, not a URL or ../ path. |
| pet-v2 look requires row 9, column 0, frameCount 16 | Supply both look rows in the fixed clockwise order. |

A structural pass cannot prove natural gait, consistent identity, correct gaze, or absence of visual popping. Inspect every pose and the exported GIFs. Pets-service upload and its semantic-quality checks are separate from this standalone desktop app.

## Adding a ready default

Place a complete canonical pack at Resources/Characters/your-pet/ with image set to atlas.png, then validate it. Add a licensed preview and provenance in docs/ARTWORK.md. The next build validates every default before packaging; runtime validates again and lists only ready packs with unique ids. Incomplete or duplicate defaults are unavailable. Keep unfinished artwork outside Resources/Characters.

The Character menu remembers the chosen id, or the local folder for an imported pack. Show All Ready Characters displays the validated defaults in one window with staggered route phases. Selecting one character returns to individual mode.

## Future motion work

Tight in-place circles and small prancing hops need suitable turning and jumping poses plus motion review. Current v2 look frames represent gaze, not a body turntable. Do not use them as an upside-down rotating dog or claim expanded motions are implemented. Those motions are a follow-up after the three-character demo.
