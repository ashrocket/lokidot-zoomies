# LokiDot Zoomies for Windows

A native Windows preview using .NET 10 WPF. Extract the entire win-x64 ZIP and run `LokiDot.Zoomies.exe`, or install the MSI and open LokiDot Zoomies Preview from Start. The self-contained download includes its .NET runtime. The MSI installs for all users and requests administrator access; the ZIP runs without installation. Both downloads are unsigned previews and may show a Windows reputation warning.

Choose a dog or All dogs, choose Zoomies, Circle or Prance, and press Start. Pause freezes the current pose; Resume continues from it. Repeat adds 24 seconds of rest between routines. Close the controls window to quit and remove the dogs. Desktop dogs are transparent, topmost, click-through windows that do not activate themselves. The controls window behaves like a normal app window.

Add your dog opens a folder picker for an existing `zoomies-v1` or `pet-v2` pack. A successful import lasts for the current session; the original files stay where they are. Import errors explain which requirement failed. Windows animation effects being off keeps the dogs still.

This preview uses the primary monitor's work area at Start. Multi-monitor placement, mixed-DPI changes, virtual desktops, games, exclusive fullscreen, screen readers and real desktop click-through still need hands-on Windows testing. The Mac app's export, menu-bar integration and persistent settings are not included. `zoomies-v1` lacks jumping artwork; choosing Prance explains the missing frames and keeps the current routine intact. Use Zoomies or Circle for those packs.

Build and verify on Windows with the .NET 10 SDK:

```powershell
./windows/build.ps1
./windows/test-installer.ps1
```

The scripts produce a portable ZIP, an MSI, checksums, test results, installer logs and WPF render images under a fresh `windows/artifacts/runs/<id>` directory. `windows/artifacts/publish-path.txt` records the current publish directory; download copies remain at `windows/artifacts`. Earlier run outputs are preserved. CI runs these same commands on `windows-2025`. A successful build alone is not desktop visual QA. See [Windows implementation and verification](../docs/windows.md) for details and the build-tool support limitation.
