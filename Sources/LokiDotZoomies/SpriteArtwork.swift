import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZoomiesCore

/// Reads existing pixels only. No artwork, URL, account ID, or private file path
/// is embedded in the public source. The optional bundled PNG stays local.
final class SpriteArtwork {
    static let frameDuration = 0.08
    let layout: SpriteLayout
    let idle: [CGImage]
    let right: [CGImage]
    let left: [CGImage]

    enum Error: Swift.Error, LocalizedError {
        case unreadable, missing, exportFailed
        var errorDescription: String? {
            switch self {
            case .unreadable: return "This file could not be read as a pet sprite sheet."
            case .missing: return "Choose Loki Artwork from the paw menu to load a local sprite sheet."
            case .exportFailed: return "The animation preview could not be saved."
            }
        }
    }

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Error.unreadable }
        let layout = try SpriteLayout(width: width, height: height)
        self.layout = layout
        guard let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Error.unreadable }
        func frames(_ state: SpriteLayout.State) throws -> [CGImage] {
            try (0..<state.frameCount).map {
                guard let frame = atlas.cropping(to: try layout.frameRect(state: state, index: $0)) else {
                    throw Error.unreadable
                }
                return frame
            }
        }
        idle = try frames(.idle)
        right = try frames(.runningRight)
        left = try frames(.runningLeft)
    }

    static func initialURL() -> URL? {
        if let index = CommandLine.arguments.firstIndex(of: "--spritesheet"), CommandLine.arguments.count > index + 1 {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        return Bundle.main.url(forResource: "LokiSpriteSheet", withExtension: "png")
    }

    func runningFrame(time: TimeInterval, facingLeft: Bool) -> CGImage {
        let frames = facingLeft ? left : right
        let index = Int(max(0, time) / Self.frameDuration) % frames.count
        return frames[index]
    }

    /// Local review artifacts preserve the source frames and their order.
    func writePreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, frames) in [("running-left", left), ("running-right", right)] {
            let url = directory.appendingPathComponent(name + ".gif")
            guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
                throw Error.exportFailed
            }
            CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for frame in frames {
                CGImageDestinationAddImage(output, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Self.frameDuration]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(output) else { throw Error.exportFailed }
            let still = directory.appendingPathComponent(name + ".png")
            guard let png = CGImageDestinationCreateWithURL(still as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Error.exportFailed }
            CGImageDestinationAddImage(png, frames[0], nil)
            guard CGImageDestinationFinalize(png) else { throw Error.exportFailed }
        }
    }
}
