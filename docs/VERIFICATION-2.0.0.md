# Version 2.0.0 verification

Verified on the owner's MacBook Pro (M1, MacBookPro17,1, 8 GB of memory, macOS 26.7.2, build 25G330) on 3 November 2026.

## Build and tests

The 2.0.0 source is on branch `claude/lean-whippet-reminders`, after commit `1566992`. The installed app in `~/Applications` is the last build of that source. No source, resource, script or test file was changed after that build. The three program files in the installed app are byte-identical to the build output:

| File | SHA-256 |
| --- | --- |
| `LokiDotZoomies` | `13086c8840aea0091a71c05b946ea4f504be8875ff9b8a0887a29e7cec85aa19` |
| `lokidot` | `f895d11ee1ab4a3ab54b258c12b8eae48dd6a03614f4ace61d90615872457145` |
| `SpritePackTool` | `9068b8d2659feeacfb2ca8baa5cf9b9597721dd7b7e2e0b4fd9e3c343791ada0` |

All 124 XCTest cases passed with zero failures. All 8 staged-file checks of the update flow passed. The installed app passed `codesign --verify --deep --strict`. The signature is ad hoc.

## Resource use

The measured values are in [Calendar reminders: Resource use](calendar-alarms.md#resource-use). This section tells how they were measured.

- **Counters.** CPU time, wakeups, energy and memory come from the kernel's counters for each process (`proc_pid_rusage`). Memory is the physical footprint, which is the value in the **Memory** column of Activity Monitor. Resident size (RSS) was not used, because it does not include compressed memory.
- **No pauses.** Some tools (`footprint`, `vmmap`, `heap`) pause the app while they read it. These tools were not used during a measurement period.
- **Periods.** Each CPU test is 10 minutes of idle after a fresh launch and 150 seconds to settle, with one `top` sample each minute.
- **Reference processes.** The Dock, ControlCenter, SystemUIServer, Finder, NotificationCenter and Spotlight were read at the same times.
- **Calendar link.** The reminders-on test used a real Google Calendar link (the public US holidays calendar) and a local test file with two test meetings.
- **After-use memory.** A script opened the paw menu, showed a reminder card with sound and a lap, and opened and closed the settings window. It read the memory after each step.
- **Minimum.** A test app with only a menu-bar icon uses 9.0 MB on this Mac. That is the lowest value for this type of app.
- **Sound.** In a test app, `NSSound` added 2.69 MB, and the macOS sound service added 0 MB. After a reminder card with sound, the running 2.0.0 app had zero Core Audio HAL client (`HALC`) objects.- **Comparison with 1.3.2.** The installed 1.3.2 app used 67 MB, and 46 MB of that was decoded artwork.

## App size on disk

| | 1.3.2 | 2.0.0 |
| --- | --- | --- |
| Whole app | 7.19 MB | 8.45 MB |
| Program files | 1.34 MB | 2.59 MB |
| Dog artwork | 5.42 MB | 5.42 MB |

Both versions are optimized builds for Apple Silicon only. The program files are larger because of the reminder feature.

## Raw evidence

The raw logs, the measurement tools and the verbatim tool output are in `evidence/2026-11-03-resource-use/`. The repository ignores `evidence/` folders, so this folder stays on the Mac where the tests ran. Its `README.md` tells which file supports each value.

## Limits

- Each test was done one time, on one Mac.
- CPU and memory with Apple Calendar connected were not measured.
- An Outlook link was not tested live. The Google link was.
- Intel Macs, other macOS versions and the Windows build were not verified.
