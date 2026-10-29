# Your dog gets a turn 🐾

You bring the dog photo. Your agent makes the animation pack. LokiDot lets them out to play.

A **sprite pack** is a folder containing a sheet of little dog poses and a file that tells LokiDot how to play them. You do not need to write that file yourself: the setup prompt below asks your agent to create it, make the artwork, check it, and show you a preview.

## The easy route: give your agent the job

1. **Pick a good photo.** Use a clear full-body side view with the ears, feet, and tail visible. A second view helps preserve markings. Have your dog's name ready.
2. **Copy the prompt.** Open LokiDot and click **Copy setup prompt**, or copy the complete block below. From Terminal, `lokidot dog-prompt | pbcopy` puts the same prompt on your clipboard.
3. **Paste it into your agent and attach the photo.** Use an agent with image-generation and file tools. Tell it the dog's name and any style preference, such as a tiny illustrated version. The prompt asks it to do the work, not just give you advice.
4. **Review your dog.** Ask the agent for the finished folder, a running preview, and a successful validator result. Check that the dog looks right and that both running directions move naturally. If you still see the teal practice character, the real artwork is not finished.
5. **Let them out.** In LokiDot, click **Add your dog…** and choose the finished **folder**, not the photo or PNG. Or run the exact `lokidot dog "..." circle` command your agent gives you.
6. **Keep their home.** Store the pack somewhere permanent. The app remembers that folder; if you move it later, import the new location.

The first pack supports **Big zoomies** and **Little circles**. **Happy prance** needs the full pet-v2 format with jumping artwork. The three bundled dogs already have those poses.

## Copy this whole prompt to your agent

Attach your photo in the same conversation. The app button and `lokidot dog-prompt` use the [plain-text version](../Resources/DogSetupPrompt.txt) of this prompt.

```text
Help me turn my dog into a LokiDot Zoomies desktop companion. Please do the setup, not just describe it.

Use the dog photo(s) I attach as the reference. Ask for my dog's name and a clear full-body photo if I haven't supplied them. A side view is best; a second view helps with markings. Keep the dog's actual coat, ears, tail, proportions, and personality. Ask only for information you need.

Project and format guide:
https://github.com/ashrocket/lokidot-zoomies
https://github.com/ashrocket/lokidot-zoomies/blob/main/docs/sprite-packs.md

Make a simple zoomies-v1 pack first. It supports Big zoomies and Little circles. Happy prance requires the separate, complete 73-pose pet-v2 format; do not promise it for this starter or add unsupported animation fields.

1. Find the app/launcher and make a new pack folder.
Use `command -v lokidot`, the project's `./lokidot`, or the helper at "$HOME/Applications/LokiDot Zoomies.app/Contents/MacOS/lokidot". If none is available, consult the repository's installation instructions and explain the missing prerequisite. Don't claim validation ran if you cannot run it.
Choose a new folder such as "$HOME/Pictures/LokiDot/Biscuit", replacing Biscuit with my dog's name. Avoid overwriting an existing pack. Run `lokidot new-dog "PACK_FOLDER" "DOG_NAME"` with the real launcher and paths. This creates a working practice sprite and manifest; the practice sprite MUST be replaced with my dog's artwork before calling the job finished.

2. Generate or draw the actual animation artwork.
Create one transparent RGBA PNG named atlas.png. Use a 4-column, 3-row grid of 256 x 256 pixel cells: exactly 1024 x 768 pixels overall. Rows run from the TOP. Keep every pose inside its own cell with transparent padding.
- Row 1: one relaxed idle pose in column 1; leave columns 2-4 completely transparent.
- Row 2: four consecutive frames of the dog running RIGHT, one per column.
- Row 3: four separately authored frames running LEFT, one per column.
The run should form a believable looping stride, not four identical poses. Keep body size, foot baseline, coat markings, and framing consistent. Preserve left/right markings; do not mirror one direction to manufacture the other. No painted checkerboard, background, ground, captions, borders, grid lines, or extra dogs. Use true transparency.
If an image tool misses the grid or transparency, repair the artwork and recheck it. If you cannot create image files, give me the exact image-generation brief and explain what is still missing; don't substitute the practice character or a photo for finished animation.

3. Finish manifest.json beside atlas.png.
Use schemaVersion 1, format "zoomies-v1", image "atlas.png", frameWidth 256, frameHeight 256. Give the dog a readable name (up to 40 characters) and a unique lowercase id starting with a letter (letters, digits, and hyphens only, up to 32 characters).
Use exactly these animation entries; their rows and columns are ZERO-based:
"idle": {"row":0,"column":0,"frameCount":1,"fps":1}
"running-right": {"row":1,"column":0,"frameCount":4,"fps":8}
"running-left": {"row":2,"column":0,"frameCount":4,"fps":8}
Preserve the starter's valid JSON structure. If you deliberately use a different cell size, update both frame dimensions to match the actual PNG grid. Do not add executable hooks, URLs, or extra manifest fields.

4. Validate, inspect, and let the dog out.
Run `lokidot validate "PACK_FOLDER"`. Fix errors until it exits successfully. Inspect every frame and an animated preview: the validator checks structure and transparency, not whether this looks like my dog or whether the feet move naturally.
Preview with `lokidot dog "PACK_FOLDER" circle`, then try zoomies. You can also export GIF previews using the app executable's `--pack "PACK_FOLDER" --render-preview "PREVIEW_FOLDER"` options.
If you cannot run the Mac app, say so and give me the exact local commands; don't claim live playback was verified.

5. Hand me the finished result.
Give me the exact pack folder, manifest.json, atlas.png, a preview, and the validation result. Explain: open LokiDot Zoomies, click "Add your dog…", and choose the FOLDER containing those two files. Keep it somewhere permanent because the app remembers that location. Include a correctly quoted launch command for my exact folder.
Only describe the dog as ready after its actual artwork is in place and validation has passed. Do not publish my photos or pack; I will decide if I want to share them.
```

