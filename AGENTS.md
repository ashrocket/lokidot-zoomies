# Zoomies project guidance

- Keep changes scoped and preserve personal sprite packs outside the repository. Adding an app icon does not authorize publishing a user's dog pack or recording.
- Build the app and distribution ZIP with `./lokidot build`; use `./lokidot test` for the existing XCTest suite. Read `scripts/build.sh` and `scripts/install.sh` before changing packaging or installation.
- `LOKIDOT_BUILD_ROOT` and `LOKIDOT_MODULE_CACHE` can place build output and compiler caches in an explicit local directory. Do not build inside synced folders.
- App icon source lives in `Resources/AppIcon/whippet-head.png`. The build produces the ICNS sizes with macOS tools and signs the completed bundle. Check `CFBundleIconFile`, the packaged icon, and the app's signature after changing it.
- Installing the app is separate from creating a PR or publishing a release. `./lokidot install --no-build` uses the recorded build, asks the running app to quit normally, and preserves user preferences.
- Use the shared MacBook Minion skill and queue for compatible substantial background work when the paired worker is available. Never bypass another job's lock.
- Before large builds, run the shared diskcleaner check. Do not delete unrelated files or caches to make room.
