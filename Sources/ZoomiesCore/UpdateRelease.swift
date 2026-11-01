import Foundation
import CryptoKit

public struct UpdateError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Stable releases only. Reject aliases, leading zeros, suffixes and integer overflow.
public struct UpdateVersion: Comparable, Equatable, CustomStringConvertible {
    public let major: UInt64
    public let minor: UInt64
    public let patch: UInt64
    public init(_ value: String) throws {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw UpdateError("The release version is invalid.") }
        let numbers = try parts.map { part -> UInt64 in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = UInt64(part) else {
                throw UpdateError("The release version is invalid.")
            }
            return number
        }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }
    public var description: String { "\(major).\(minor).\(patch)" }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct UpdateRelease {
    public static let metadataURL = URL(string: "https://api.github.com/repos/ashrocket/lokidot-zoomies/releases/latest")!
    public static let maximumMetadataBytes = 1024 * 1024
    public static let maximumPackageBytes = 128 * 1024 * 1024
    public let version: UpdateVersion
    public let filename: String
    public let downloadURL: URL
    public let size: Int
    public let sha256: String

    private struct Feed: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let state: String
        let size: Int
        let digest: String?
    }

    public static func parse(_ data: Data, currentVersion: String, architecture: String) throws -> UpdateRelease? {
        guard data.count <= maximumMetadataBytes else { throw UpdateError("The release response is too large.") }
        guard ["arm64", "x86_64"].contains(architecture) else { throw UpdateError("This Mac architecture is unsupported.") }
        let current = try UpdateVersion(currentVersion)
        let feed: Feed
        do { feed = try JSONDecoder().decode(Feed.self, from: data) }
        catch { throw UpdateError("GitHub returned an invalid release response.") }
        guard !feed.draft, !feed.prerelease, feed.tag_name.hasPrefix("v") else {
            throw UpdateError("The release is not a stable version.")
        }
        let version = try UpdateVersion(String(feed.tag_name.dropFirst()))
        guard feed.html_url == "https://github.com/ashrocket/lokidot-zoomies/releases/tag/v\(version)" else {
            throw UpdateError("The release does not belong to the expected repository and tag.")
        }
        // Older releases may predate the PKG format. They cannot be upgrades.
        guard version > current else { return nil }
        let filename = "LokiDot-Zoomies-\(version)-macos-\(architecture).pkg"
        let matches = feed.assets.filter { $0.name == filename }
        guard matches.count == 1, let asset = matches.first, asset.state == "uploaded",
              asset.size > 0, asset.size <= maximumPackageBytes else {
            throw UpdateError("A complete, supported installer is not available for this Mac.")
        }
        let expectedURL = "https://github.com/ashrocket/lokidot-zoomies/releases/download/v\(version)/\(filename)"
        guard asset.browser_download_url == expectedURL, let url = URL(string: expectedURL) else {
            throw UpdateError("The installer URL does not match the expected release.")
        }
        guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.utf8.count == 71,
              digest.dropFirst(7).utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw UpdateError("GitHub has not supplied a valid SHA-256 digest for this installer.")
        }
        return UpdateRelease(version: version, filename: filename, downloadURL: url,
                             size: asset.size, sha256: String(digest.dropFirst(7)).lowercased())
    }

    /// Only exact HTTPS asset delivery hosts; never suffix matching or credentials.
    public static func allowsAssetRedirect(to url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { return false }
        return ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"].contains(url.host ?? "")
    }
}

/// Incremental verification bounds memory and refuses both truncated and oversized data.
public struct UpdateIntegrityVerifier {
    private var hash = SHA256()
    private var count = 0
    private let release: UpdateRelease
    public init(release: UpdateRelease) { self.release = release }
    public mutating func append(_ data: Data) throws {
        guard data.count <= release.size - count else { throw UpdateError("The downloaded installer exceeds its declared size.") }
        count += data.count
        hash.update(data: data)
    }
    public func finish() throws {
        guard count == release.size else { throw UpdateError("The installer download is incomplete.") }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else { throw UpdateError("The installer failed SHA-256 verification. It will not be opened.") }
    }
}