## What “finished” looks like

Your agent should return a folder like this:

```text
Biscuit/
├── manifest.json   ← name, grid, and animation timing
└── atlas.png       ← transparent sheet of your actual dog's poses
```

It should also show a preview and the result of:

```sh
lokidot validate "$HOME/Pictures/LokiDot/Biscuit"
lokidot dog "$HOME/Pictures/LokiDot/Biscuit" circle
```

Replace the example path with the folder your agent actually created. The validator checks that the files, grid, frames, and transparency are usable. It cannot tell whether the drawing resembles your dog or the gait looks good. That last check is yours.

## If you want to draw it yourself

Create a practice pack:

```sh
lokidot new-dog "$HOME/Pictures/LokiDot/Biscuit" "Biscuit"
```

The starter is a small synthetic character, not a likeness of your dog. It uses a **256 × 192 pixel sheet**, with four columns and three rows of **64 × 64 pixel cells**. Replace its artwork.

The agent prompt instead requests a higher-resolution **1024 × 768 sheet** with **256 × 256 cells**. Both use the same layout. When changing cell size, set `frameWidth` and `frameHeight` in the manifest to match; do not stretch a sheet without updating its grid.

| Row, from the top | Draw this | Check |
| --- | --- | --- |
| 1 | One resting pose in the first cell; leave the rest empty | Recognizable silhouette at desktop size |
| 2 | Four consecutive poses running right | A looping stride, consistent feet and body size |
| 3 | Four separately drawn poses running left | Correct direction and coat markings |

Keep padding around each pose. Use real transparent RGBA PNG pixels, not a painted checkerboard. No captions, grid lines, or background scenery. See the [complete format rules](sprite-packs.md) before changing frame counts, timing, or layouts.

For prancing, start with the [pet-v2 template](../examples/pet-v2/manifest.json) and supply its complete 73-pose atlas. Adding a `jumping` field to the simple format is not enough. Gaze frames are eye/head poses, not a body turntable.

To export declared-state GIFs without opening a desktop overlay:

```sh
APP="$HOME/Applications/LokiDot Zoomies.app"
"$APP/Contents/MacOS/LokiDotZoomies" --pack "$HOME/Pictures/LokiDot/Biscuit" \
  --render-preview "$HOME/Pictures/LokiDot/Biscuit-previews"
```

For a choreography preview, use `--render-motion-preview` and `--motion circle` instead. It produces a GIF and a storyboard.

## If something looks wrong

| What happened | What to do |
| --- | --- |
| The importer cannot use my photo | Ask your agent for the finished pack folder. A photo is a reference, not an animation. |
| I still see the teal practice character | Have the agent replace the starter atlas with your dog's actual poses. |
| There is a rectangle or checkerboard behind the dog | Re-export with real alpha transparency. |
| The dog jitters, slides, or changes size | Align the feet and body across cells, then review the animated loop. |
| The validator reports missing or malformed frames | Give the exact error to the agent; have it repair and rerun validation. |
| Happy prance is unavailable | Use zoomies/circles, or commission a complete pet-v2 pack with jumping poses. |
| A previously imported dog disappeared after moving files | Import the pack again from its new permanent folder. |

## Share the joy

A pack consists of its manifest and PNG. Give it a unique id, a friendly name, and clear artwork rights. Include a running preview when proposing a bundled dog. PRs are welcome; keep unfinished art out of `Resources/Characters` so everyone else's build stays healthy.

Imported packs stay local. A distributed app that bundles your pack includes its artwork, so share only material you have permission to distribute.
