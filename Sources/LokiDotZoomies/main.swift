import AppKit
import ZoomiesCore

let args = CommandLine.arguments
func fail(_ message: String) -> Never { fputs("\(message)\n", stderr); exit(1) }
if args.contains("--all-ready") && args.contains("--pack") {
    fail("Choose --all-ready for the bundled characters or --pack for one imported character.")
}
if args.contains("--spritesheet") {
    fail("--spritesheet has been replaced by --pack /path/to/folder. Add manifest.json; see docs/sprite-packs.md.")
}
for flag in ["--pack", "--render-preview", "--diagnostics"] {
    if let index = args.firstIndex(of: flag), args.count <= index + 1 || args[index + 1].hasPrefix("--") {
        fail("\(flag) requires a local path.")
    }
}
if let index = args.firstIndex(of: "--render-preview") {
    do {
        guard let url = SpriteArtwork.initialURL() else { throw SpritePackError("Supply --pack /path/to/folder or build with a validated sprite pack.") }
        let artwork = try SpriteArtwork(url: url)
        try artwork.writePreviews(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
        print("Exported \(artwork.pack.frames.count) declared states for \(artwork.name).")
    } catch { fail(error.localizedDescription) }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
