import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

public struct SpritePackError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func checkKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    let extra = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
    if !extra.isEmpty {
        throw SpritePackError("Unknown field(s) \(extra.joined(separator: ", ")) at \(decoder.codingPath.map(\.stringValue).joined(separator: ".")); manifests contain data only.")
    }
}

public struct SpriteAnimation: Codable {
    public let row: Int
    public let column: Int
    public let frameCount: Int
    public let fps: Double

    public init(row: Int, column: Int = 0, frameCount: Int, fps: Double) {
        self.row = row; self.column = column; self.frameCount = frameCount; self.fps = fps
    }
    private enum CodingKeys: String, CodingKey { case row, column, frameCount, fps }
    public init(from decoder: Decoder) throws {
        try checkKeys(decoder, allowed: ["row", "column", "frameCount", "fps"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row)
        column = try c.decode(Int.self, forKey: .column)
        frameCount = try c.decode(Int.self, forKey: .frameCount)
        fps = try c.decode(Double.self, forKey: .fps)
    }
}

public struct SpritePackManifest: Codable {
    public let schemaVersion: Int
    public let format: String
    public let id: String
    public let name: String
    public let image: String
    public let frameWidth: Int
    public let frameHeight: Int
    public let animations: [String: SpriteAnimation]

    public static let zoomiesStates = ["idle", "running-right", "running-left"]
    public static let v2Rows: [(name: String, count: Int)] = [
        ("idle", 6), ("running-right", 8), ("running-left", 8), ("waving", 4),
        ("jumping", 5), ("failed", 8), ("waiting", 6), ("running", 6), ("review", 6),
        ("look", 16)
    ]

