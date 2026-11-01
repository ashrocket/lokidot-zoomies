import Foundation
import Darwin
import ZoomiesCore

// Invoked by scripts/test.sh. Only synthetic private temporary files are touched.
// The production verifier is compiled into this probe; network and Installer stay unused.
@main enum StagingProbe {
    static func main() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LokiDot-staging-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "LokiDot-Zoomies-1.4.0-macos-arm64.pkg"
        let json: [String: Any] = ["tag_name": "v1.4.0", "html_url": "https://github.com/ashrocket/lokidot-zoomies/releases/tag/v1.4.0", "draft": false, "prerelease": false,
            "assets": [["name": name, "state": "uploaded", "size": 3, "digest": "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "browser_download_url": "https://github.com/ashrocket/lokidot-zoomies/releases/download/v1.4.0/\(name)"]]]
        let release = try UpdateRelease.parse(JSONSerialization.data(withJSONObject: json), currentVersion: "1.3.2", architecture: "arm64")!
        func fixture(_ name: String, bytes: String = "abc", mode: Int = 0o600, quarantine: Bool = true) throws -> URL {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: url.path, contents: Data(bytes.utf8), attributes: [.posixPermissions: mode]) else { fatalError("fixture creation failed") }
            if quarantine {
                let value = "0083;0;LokiDot staging test;\(UUID().uuidString)"
                guard value.withCString({ setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }) == 0 else { fatalError("quarantine setup failed") }
            }
            return url
        }
        func rejected(_ title: String, _ url: URL) throws {
            do { try UpdateTransport.verifyStagedPackage(at: url, release: release) }
            catch { print("PASS \(title): rejected"); return }
            throw UpdateError("FAIL \(title): unexpectedly accepted")
        }
        let valid = try fixture("valid.pkg")
        try UpdateTransport.verifyStagedPackage(at: valid, release: release)
        print("PASS valid private quarantined fixture")
        try rejected("changed bytes", fixture("changed.pkg", bytes: "abd"))
        try rejected("truncated bytes", fixture("truncated.pkg", bytes: "ab"))
        try rejected("missing quarantine", fixture("unquarantined.pkg", quarantine: false))
        try rejected("permissive mode", fixture("public.pkg", mode: 0o644))
        let symlink = directory.appendingPathComponent("symlink.pkg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: valid)
        try rejected("symlink", symlink)
        let hardlink = directory.appendingPathComponent("hardlink.pkg")
        try FileManager.default.linkItem(at: valid, to: hardlink)
        try rejected("hardlink", hardlink)
        let fifo = directory.appendingPathComponent("fifo.pkg")
        guard mkfifo(fifo.path, 0o600) == 0 else { fatalError("FIFO setup failed") }
        try rejected("FIFO", fifo)
        print("PASS all 8 staged-file checks; no network or Installer used")
    }
}
