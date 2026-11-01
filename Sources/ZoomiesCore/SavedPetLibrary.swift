import Foundation
import CryptoKit

public struct SavedPet: Equatable {
    public let id: String
    public let name: String
    public let directory: URL
    public let problem: String?
}

/// Personal packs live outside the app bundle and source checkout. A save copies
/// only a validated snapshot; reference photos and unrelated files stay put.
public struct SavedPetLibrary {
    public let root: URL
    private let files = FileManager.default
    public init(root: URL) { self.root = root.standardizedFileURL }

    public static func isSavedID(_ id: String) -> Bool {
        id.range(of: "^saved-[0-9a-f]{24}$", options: .regularExpression) != nil
    }

    private func checkedRoot(create: Bool = false) throws {
        if !files.fileExists(atPath: root.path), create {
            try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SpritePackError("The saved-pet library must be an ordinary local folder.")
        }
    }

    public func directory(for id: String) throws -> URL {
        guard Self.isSavedID(id) else { throw SpritePackError("That is not a saved pet identifier.") }
        try checkedRoot()
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SpritePackError("The saved pet is missing or is not an ordinary folder. Import its original pack again.")
        }
        return directory
    }

    public func pets() throws -> [SavedPet] {
        guard files.fileExists(atPath: root.path) else { return [] }
        try checkedRoot()
        let children = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return children.filter { Self.isSavedID($0.lastPathComponent) }.map { child in
            let id = child.lastPathComponent
            do {
                let pack = try SpritePack.load(directory: directory(for: id))
                return SavedPet(id: id, name: pack.manifest.name, directory: child, problem: nil)
            } catch {
                // One broken saved copy must not prevent other pets from loading.
                return SavedPet(id: id, name: "Unavailable saved pet", directory: child, problem: error.localizedDescription)
            }
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func save(_ pack: SpritePack) throws -> SavedPet {
        try checkedRoot(create: true)
        let fingerprint = try Self.fingerprint(pack)
        let id = "saved-" + fingerprint.prefix(24)
        let destination = root.appendingPathComponent(id, isDirectory: true)
        if files.fileExists(atPath: destination.path) {
            let existing = try SpritePack.load(directory: directory(for: id))
            guard try Self.fingerprint(existing) == fingerprint else {
                throw SpritePackError("A different or damaged saved copy occupies this pet's library folder. Remove that copy in Saved pets, then import again.")
            }
            return SavedPet(id: id, name: existing.manifest.name, directory: destination, problem: nil)
        }
        let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { if files.fileExists(atPath: staging.path) { try? files.removeItem(at: staging) } }
        try pack.write(to: staging)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
        for name in ["manifest.json", "atlas.png"] {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.appendingPathComponent(name).path)
        }
        // Commit the complete folder in one move; never replace an existing pet.
        try files.moveItem(at: staging, to: destination)
        return SavedPet(id: id, name: pack.manifest.name, directory: destination, problem: nil)
    }

    /// The caller supplies the OS Trash operation. Tests supply a private fixture
    /// trash, never the owner's real Trash. Only a direct managed child is accepted.
    public func remove(_ id: String, moveToTrash: (URL) throws -> Void) throws {
        try moveToTrash(directory(for: id))
    }

    private static func fingerprint(_ pack: SpritePack) throws -> String {
        let manifest = pack.manifest
        let canonical = SpritePackManifest(format: manifest.format, id: manifest.id, name: manifest.name,
                                           image: "atlas.png", frameWidth: manifest.frameWidth,
                                           frameHeight: manifest.frameHeight, animations: manifest.animations)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256(); hash.update(data: try encoder.encode(canonical)); hash.update(data: pack.imageData)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
