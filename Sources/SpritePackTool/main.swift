import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZoomiesCore

func folder(_ argument: String) -> URL { URL(fileURLWithPath: argument, isDirectory: true) }
func summary(_ pack: SpritePack) -> String {
    let states = pack.manifest.animations.keys.sorted().map {
        "\($0)=\(pack.manifest.animations[$0]!.frameCount)"
    }.joined(separator: ", ")
    return "VALID \(pack.manifest.name) [\(pack.manifest.format)]: \(states)"
}

/// Explicit synthetic test artwork; never used as a fallback character.
func makeSample(at destination: URL) throws {
    let cell = 64, columns = 4, rows = 3
    guard let context = CGContext(data: nil, width: cell * columns, height: cell * rows,
        bitsPerComponent: 8, bytesPerRow: cell * columns * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw SpritePackError("Could not create the synthetic fixture.")
    }
    context.translateBy(x: 0, y: CGFloat(cell * rows)); context.scaleBy(x: 1, y: -1)
    for row in 0..<rows {
        for column in 0..<(row == 0 ? 1 : columns) {
            let x = CGFloat(column * cell), y = CGFloat(row * cell)
            context.setFillColor(CGColor(red: 0.1, green: 0.55, blue: 0.65, alpha: 1))
            context.fill(CGRect(x: x + 18, y: y + 16, width: 28, height: 32))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: x + (row == 2 ? 22 : 36), y: y + 22, width: 6, height: 6))
            context.setFillColor(CGColor(gray: 0.15, alpha: 1))
            let offset = CGFloat(column % 2 == 0 ? 0 : 5)
            context.fill(CGRect(x: x + 18 - offset, y: y + 48, width: 10, height: 5))
            context.fill(CGRect(x: x + 36 + offset, y: y + 48, width: 10, height: 5))
        }
    }
    let bytes = NSMutableData()
    guard let image = context.makeImage(),
          let output = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
        throw SpritePackError("Could not encode the synthetic fixture.")
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { throw SpritePackError("Could not finish the synthetic fixture.") }
    let manifest = SpritePackManifest(format: "zoomies-v1", id: "sample", name: "Sample",
        image: "atlas.png", frameWidth: cell, frameHeight: cell, animations: [
            "idle": SpriteAnimation(row: 0, frameCount: 1, fps: 1),
            "running-right": SpriteAnimation(row: 1, frameCount: 4, fps: 8),
            "running-left": SpriteAnimation(row: 2, frameCount: 4, fps: 8)
        ])
    let pack = try SpritePack(manifest: manifest, imageData: bytes as Data)
    try pack.write(to: destination)
    print(summary(pack))
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw SpritePackError("Usage: SpritePackTool validate PACK | copy PACK NEW_FOLDER | bundle PACK APP | sample NEW_FOLDER")
    }
    switch command {
    case "validate":
        guard args.count == 2 else { throw SpritePackError("Usage: SpritePackTool validate PACK_FOLDER") }
        print(summary(try SpritePack.load(directory: folder(args[1]))))
    case "bundle":
        guard args.count == 3 else { throw SpritePackError("Usage: SpritePackTool bundle PACK_FOLDER APP_BUNDLE") }
        let pack = try SpritePack.load(directory: folder(args[1]))
        let contents = folder(args[2]).appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contents.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw SpritePackError("The destination app has no readable Info.plist.")
        }
        try pack.write(to: contents.appendingPathComponent("Resources/SpritePack", isDirectory: true))
        plist["CFBundleName"] = "\(pack.manifest.name) Zoomies"
        plist["CFBundleDisplayName"] = "\(pack.manifest.name) Zoomies"
        plist["CFBundleIdentifier"] = "com.ashrocket.LokiDotZoomies.pet.\(pack.manifest.id)"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL, options: .atomic)
        print(summary(pack))
    case "copy":
        guard args.count == 3 else { throw SpritePackError("Usage: SpritePackTool copy PACK_FOLDER NEW_FOLDER") }
        let pack = try SpritePack.load(directory: folder(args[1]))
        try pack.write(to: folder(args[2]))
        print(summary(pack))
    case "sample":
        guard args.count == 2 else { throw SpritePackError("Usage: SpritePackTool sample NEW_FOLDER") }
        try makeSample(at: folder(args[1]))
    default:
        throw SpritePackError("Unknown command \(command). Use validate, copy, bundle, or sample.")
    }
} catch {
    fputs("INVALID: \(error.localizedDescription)\n", stderr)
    exit(1)
}
