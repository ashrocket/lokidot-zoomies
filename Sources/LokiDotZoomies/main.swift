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
for flag in ["--pack", "--render-preview", "--render-motion-preview", "--diagnostics", "--motion"] {
    if let index = args.firstIndex(of: flag), args.count <= index + 1 || args[index + 1].hasPrefix("--") {
        fail("\(flag) requires a local path.")
    }
}
if let index = args.firstIndex(of: "--motion"), MotionStyle(rawValue: args[index + 1]) == nil {
    fail("--motion must be zoomies, circle, or prance.")
}
if args.contains("--help") || args.contains("-h") {
    print("LokiDot Zoomies: --all-ready, --pack FOLDER, --motion zoomies|circle|prance, --background, --reduce-motion, --diagnostics FILE, --render-preview FOLDER, --render-motion-preview FOLDER. For easy commands, run lokidot --help.")
    exit(0)
}
if let index = args.firstIndex(of: "--render-motion-preview") {
    do {
        let style = args.firstIndex(of: "--motion").flatMap { MotionStyle(rawValue: args[$0 + 1]) } ?? .zoomies
        let artworks: [SpriteArtwork]
        if let url = SpriteArtwork.initialURL() { artworks = [try SpriteArtwork(url: url)] }
        else {
            guard let root = Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true) else { throw SpritePackError("Build the app first.") }
            let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            let ready = try folders.sorted(by: { $0.path < $1.path }).map { try SpriteArtwork(url: $0) }
            artworks = args.contains("--all-ready") ? ready : Array(ready.filter { $0.pack.manifest.id == "robot-loki" }.prefix(1))
        }
        try MotionPreview.write(artworks: artworks, style: style, to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
        print("Exported \(style.title) for \(artworks.count) character(s).")
    } catch { fail(error.localizedDescription) }
} else if let index = args.firstIndex(of: "--render-preview") {
    do {
        guard let url = SpriteArtwork.initialURL() else { throw SpritePackError("Supply --pack /path/to/folder or build with a validated sprite pack.") }
        let artwork = try SpriteArtwork(url: url)
        try artwork.writePreviews(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
        print("Exported \(artwork.pack.frames.count) declared states for \(artwork.name).")
    } catch { fail(error.localizedDescription) }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
