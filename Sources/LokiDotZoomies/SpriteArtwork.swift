import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZoomiesCore

final class SpriteArtwork {
    let pack: SpritePack
    let sourceURL: URL
    var name: String { pack.manifest.name }
    var idle: [CGImage] { pack.frames["idle"]! }
    var displaySize: CGSize { pack.displaySize }
    var canPrance: Bool { pack.frames["jumping"] != nil }

    func jumpingFrame(progress: Double) -> CGImage {
        precondition(canPrance, "Prancing requires authored jumping frames")
        let frames = pack.frames["jumping"]!
        return frames[min(frames.count - 1, Int(max(0, min(1, progress)) * Double(frames.count)))]
    }

    init(url: URL) throws {
        pack = try SpritePack.load(directory: url)
        sourceURL = url
    }

    static func initialURL() -> URL? {
        if let index = CommandLine.arguments.firstIndex(of: "--pack"), CommandLine.arguments.count > index + 1 {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        }
        let url = Bundle.main.resourceURL?.appendingPathComponent("SpritePack", isDirectory: true)
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    func runningFrame(time: TimeInterval, facingLeft: Bool) -> CGImage {
        let state = facingLeft ? "running-left" : "running-right"
        let frames = pack.frames[state]!
        let fps = pack.manifest.animations[state]!.fps
        return frames[Int(max(0, time) * fps) % frames.count]
    }

    func writePreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in pack.frames.keys.sorted() {
            let frames = pack.frames[name]!
            let delay = 1 / pack.manifest.animations[name]!.fps
            let url = directory.appendingPathComponent(name + ".gif")
            guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
                throw SpritePackError("Could not create \(name).gif.")
            }
            CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for frame in frames {
                CGImageDestinationAddImage(output, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(output) else { throw SpritePackError("Could not finish \(name).gif.") }
        }
    }
}
