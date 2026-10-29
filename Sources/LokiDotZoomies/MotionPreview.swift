import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZoomiesCore

/// Offscreen proof of the same poses and authored frames used by Overlay.
enum MotionPreview {
    static func write(artworks: [SpriteArtwork], style: MotionStyle, to destination: URL) throws {
        guard !artworks.isEmpty else { throw SpritePackError("No ready characters to preview.") }
        guard style != .prance || artworks.allSatisfy(\.canPrance) else {
            throw SpritePackError("Prancing requires authored jumping poses in every selected pack.")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let width = 960, height = 600
        let routines = artworks.enumerated().map {
            MotionRoutine(style: style, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                          artworkSize: $0.element.displaySize, index: $0.offset, count: artworks.count)
        }
        func render(_ progress: Double) throws -> CGImage {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw SpritePackError("Could not create a motion preview.")
            }
            context.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 0.94, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let poses = routines.map { $0.sample(progress: progress) }
            for index in artworks.indices.sorted(by: { poses[$0].point.y > poses[$1].point.y }) {
                let pose = poses[index], artwork = artworks[index], size = routines[index].route.spriteSize
                context.saveGState()
                context.translateBy(x: pose.point.x, y: pose.point.y)
                context.rotate(by: pose.bank); context.scaleBy(x: pose.scaleX, y: pose.scaleY)
                let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
                if let jump = pose.jumpProgress { context.draw(artwork.jumpingFrame(progress: jump), in: rect) }
                else {
                    context.setAlpha(1 - pose.rightWeight)
                    context.draw(artwork.runningFrame(time: pose.strideTime, facingLeft: true), in: rect)
                    context.setAlpha(pose.rightWeight)
                    context.draw(artwork.runningFrame(time: pose.strideTime, facingLeft: false), in: rect)
                }
                context.restoreGState()
            }
            return context.makeImage()!
        }
        let frameCount = Int(style.duration * 15)
        let gifURL = destination.appendingPathComponent(style.rawValue + ".gif")
        guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw SpritePackError("Cannot write \(gifURL.path).")
        }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<frameCount {
            CGImageDestinationAddImage(gif, try render(Double(index) / Double(frameCount - 1)),
                                      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw SpritePackError("Could not finish the motion GIF.") }
        guard let sheet = CGContext(data: nil, width: width * 3, height: height * 2, bitsPerComponent: 8,
                                    bytesPerRow: width * 3 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for (index, progress) in [0.0, 0.14, 0.32, 0.5, 0.68, 0.86].enumerated() {
            sheet.draw(try render(progress), in: CGRect(x: (index % 3) * width, y: (1 - index / 3) * height, width: width, height: height))
        }
        let url = destination.appendingPathComponent(style.rawValue + "-storyboard.png")
        guard let png = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil), let image = sheet.makeImage() else { return }
        CGImageDestinationAddImage(png, image, nil)
        guard CGImageDestinationFinalize(png) else { throw SpritePackError("Could not finish the storyboard.") }
    }
}
