import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    do {
        guard let url = SpriteArtwork.initialURL() else { throw SpriteArtwork.Error.missing }
        let artwork = try SpriteArtwork(url: url)
        try artwork.writePreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        print("Exported original left/right frames; 8 frames per direction, 0.08 seconds per frame.")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        // NSApplication's delegate is weak; retain the owner of the pet and
        // status item for the whole event loop, including quiet rest periods.
        withExtendedLifetime(delegate) { application.run() }
    }
}
