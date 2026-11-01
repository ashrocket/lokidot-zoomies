# Bundled artwork

The following assets were supplied for this open-source release and are included under the repository's MIT license. No signed URLs, account identifiers, Library identifiers, or private paths are stored in the source.

| Pack | Provenance | Status |
| --- | --- | --- |
| robot-loki | Owner-supplied original ivory-and-graphite robot-whippet sprite sheet; owner explicitly approved publication of the sheet and running GIF. | Complete pet-v2; all 73 required poses pass local structural validation. |
| beagle | Original illustrated Beagle artwork generated for this project; no external reference-image bytes copied. | Complete pet-v2; all 73 required poses pass local structural validation. |
| whippet | Owner-supplied line-drawing Whippet pack, imported from the provided sprite ZIP. Only the base PNG and running GIF are bundled; no source scripts are executed. | Complete pet-v2; all 73 required poses pass local structural validation; playback preserves the supplied 120 ms frame timing. |
| loki-vampire | AI-generated vampire-whippet artwork made for the owner; the owner explicitly requested its inclusion in this public repository on 31 October 2026. Only the validated atlas and manifest are included under the repository's MIT license. | zoomies-v1: idle plus four running poses in each direction. Supports zoomies and circles; no jumping poses. |

Beagle's prior visual review reported clear cardinal gazes, with approximate intermediate gazes and two direction transitions requiring further refinement. Those are semantic review notes, not guarantees made by the structural validator. Zoomies currently plays its left/right locomotion rows and first idle pose.

The Whippet ZIP also contains expansion sheets for turns, circles, prancing, play bows, skids, and settling. Those originals are preserved separately for later motion work; this release does not claim to play the expansion animations.

The synthetic Sample pack produced by scripts/make-sample-pack.sh is original test geometry, generated only on explicit request. It is never silently substituted for a user character. Other imported art retains its own license.

## App icon

`Resources/AppIcon/whippet-head.png` is original AI-generated whippet-head line art made for Zoomies on 31 October 2026 with the built-in image generation tool. The owner requested its publication in this repository under the same MIT license. It has a transparent background and contains no reference-image pixels. The build uses macOS `sips` and `iconutil` to package the standard and Retina sizes into `AppIcon.icns` before signing the app.
