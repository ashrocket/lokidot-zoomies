import XCTest
@testable import ZoomiesCore

final class UpdateReleaseTests: XCTestCase {
    private let digest = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private func asset(architecture: String = "arm64") -> [String: Any] {
        let name = "LokiDot-Zoomies-1.4.0-macos-\(architecture).pkg"
        return ["name": name, "browser_download_url": "https://github.com/ashrocket/lokidot-zoomies/releases/download/v1.4.0/\(name)",
                "state": "uploaded", "size": 3, "digest": digest]
    }
    private func feed(_ overrides: [String: Any] = [:], assets: [[String: Any]]? = nil) throws -> Data {
        var value: [String: Any] = ["tag_name": "v1.4.0", "html_url": "https://github.com/ashrocket/lokidot-zoomies/releases/tag/v1.4.0",
                                    "draft": false, "prerelease": false, "assets": assets ?? [asset()]]
        value.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func parse(_ data: Data, current: String = "1.3.2", architecture: String = "arm64") throws -> UpdateRelease? {
        try UpdateRelease.parse(data, currentVersion: current, architecture: architecture)
    }

    func testVersionOrderingIsNumericAcrossEveryComponent() throws {
        let values = ["0.9.9", "1.0.0", "1.3.2", "1.3.10", "1.4.0", "1.10.0", "2.0.0", "10.0.0"]
        let versions = try values.map(UpdateVersion.init)
        XCTAssertEqual(versions.reversed().sorted().map(\.description), values)
        XCTAssertEqual(try UpdateVersion("1.3.2"), try UpdateVersion("1.3.2"))
    }

    func testRejectsNonCanonicalAndOverflowVersions() {
        for value in ["v1.2.3", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "1.2.3-beta", "1.2.3+build",
                      "1.2.3\n", " 1.2.3", "+1.2.3", "-1.2.3", "1..3", "١.2.3", "18446744073709551616.0.0"] {
            XCTAssertThrowsError(try UpdateVersion(value), value)
        }
    }

    func testValidFeedSelectsExactArchitecture() throws {
        let data = try feed(assets: [asset(), asset(architecture: "x86_64")])
        for arch in ["arm64", "x86_64"] {
            let result = try XCTUnwrap(parse(data, architecture: arch))
            XCTAssertEqual(result.version.description, "1.4.0")
            XCTAssertEqual(result.filename, "LokiDot-Zoomies-1.4.0-macos-\(arch).pkg")
            XCTAssertEqual(result.size, 3)
            XCTAssertEqual(result.sha256, String(digest.dropFirst(7)))
        }
        XCTAssertThrowsError(try parse(data, architecture: "i386"))
    }

    func testNoUpgradeForSameOrOlderVersion() throws {
        XCTAssertNil(try parse(feed(), current: "1.4.0"))
        XCTAssertNil(try parse(feed(assets: []), current: "2.0.0"))
        XCTAssertThrowsError(try parse(feed(), current: "unknown"))
    }

    func testRejectsDraftPrereleaseAndInvalidTags() throws {
        XCTAssertThrowsError(try parse(feed(["draft": true])))
        XCTAssertThrowsError(try parse(feed(["prerelease": true])))
        for tag in ["1.4.0", "vv1.4.0", "v1.4.0-beta", "v1.04.0", "v1.4.0/evil"] {
            XCTAssertThrowsError(try parse(feed(["tag_name": tag])), tag)
        }
    }

    func testRejectsWrongRepositoryOrReleasePage() throws {
        for page in ["https://github.com/other/lokidot-zoomies/releases/tag/v1.4.0", "https://github.com/ashrocket/other/releases/tag/v1.4.0",
                     "https://github.com/ashrocket/lokidot-zoomies/releases/tag/v1.5.0", "http://github.com/ashrocket/lokidot-zoomies/releases/tag/v1.4.0"] {
            XCTAssertThrowsError(try parse(feed(["html_url": page])))
        }
    }

    func testRequiresOneUploadedMatchingAsset() throws {
        XCTAssertThrowsError(try parse(feed(assets: [])))
        XCTAssertThrowsError(try parse(feed(assets: [asset(), asset()])))
        XCTAssertThrowsError(try parse(feed(assets: [asset(architecture: "x86_64")])))
        for (key, value) in [("state", "new"), ("name", "LokiDot-Zoomies-1.5.0-macos-arm64.pkg"), ("name", "../installer.pkg")] {
            var bad = asset(); bad[key] = value
            XCTAssertThrowsError(try parse(feed(assets: [bad])))
        }
    }

    func testRejectsAlteredAssetURL() throws {
        let good = asset()["browser_download_url"] as! String
        for value in [good.replacingOccurrences(of: "ashrocket", with: "other"), good.replacingOccurrences(of: "/v1.4.0/", with: "/v1.5.0/"),
                      good.replacingOccurrences(of: "https:", with: "http:"), good + "?download=1", good + "#fragment",
                      good.replacingOccurrences(of: "github.com", with: "github.com.evil.example"), good.replacingOccurrences(of: "github.com", with: "user@github.com")] {
            var bad = asset(); bad["browser_download_url"] = value
            XCTAssertThrowsError(try parse(feed(assets: [bad])))
        }
    }

    func testRequiresBoundedPositiveSize() throws {
        for size in [-1, 0, UpdateRelease.maximumPackageBytes + 1] {
            var bad = asset(); bad["size"] = size
            XCTAssertThrowsError(try parse(feed(assets: [bad])))
        }
        var maximum = asset(); maximum["size"] = UpdateRelease.maximumPackageBytes
        XCTAssertNotNil(try parse(feed(assets: [maximum])))
    }

    func testRequiresSHA256Digest() throws {
        let invalid: [Any] = [NSNull(), "", "sha256:abc", "sha512:" + String(repeating: "a", count: 64),
                              "sha256:" + String(repeating: "g", count: 64), digest + "\n"]
        for value in invalid {
            var bad = asset(); bad["digest"] = value
            XCTAssertThrowsError(try parse(feed(assets: [bad])))
        }
        var missing = asset(); missing.removeValue(forKey: "digest")
        XCTAssertThrowsError(try parse(feed(assets: [missing])))
    }

    func testRejectsOversizedOrMalformedMetadata() {
        XCTAssertThrowsError(try parse(Data(repeating: 32, count: UpdateRelease.maximumMetadataBytes + 1)))
        XCTAssertThrowsError(try parse(Data("{broken".utf8)))
        XCTAssertThrowsError(try parse(Data("{}".utf8)))
    }

    func testStreamingDigestAcceptsExactBytes() throws {
        var verifier = UpdateIntegrityVerifier(release: try XCTUnwrap(parse(feed())))
        try verifier.append(Data("a".utf8)); try verifier.append(Data("bc".utf8))
        XCTAssertNoThrow(try verifier.finish())
    }

    func testDigestMismatchTruncationAndOverflowFailClosed() throws {
        let release = try XCTUnwrap(parse(feed()))
        var mismatch = UpdateIntegrityVerifier(release: release)
        try mismatch.append(Data("abd".utf8))
        XCTAssertThrowsError(try mismatch.finish())
        var truncated = UpdateIntegrityVerifier(release: release)
        try truncated.append(Data("ab".utf8))
        XCTAssertThrowsError(try truncated.finish())
        var oversized = UpdateIntegrityVerifier(release: release)
        XCTAssertThrowsError(try oversized.append(Data("abcd".utf8)))
    }

    func testAssetRedirectsUseExactHTTPSHosts() {
        for host in ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"] {
            XCTAssertTrue(UpdateRelease.allowsAssetRedirect(to: URL(string: "https://\(host)/asset?signature=token")!))
        }
        for value in ["http://release-assets.githubusercontent.com/a", "https://release-assets.githubusercontent.com.evil.example/a",
                      "https://evil.example/a", "https://github.com/other/repo", "https://user@objects.githubusercontent.com/a",
                      "https://objects.githubusercontent.com:8443/a", "https://objects.githubusercontent.com/a#fragment", "file:///tmp/a"] {
            XCTAssertFalse(UpdateRelease.allowsAssetRedirect(to: URL(string: value)!))
        }
    }
}
