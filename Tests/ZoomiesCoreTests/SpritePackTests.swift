import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import ZoomiesCore

final class SpritePackTests: XCTestCase {
    private func manifest(v2: Bool = false) -> SpritePackManifest {
        var states: [String: SpriteAnimation] = [
            "idle": SpriteAnimation(row: 0, frameCount: 1, fps: 1),
            "running-right": SpriteAnimation(row: 1, frameCount: 2, fps: 10),
            "running-left": SpriteAnimation(row: 2, frameCount: 3, fps: 15)
        ]
        if v2 {
            states = Dictionary(uniqueKeysWithValues: SpritePackManifest.v2Rows.enumerated().map {
                ($0.element.name, SpriteAnimation(row: $0.offset, frameCount: $0.element.count, fps: 12.5))
            })
        }
        return SpritePackManifest(format: v2 ? "pet-v2" : "zoomies-v1", id: "test-pet", name: "Test Pet",
            image: "atlas.png", frameWidth: v2 ? 192 : 32, frameHeight: v2 ? 208 : 32, animations: states)
    }

    private func dictionary(_ source: SpritePackManifest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
    }
    private func decode(_ object: [String: Any]) throws -> SpritePackManifest {
        try SpritePackManifest.decode(JSONSerialization.data(withJSONObject: object))
    }
    private func mutate(_ source: SpritePackManifest? = nil,
                        _ body: (inout [String: Any]) -> Void) throws -> SpritePackManifest {
        var object = try dictionary(source ?? manifest()); body(&object)
        return try decode(object)
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoomies-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func png(_ source: SpritePackManifest? = nil, emptyCell: Int? = nil,
                     opaque: Bool = false, fillUnused: Bool = false, type: UTType = .png) throws -> Data {
        let m = source ?? manifest()
        let width = m.format == "pet-v2" ? 1536 : 128
        let height = m.format == "pet-v2" ? 2288 : 96
        let rects = try m.validatedRects(width: width, height: height).values.flatMap { $0 }
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        if opaque || fillUnused {
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        for rect in rects {
            let cell = Int(rect.minY) / m.frameHeight * (width / m.frameWidth) + Int(rect.minX) / m.frameWidth
            if cell != emptyCell { context.fill(rect.insetBy(dx: 6, dy: 6)) }
        }
        if fillUnused {
            // Restore required cells' transparent margins; leave unused cells opaque.
            for rect in rects {
                context.clear(rect)
                context.fill(rect.insetBy(dx: 6, dy: 6))
            }
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func invalid(_ m: SpritePackManifest, contains text: String, data: Data? = nil,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let bytes = try data ?? png()
        XCTAssertThrowsError(try SpritePack(manifest: m, imageData: bytes), file: file, line: line) {
            XCTAssertTrue($0.localizedDescription.contains(text), $0.localizedDescription, file: file, line: line)
        }
    }

    func testCompleteNativeSetAllowsDifferentCountsAndRoundTrips() throws {
        let pack = try SpritePack(manifest: manifest(), imageData: png())
        XCTAssertEqual(pack.frames["running-right"]?.count, 2)
        XCTAssertEqual(pack.frames["running-left"]?.count, 3)
        let destination = try temporary().appendingPathComponent("pack")
        try pack.write(to: destination)
        let loaded = try SpritePack.load(directory: destination)
        XCTAssertEqual(loaded.imageData, pack.imageData)
        XCTAssertEqual(loaded.manifest.id, "test-pet")
        XCTAssertEqual(loaded.manifest.animations["running-left"]?.fps, 15)
        XCTAssertThrowsError(try pack.write(to: destination))
    }

    func testCompleteV2RequiresAllSeventyThreePoses() throws {
        let m = manifest(v2: true)
        let pack = try SpritePack(manifest: m, imageData: png(m))
        XCTAssertEqual(pack.frames.values.reduce(0) { $0 + $1.count }, 73)
        XCTAssertEqual(pack.frames["look"]?.count, 16)
    }

    func testV2RejectsMissingNonLocomotionStateAndWrongFrameCount() throws {
        let m = manifest(v2: true), bytes = try png(m)
        let missing = try mutate(m) {
            var states = $0["animations"] as! [String: Any]
            states.removeValue(forKey: "review"); $0["animations"] = states
        }
        try invalid(missing, contains: "review", data: bytes)
        let wrong = try mutate(m) {
            var states = $0["animations"] as! [String: Any]
            states["look"] = ["row": 9, "column": 0, "frameCount": 8, "fps": 1]; $0["animations"] = states
        }
        try invalid(wrong, contains: "frameCount 16", data: bytes)
    }

    func testV2RejectsWrongGeometryAndPaintInUnusedCells() throws {
        try invalid(manifest(v2: true), contains: "whole multiples")
        let m = manifest(v2: true)
        try invalid(m, contains: "unused cell", data: png(m, fillUnused: true))
    }

    func testMissingDirectionHasAnActionableError() throws {
        let m = try mutate {
            var states = $0["animations"] as! [String: Any]
            states.removeValue(forKey: "running-left"); $0["animations"] = states
        }
        try invalid(m, contains: "Missing required animation(s): running-left")
    }

    func testUnknownExecutableAndNestedFieldsAreRejected() throws {
        XCTAssertThrowsError(try mutate { $0["postBuild"] = "touch /tmp/should-not-run" })
        XCTAssertThrowsError(try mutate {
            var states = $0["animations"] as! [String: Any]
            var idle = states["idle"] as! [String: Any]
            idle["script"] = "anything"; states["idle"] = idle; $0["animations"] = states
        })
        try invalid(try mutate {
            var states = $0["animations"] as! [String: Any]
            states["download"] = ["row": 0, "column": 2, "frameCount": 2, "fps": 1]
            $0["animations"] = states
        }, contains: "Unknown animation")
    }

    func testPathsAndURLsCannotEscapePack() throws {
        for name in ["../outside.png", "/tmp/outside.png", "sub/art.png", "..\\outside.png",
                     "https://example.test/art.png", "file:art.png", ".hidden.png", "bad\n.png"] {
            try invalid(try mutate { $0["image"] = name }, contains: "plain PNG filename")
        }
    }

    func testSymlinkImageAndManifestAreRejected() throws {
        let root = try temporary(), external = root.appendingPathComponent("outside.png")
        try png().write(to: external)
        let pack = root.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest()).write(to: pack.appendingPathComponent("manifest.json"))
        try FileManager.default.createSymbolicLink(at: pack.appendingPathComponent("atlas.png"), withDestinationURL: external)
        XCTAssertThrowsError(try SpritePack.load(directory: pack)) {
            XCTAssertTrue($0.localizedDescription.contains("symbolic link"))
        }
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("manifest.json"),
            withDestinationURL: pack.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try SpritePack.load(directory: linked))
    }

    func testNonRegularFilesAreRejectedWithoutBlocking() throws {
        let root = try temporary()
        XCTAssertEqual(mkfifo(root.appendingPathComponent("manifest.json").path, 0o600), 0)
        XCTAssertThrowsError(try SpritePack.load(directory: root)) {
            XCTAssertTrue($0.localizedDescription.contains("regular file"))
        }
    }

    func testCorruptAndDisguisedImagesAreRejected() throws {
        try invalid(manifest(), contains: "decodable PNG", data: Data("not a PNG".utf8))
        try invalid(manifest(), contains: "decodable PNG", data: png(type: .jpeg))
        try invalid(manifest(), contains: "decodable PNG", data: png().prefix(20))
        try invalid(manifest(), contains: "decodable PNG", data: Data(png().dropLast(12)))
        var corrupted = try png()
        corrupted[29] ^= 1
        try invalid(manifest(), contains: "checksum", data: corrupted)
    }

    func testMissingFilesAndMalformedJSONAreRejected() throws {
        let root = try temporary()
        XCTAssertThrowsError(try SpritePack.load(directory: root)) {
            XCTAssertTrue($0.localizedDescription.contains("manifest.json"))
        }
        try JSONEncoder().encode(manifest()).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try SpritePack.load(directory: root)) {
            XCTAssertTrue($0.localizedDescription.contains("atlas.png"))
        }
        XCTAssertThrowsError(try SpritePackManifest.decode(Data("{".utf8)))
        XCTAssertThrowsError(try SpritePackManifest.decode(Data("{}".utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("missing schemaVersion"))
        }
    }

    func testEmptyAndOpaqueFramesAreRejected() throws {
        try invalid(manifest(), contains: "running-left frame 2 is empty", data: png(emptyCell: 9))
        try invalid(manifest(), contains: "transparent background", data: png(opaque: true))
    }

    func testOverlapsNegativeIndicesAndOutOfBoundsAreRejected() throws {
        for row in [-1, 3] {
            try invalid(try mutate {
                var states = $0["animations"] as! [String: Any]
                states["running-left"] = ["row": row, "column": 0, "frameCount": 3, "fps": 10]
                $0["animations"] = states
            }, contains: "outside")
        }
        try invalid(try mutate {
            var states = $0["animations"] as! [String: Any]
            states["running-left"] = ["row": 2, "column": 2, "frameCount": 3, "fps": 10]
            $0["animations"] = states
        }, contains: "extend beyond")
        try invalid(try mutate {
            var states = $0["animations"] as! [String: Any]
            states["running-left"] = ["row": 1, "column": 0, "frameCount": 3, "fps": 10]
            $0["animations"] = states
        }, contains: "overlaps")
    }

    func testCountsRatesAndGridDimensionsAreBounded() throws {
        for count in [0, 1, 65] {
            try invalid(try mutate {
                var states = $0["animations"] as! [String: Any]
                states["running-left"] = ["row": 2, "column": 0, "frameCount": count, "fps": 10]
                $0["animations"] = states
            }, contains: "frameCount")
        }
        for fps in [0, -1, 31] {
            try invalid(try mutate {
                var states = $0["animations"] as! [String: Any]
                states["running-left"] = ["row": 2, "column": 0, "frameCount": 3, "fps": fps]
                $0["animations"] = states
            }, contains: "fps")
        }
        try invalid(try mutate { $0["frameWidth"] = 33 }, contains: "whole multiples")
        try invalid(try mutate { $0["frameHeight"] = 513 }, contains: "8–512")
        XCTAssertThrowsError(try manifest().validatedRects(width: 8192, height: 8192))
    }

    func testManifestAndPNGSizeLimits() throws {
        XCTAssertThrowsError(try SpritePackManifest.decode(Data(repeating: 32, count: 32_769)))
        try invalid(manifest(), contains: "16 MiB", data: Data(repeating: 0, count: 16 * 1024 * 1024 + 1))
    }

    func testNamesIdentifiersAndSchemaAreValidated() throws {
        for id in ["../bad", "A", "bad id", "$(anything)", String(repeating: "a", count: 33)] {
            try invalid(try mutate { $0["id"] = id }, contains: "id must")
        }
        try invalid(try mutate { $0["name"] = "Bad\nName" }, contains: "name must")
        try invalid(try mutate { $0["schemaVersion"] = 2 }, contains: "schemaVersion")
        try invalid(try mutate { $0["format"] = "unknown" }, contains: "format must")
    }

    func testTallAndWideArtworkRemainInsideMotionBounds() throws {
        for size in [CGSize(width: 144, height: 20), CGSize(width: 20, height: 156)] {
            let bounds = CGRect(x: -300, y: 40, width: 1200, height: 900)
            let route = MotionRoute(bounds: bounds, artworkSize: size)
            let radius = hypot(route.spriteSize.width, route.spriteSize.height) / 2
            for i in 0...1000 {
                let point = route.sample(progress: Double(i) / 1000).point
                XCTAssertTrue(bounds.contains(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)))
            }
        }
    }

    func testThreePhaseOffsetsCloseSmoothlyAndStayOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let route = MotionRoute(bounds: bounds)
        var starts = [CGPoint]()
        for phase in [0.0, 1.0 / 3, 2.0 / 3] {
            let start = route.sample(progress: 0, phase: phase)
            let end = route.sample(progress: 1, phase: phase)
            starts.append(start.point)
            XCTAssertEqual(start.point.x, end.point.x, accuracy: 0.001)
            XCTAssertEqual(start.point.y, end.point.y, accuracy: 0.001)
            var previous = start.point
            for i in 1...2000 {
                let current = route.sample(progress: Double(i) / 2000, phase: phase).point
                XCTAssertTrue(bounds.contains(current))
                XCTAssertLessThan(hypot(current.x - previous.x, current.y - previous.y), 20)
                previous = current
            }
        }
        for index in 0..<3 {
            let other = starts[(index + 1) % 3]
            XCTAssertGreaterThan(hypot(starts[index].x - other.x, starts[index].y - other.y), 50)
        }
    }
}
