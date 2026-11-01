# Zoomies project guidance

- Keep changes scoped and preserve personal sprite packs outside the repository. Adding an app icon does not authorize publishing a user's dog pack or recording.
- The owner explicitly approved the bundled `loki-vampire` atlas and manifest for public inclusion. This permission does not extend to other personal packs, reference photos, or recordings. The vampire supports zoomies and circles; whole-pack prance must report the missing jumping artwork clearly.
- Update clients use only this repository's stable GitHub releases and require explicit consent before downloading or launching an installer. Keep exact asset/repository validation, bounded transfers, SHA-256 checks, private staging, and normal OS security prompts. Never silently execute updates. Test both platforms' negative update fixtures before release.
- A release includes the versioned Mac PKG used by the updater, the stable `LokiDot-Zoomies-macos-arm64.pkg` README alias, the Windows MSI, ZIPs, and portable SHA-256 checksums. Keep the README download links working without authentication.
- Build the app, distribution ZIP, and current-user macOS PKG with `./lokidot build`; use `./lokidot test` for the existing XCTest suite. Read `scripts/build.sh`, `scripts/package-macos.sh`, and `scripts/install.sh` before changing packaging or installation.
- `LOKIDOT_BUILD_ROOT` and `LOKIDOT_MODULE_CACHE` can place build output and compiler caches in an explicit local directory. Do not build inside synced folders.
- App icon source lives in `Resources/AppIcon/whippet-head.png`. The build produces the ICNS sizes with macOS tools and signs the completed bundle. Check `CFBundleIconFile`, the packaged icon, and the app's signature after changing it.
- Installing the app is separate from creating a PR or publishing a release. `./lokidot install --no-build` uses the recorded build, asks the running app to quit normally, and preserves user preferences.
- Use the shared MacBook Minion skill and queue for compatible substantial background work when the paired worker is available. Never bypass another job's lock.
- Before large builds, run the shared diskcleaner check. Do not delete unrelated files or caches to make room.
