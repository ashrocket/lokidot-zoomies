import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--render-art"), CommandLine.arguments.count > index + 1 {
    let representation = NSBitmapImageRep(cgImage: PetArtwork.image(scale: 4))
    if let data = representation.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
