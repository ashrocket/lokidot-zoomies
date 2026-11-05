import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ZoomiesCore

final class SavedPetLibraryTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pet-library-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func pack(color: CGFloat = 0.4, imageName: String = "atlas.png") throws -> SpritePack {
        let manifest = SpritePackManifest(format: "zoomies-v1", id: "beagle", name: "Library Test Pet", image: imageName,
            frameWidth: 16, frameHeight: 16, animations: [
                "idle": .init(row: 0, frameCount: 1, fps: 1),
                "running-right": .init(row: 1, frameCount: 2, fps: 10),
                "running-left": .init(row: 2, frameCount: 2, fps: 10)])
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 48, bitsPerComponent: 8, bytesPerRow: 128,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: color, alpha: 1))
        for row in 0..<3 { for column in 0..<2 { context.fill(CGRect(x: column * 16 + 4, y: row * 16 + 4, width: 8, height: 8)) } }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try SpritePack(manifest: manifest, imageData: data as Data)
    }

    func testSaveCopiesOnlyValidatedPackAndSurvivesOriginalMoving() throws {
        let root = try temporary(), source = root.appendingPathComponent("original"), libraryRoot = root.appendingPathComponent("library")
        let original = try pack(); try original.write(to: source)
        try Data("Private reference photo".utf8).write(to: source.appendingPathComponent("reference.jpg"))
        let saved = try SavedPetLibrary(root: libraryRoot).save(SpritePack.load(directory: source))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: saved.directory.path)), ["manifest.json", "atlas.png"])
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("moved-original"))
        let restarted = SavedPetLibrary(root: libraryRoot)
        XCTAssertEqual(try restarted.pets().map(\.id), [saved.id])
        XCTAssertEqual(try SpritePack.load(directory: restarted.directory(for: saved.id)).imageData, original.imageData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("moved-original/reference.jpg").path))
    }

    func testExactReimportReusesCopyEvenWithDifferentPNGFilename() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        let first = try library.save(pack()), second = try library.save(pack(imageName: "my-pet.png"))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try library.pets().count, 1)
    }

    func testSameManifestIDAndNameWithDifferentArtworkStaySeparate() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        let first = try library.save(pack(color: 0.2)), second = try library.save(pack(color: 0.8))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, "beagle")
        XCTAssertTrue(SavedPetLibrary.isSavedID(first.id))
        XCTAssertEqual(try library.pets().count, 2)
    }

    func testTrashOnlyMovesManagedCopyAndKeepsOriginal() throws {
        let root = try temporary(), source = root.appendingPathComponent("original"), trash = root.appendingPathComponent("fixture-trash")
        let original = try pack(); try original.write(to: source)
        let library = SavedPetLibrary(root: root.appendingPathComponent("library"))
        let saved = try library.save(original)
        try library.remove(saved.id) { try FileManager.default.moveItem(at: $0, to: trash) }
        XCTAssertTrue(try library.pets().isEmpty)
        XCTAssertEqual(try SpritePack.load(directory: source).imageData, original.imageData)
        XCTAssertEqual(try SpritePack.load(directory: trash).imageData, original.imageData)
    }

    func testFailedTrashPreservesSavedCopy() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        let saved = try library.save(pack())
        XCTAssertThrowsError(try library.remove(saved.id) { _ in throw SpritePackError("Trash unavailable") })
        XCTAssertEqual(try library.pets().map(\.id), [saved.id])
    }

    func testRemovalRejectsForeignPathsAndBuiltInIdentifiers() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        _ = try library.save(pack())
        for id in ["beagle", "../original", "/tmp/another-pet", "saved-../../original", "saved-zzzzzzzzzzzzzzzzzzzzzzzz"] {
            XCTAssertThrowsError(try library.remove(id) { _ in XCTFail("Must not call Trash for a foreign path") })
        }
    }

    func testSymlinkCannotRedirectLibraryOrRemoval() throws {
        let root = try temporary(), original = root.appendingPathComponent("original")
        try pack().write(to: original)
        let link = root.appendingPathComponent("linked-library")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try SavedPetLibrary(root: link).save(pack()))
        let library = SavedPetLibrary(root: root.appendingPathComponent("library"))
        _ = try library.save(pack())
        let id = "saved-0123456789abcdef01234567"
        try FileManager.default.createSymbolicLink(at: library.root.appendingPathComponent(id), withDestinationURL: original)
        XCTAssertThrowsError(try library.remove(id) { _ in XCTFail("Must not trash a symlink target") })
        XCTAssertNotNil(try library.pets().first { $0.id == id }?.problem)
        XCTAssertNoThrow(try SpritePack.load(directory: original))
    }

    func testBrokenEntryDoesNotHideHealthyPetsAndCanBeRemoved() throws {
        let root = try temporary(), library = SavedPetLibrary(root: root.appendingPathComponent("library"))
        let good = try library.save(pack())
        let brokenID = "saved-0123456789abcdef01234567"
        let broken = library.root.appendingPathComponent(brokenID)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not a manifest".utf8).write(to: broken.appendingPathComponent("manifest.json"))
        let entries = try library.pets()
        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(entries.first { $0.id == good.id }?.problem)
        XCTAssertNotNil(entries.first { $0.id == brokenID }?.problem)
        try library.remove(brokenID) { try FileManager.default.moveItem(at: $0, to: root.appendingPathComponent("fixture-trash")) }
        XCTAssertEqual(try library.pets().map(\.id), [good.id])
    }

    func testDamagedExistingCopyIsNotOverwrittenByReimport() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        let original = try pack(), saved = try library.save(original)
        let changed = Data("damaged but preserved".utf8)
        try changed.write(to: saved.directory.appendingPathComponent("atlas.png"))
        XCTAssertThrowsError(try library.save(original))
        XCTAssertEqual(try Data(contentsOf: saved.directory.appendingPathComponent("atlas.png")), changed)
    }

    func testNewLibraryFilesArePrivateAndNoStagingFolderIsListed() throws {
        let library = SavedPetLibrary(root: try temporary().appendingPathComponent("library"))
        let saved = try library.save(pack())
        for (url, mode) in [(library.root, 0o700), (saved.directory, 0o700), (saved.directory.appendingPathComponent("atlas.png"), 0o600)] {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, mode)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.root.path), [saved.id])
    }
}