    public init(format: String, id: String, name: String, image: String,
                frameWidth: Int, frameHeight: Int, animations: [String: SpriteAnimation]) {
        schemaVersion = 1; self.format = format; self.id = id; self.name = name
        self.image = image; self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.animations = animations
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, format, id, name, image, frameWidth, frameHeight, animations
    }
    public init(from decoder: Decoder) throws {
        try checkKeys(decoder, allowed: ["schemaVersion", "format", "id", "name", "image", "frameWidth", "frameHeight", "animations"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        format = try c.decode(String.self, forKey: .format)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        image = try c.decode(String.self, forKey: .image)
        frameWidth = try c.decode(Int.self, forKey: .frameWidth)
        frameHeight = try c.decode(Int.self, forKey: .frameHeight)
        animations = try c.decode([String: SpriteAnimation].self, forKey: .animations)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32_768 else { throw SpritePackError("manifest.json exceeds 32 KiB.") }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch let error as SpritePackError { throw error }
        catch DecodingError.keyNotFound(let key, let context) {
            throw SpritePackError("manifest.json: missing \( (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")).")
        } catch {
            throw SpritePackError("manifest.json is not valid schema-1 JSON: \(error.localizedDescription)")
        }
    }

    public func validatedRects(width: Int, height: Int) throws -> [String: [CGRect]] {
        guard schemaVersion == 1 else { throw SpritePackError("schemaVersion must be 1.") }
        guard format == "zoomies-v1" || format == "pet-v2" else {
            throw SpritePackError("format must be zoomies-v1 or pet-v2.")
        }
        guard id.range(of: "^[a-z][a-z0-9-]{0,31}$", options: .regularExpression) != nil else {
            throw SpritePackError("id must be 1–32 lowercase letters, digits or hyphens, starting with a letter.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              !name.contains("/"), !name.contains("\\") else {
            throw SpritePackError("name must be 1–40 printable characters without slashes.")
        }
        try Self.validateImageName(image)
        guard (8...512).contains(frameWidth), (8...512).contains(frameHeight) else {
            throw SpritePackError("frameWidth and frameHeight must each be 8–512 pixels.")
        }
        guard width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 8_388_608,
              width % frameWidth == 0, height % frameHeight == 0 else {
            throw SpritePackError("PNG dimensions must be whole multiples of the frame size, at most 4096 per side and 8,388,608 pixels total.")
        }
        let expected = format == "pet-v2" ? Self.v2Rows.map(\.name) : Self.zoomiesStates
        let missing = Set(expected).subtracting(animations.keys).sorted()
        let extra = Set(animations.keys).subtracting(expected).sorted()
        guard missing.isEmpty else { throw SpritePackError("Missing required animation(s): \(missing.joined(separator: ", ")). Supply the complete \(format) set.") }
        guard extra.isEmpty else { throw SpritePackError("Unknown animation(s): \(extra.joined(separator: ", ")). Use only the declared \(format) states.") }
        if format == "pet-v2" {
            guard width == 1536, height == 2288, frameWidth == 192, frameHeight == 208 else {
                throw SpritePackError("pet-v2 requires a 1536 × 2288 PNG with 192 × 208 cells (8 columns, 11 rows).")
            }
            for (row, spec) in Self.v2Rows.enumerated() {
                let a = animations[spec.name]!
                guard a.row == row, a.column == 0, a.frameCount == spec.count else {
                    throw SpritePackError("pet-v2 \(spec.name) requires row \(row), column 0, frameCount \(spec.count).")
                }
            }
        }
        let columns = width / frameWidth, rows = height / frameHeight
        var occupied = Set<Int>(), result = [String: [CGRect]]()
        for name in expected {
            let a = animations[name]!
            let minimum = name == "idle" ? 1 : 2
            guard (minimum...64).contains(a.frameCount), a.fps.isFinite, (0.5...30).contains(a.fps) else {
                throw SpritePackError("\(name): frameCount must be \(minimum)–64 and fps must be 0.5–30.")
            }
            guard (0..<rows).contains(a.row), (0..<columns).contains(a.column) else {
                throw SpritePackError("\(name): row/column is outside the \(columns) × \(rows) grid (indices start at 0).")
            }
            let start = a.row * columns + a.column
            guard start + a.frameCount <= columns * rows else {
                throw SpritePackError("\(name): \(a.frameCount) frames extend beyond the PNG; supply every declared frame.")
            }
            var rects = [CGRect]()
            for index in 0..<a.frameCount {
                let cell = start + index
                guard occupied.insert(cell).inserted else {
                    throw SpritePackError("\(name) frame \(index + 1) overlaps another declared animation. Give every state its own cells.")
                }
                rects.append(CGRect(x: (cell % columns) * frameWidth, y: (cell / columns) * frameHeight,
                                    width: frameWidth, height: frameHeight))
            }
            result[name] = rects
        }
        return result
    }

    public static func validateImageName(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 128, !name.hasPrefix("."),
              name.lowercased().hasSuffix(".png"),
              !name.contains("/"), !name.contains("\\"), !name.contains(":"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw SpritePackError("image must be a plain PNG filename inside the pack folder, such as sprites.png; paths and URLs are not allowed.")
        }
    }
}

/// A local, validated snapshot. No manifest field is executed or fetched.
public final class SpritePack {
    public let manifest: SpritePackManifest
    public let imageData: Data
    public let frames: [String: [CGImage]]

    public static func load(directory: URL) throws -> SpritePack {
        let root = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SpritePackError("Choose a pack folder containing manifest.json and its PNG.")
        }
        // Bind both reads to this directory; O_NOFOLLOW rejects symbolic-link files.
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw SpritePackError("The pack folder could not be opened.") }
        defer { close(fd) }
        let manifest = try SpritePackManifest.decode(read(fd: fd, name: "manifest.json", maximum: 32_768))
        try SpritePackManifest.validateImageName(manifest.image)
        let data = try read(fd: fd, name: manifest.image, maximum: 16 * 1024 * 1024)
        return try SpritePack(manifest: manifest, imageData: data)
    }

