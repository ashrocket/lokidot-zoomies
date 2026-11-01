# Windows preview

The Windows app lives in `windows/LokiDot.Windows`; it does not change the Mac build. It targets .NET 10 WPF and publishes a self-contained x64 app for supported Windows versions. [.NET 10 is LTS through November 14, 2028](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core). Windows 11 x64 is the intended first manual-test target.

The packaging project names exactly six public artwork files: `manifest.json` and `atlas.png` for Whippet, Beagle and Robot Loki. Neither personal packs nor recordings are inputs. Runtime imports validate and hold a local snapshot in memory. They are not copied into the installation or published. There is no telemetry, update checker, networking or executable manifest field.

The preview provides the dog/all picker, Zoomies/Circle/Prance, Start, Pause/Resume, Repeat and Add your dog. A lap takes 16/8/7 seconds, followed by 24 seconds of rest when Repeat is checked. Motion uses a sampled closed Bézier route with distance easing, authored left/right crossfades and pet-v2 jump frames. Prance rejects any selected pack without authored jumping frames, with a useful error before replacing the current routine. Windows animation effects being disabled gives a stationary idle pose. The controller receives ordinary interaction; bank and squash transforms apply to an inner artwork Grid inside a padded square window, leaving the Window transform at identity; pet windows use transparent layered WPF windows, `WS_EX_TRANSPARENT`, `WS_EX_NOACTIVATE`, `WS_EX_TOOLWINDOW`, `HTTRANSPARENT` and `MA_NOACTIVATE`.

## Pack validation

The loader accepts schema 1 `zoomies-v1` and `pet-v2`, rejects missing, duplicate and unknown fields, and never interprets data as commands. It bounds JSON to 32 KiB and PNG to 16 MiB, checks PNG signature, chunk checksums, single-image/non-APNG structure and final end marker before decoding. Dimensions are limited to 4096 per side and 8,388,608 pixels total, with 8–512 pixel cells. Declared frames must fit the grid without overlap, contain visible pixels and a fully transparent background pixel. pet-v2 requires the exact 1536 × 2288 grid, row/count mapping and transparent unused cells. FPS is 0.5–30; frame counts are 1–64 for idle and 2–64 otherwise.

The image must be a plain PNG filename. Selected folders and parents cannot be reparse points. Directory/file handles exclude delete sharing during reads; file opens use `FILE_FLAG_OPEN_REPARSE_POINT`, reject non-disk/reparse/directory files, and compare resolved file paths with the held folder. Only bounded regular-file snapshots reach the decoder. Broken paths, corrupt data and missing files produce import errors.

## Build and installer

Run from the repository root on Windows with the .NET 10 SDK:

```powershell
./windows/build.ps1
./windows/test-installer.ps1
```

`build.ps1` publishes `win-x64` with the runtime, uses fresh per-run staging, checks exactly three public pack directories and six files recursively (rejecting nested directories, links and reparse points), and creates `windows/artifacts/LokiDot-Zoomies-win-x64.zip`, `.msi` and `SHA256.txt`. Complete outputs remain in `windows/artifacts/runs/<id>`; `publish-path.txt` and `run-path.txt` identify the current successful build for verification. Stable download copies are written only after both packages succeed, and earlier run directories are preserved. The MSI uses ordinary Windows Installer components, a Start Menu shortcut and major-upgrade detection. It installs per machine under Program Files and requires elevation. It has no services, autostart, Burn bootstrapper, extensions or custom executable install actions. Removing the MSI removes its installed files, shortcut and registry marker. The portable ZIP needs no installer. Neither artifact is code signed in this preview.

The build tool is deliberately pinned to [WiX 5.0.2's official release](https://github.com/wixtoolset/wix/releases/tag/v5.0.2) and [NuGet package](https://www.nuget.org/packages/wix/5.0.2), whose [source license is MS-RL](https://github.com/wixtoolset/wix/blob/v5.0.2/LICENSE.TXT). This tool predates the WiX 6/7 maintenance-subscription terms. It runs only at build time; no WiX runtime is installed. `--allow-roll-forward` lets the .NET tool use the installed SDK runtime. Official [Files harvesting](https://docs.firegiant.com/wix/schema/wxs/files/) supports the recursive payload syntax used here.

WiX 5's [consumer security servicing ended February 5, 2026](https://docs.firegiant.com/wix/). This pinned tooling is a preview limitation that needs a supported packaging decision before production distribution. It is not claimed to be current or supported. Newer WiX adoption must consider its published terms rather than silently upgrading this pin.

## Verification and remaining acceptance

`.github/workflows/windows.yml` runs on `windows-2025`, builds both downloads, runs the portable app's `--self-test`, installs the MSI on a clean runner, repeats the installed app's self-test, launches its normal entry point, closes it normally and uninstalls. Nonzero results fail CI. Installer logs, test receipts and render PNGs are uploaded even when checks fail; download artifacts are published only after the checks pass.

Self-test covers all bundled packs, valid zoomies-v1 input, unknown/executable/duplicate/missing JSON fields, filename traversal, frame/fps/overlap/extent limits, empty/opaque cells, PNG corruption/truncation/trailing/size limits, bounded local loads and a junction rejection fixture. Motion is sampled across landscape, portrait and small bounds for finite, bounded positions and closed endpoints. Self-test also rejects simple-pack Prance, including mixed All dogs selections. WPF smoke checks create the controller and pet, save offscreen render images, inspect rendered alpha, verify the nonidentity artwork transform and unclipped padded bounds across routines/screen fixtures, and read native no-activate/click-through flags. MSI checks confirm installed files and Start Menu shortcut, app startup and normal exit, and removal of files/shortcut/registry marker.

These are automated checks, not proof that pixels look correct on a real desktop or that clicks pass through to another application. Review uploaded screenshots, then manually test motion, actual focus preservation/click-through, Pause/Resume, rest timing, reduced motion, imported packs, scaling, fullscreen behavior and uninstall on a Windows desktop. The first preview uses the primary work area captured at Start, does not persist settings/imports, and does not include Mac menu-bar or movie-export features. Mixed DPI and display changes during a routine remain unverified. No Windows compilation or execution is claimed from a macOS-only static review.