    private static func read(fd: Int32, name: String, maximum: Int) throws -> Data {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw SpritePackError("\(name): missing, unreadable, or a symbolic link. Supply a regular local file inside the pack.") }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maximum else {
            throw SpritePackError("\(name): must be a regular file no larger than \(maximum) bytes.")
        }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw SpritePackError("\(name) exceeds \(maximum) bytes.") }
        return data
    }

    public init(manifest: SpritePackManifest, imageData: Data) throws {
        guard imageData.count <= 16 * 1024 * 1024 else { throw SpritePackError("PNG exceeds 16 MiB.") }
        try Self.validatePNGContainer(imageData)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw SpritePackError("Artwork must be one decodable PNG image, not an animation, renamed JPEG, or corrupt file.")
        }
        let rects = try manifest.validatedRects(width: width, height: height)
        guard let atlas = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw SpritePackError("PNG pixel data is corrupt or incomplete.")
        }
        var decoded = [String: [CGImage]]()
        for name in rects.keys.sorted() {
            decoded[name] = try rects[name]!.enumerated().map { index, rect in
                guard let frame = atlas.cropping(to: rect) else { throw SpritePackError("\(name) frame \(index + 1): cannot crop the declared cell.") }
                let alpha = try Self.alphaRange(frame)
                guard alpha.max > 0 else { throw SpritePackError("\(name) frame \(index + 1) is empty. Supply every declared pose.") }
                guard alpha.min == 0 else { throw SpritePackError("\(name) frame \(index + 1) has no transparent background. Export transparent PNG cells.") }
                return frame
            }
        }
        if manifest.format == "pet-v2" {
            let used = rects.values.flatMap { $0 }
            for row in 0..<11 {
                for column in 0..<8 {
                    let rect = CGRect(x: column * 192, y: row * 208, width: 192, height: 208)
                    if !used.contains(rect), let cell = atlas.cropping(to: rect),
                       try Self.alphaRange(cell).max != 0 {
                        throw SpritePackError("pet-v2 unused cell at row \(row), column \(column) must be fully transparent.")
                    }
                }
            }
        }
        self.manifest = manifest; self.imageData = imageData; frames = decoded
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        return crc
    }

    /// ImageIO can recover truncated PNGs. A pack must contain complete bytes,
    /// including an intact checksum for every chunk and a final IEND marker.
    private static func validatePNGContainer(_ data: Data) throws {
        let error = SpritePackError("Artwork must be one complete, decodable PNG: invalid signature, chunk checksum, animation, or end marker.")
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw error }
        try data.withUnsafeBytes { buffer in
            let b = buffer.bindMemory(to: UInt8.self)
            func uint32(_ start: Int) -> UInt32 {
                (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(b[start + $1]) }
            }
            var offset = 8, seenHeader = false, seenPixels = false
            while offset + 12 <= b.count {
                let length = Int(uint32(offset))
                guard length <= b.count - offset - 12 else { throw error }
                let end = offset + 8 + length
                let kind = String(bytes: b[(offset + 4)..<(offset + 8)], encoding: .ascii)
                var crc = UInt32.max
                for i in (offset + 4)..<end {
                    crc = crcTable[Int((crc ^ UInt32(b[i])) & 0xff)] ^ (crc >> 8)
                }
                guard crc ^ UInt32.max == uint32(end), kind != "acTL" else { throw error }
                if !seenHeader {
                    guard kind == "IHDR", length == 13 else { throw error }
                    seenHeader = true
                } else if kind == "IHDR" { throw error }
                if kind == "IDAT" { seenPixels = true }
                if kind == "IEND" {
                    guard length == 0, seenPixels, end + 4 == b.count else { throw error }
                    return
                }
                offset = end + 4
            }
            throw error
        }
    }

    private static func alphaRange(_ image: CGImage) throws -> (min: UInt8, max: UInt8) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw SpritePackError("Could not inspect PNG transparency.")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var low: UInt8 = 255, high: UInt8 = 0
            for offset in stride(from: 3, to: bytes.count, by: 4) {
                low = min(low, bytes[offset]); high = max(high, bytes[offset])
            }
            return (low, high)
        }
    }

    public var displaySize: CGSize {
        let scale = min(144.0 / Double(manifest.frameWidth), 156.0 / Double(manifest.frameHeight))
        return CGSize(width: Double(manifest.frameWidth) * scale, height: Double(manifest.frameHeight) * scale)
    }

    /// Canonical packaging copies only the validated PNG snapshot and manifest.
    public func write(to directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw SpritePackError("Output pack folder already exists; choose a new destination.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let normalized = SpritePackManifest(format: manifest.format, id: manifest.id, name: manifest.name,
            image: "atlas.png", frameWidth: manifest.frameWidth, frameHeight: manifest.frameHeight, animations: manifest.animations)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        try imageData.write(to: directory.appendingPathComponent("atlas.png"), options: .atomic)
    }
}
