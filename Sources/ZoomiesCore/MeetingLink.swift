import Foundation

/// Finds video-meeting join links in event text. Only https links on known
/// provider hosts count; everything else, including lookalike domains, is ignored.
public enum MeetingLink {
    /// Scans texts in order (nil skipped); within a text returns the first recognised join link.
    public static func find(in texts: [String?]) -> URL? {
        for case let text? in texts {
            if let url = firstLink(in: text) { return url }
        }
        return nil
    }

    /// Human name of the provider, or nil if the URL is not a recognised join link.
    public static func provider(for url: URL) -> String? {
        guard let resolved = resolve(url) else { return nil }
        return providerName(for: resolved)
    }

    private static let scanLimit = 65_536
    private static let linkStart = "https://"
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}"]
    private static let terminators: Set<Character> = ["\"", "'", "<", ">"]

    private static func firstLink(in text: String) -> URL? {
        let scan = text.prefix(scanLimit)
        var searchStart = scan.startIndex
        while let range = scan.range(of: linkStart, range: searchStart..<scan.endIndex) {
            if let url = link(in: scan, at: range.lowerBound) { return url }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func link(in scan: Substring, at start: String.Index) -> URL? {
        var end = start
        while end < scan.endIndex, !isTerminator(scan[end]) {
            end = scan.index(after: end)
        }
        var candidate = String(scan[start..<end])
        while let last = candidate.last, trailingPunctuation.contains(last) {
            candidate.removeLast()
        }
        candidate = candidate.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: candidate), let resolved = resolve(url),
              providerName(for: resolved) != nil else { return nil }
        return resolved
    }

    private static func isTerminator(_ character: Character) -> Bool {
        character.isWhitespace || terminators.contains(character)
    }

    /// Follows known redirectors (at most three levels) to the link they wrap.
    private static func resolve(_ url: URL, depth: Int = 0) -> URL? {
        guard depth < 3 else { return nil }
        guard let target = redirectTarget(of: url) else { return url }
        guard let inner = URL(string: target) else { return nil }
        return resolve(inner, depth: depth + 1)
    }

    private static func redirectTarget(of url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        if hostMatches(host, "safelinks.protection.outlook.com") {
            return queryValue("url", in: url)
        }
        if host == "www.google.com", url.path == "/url" {
            return queryValue("q", in: url)
        }
        return nil
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    private static func providerName(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        return providerName(host: host, path: url.path)
    }

    private static func providerName(host: String, path: String) -> String? {
        let rest = path.dropFirst()
        if matches(host, ["zoom.us", "zoomgov.com"]), hasPrefix(path, ["/j/", "/my/", "/w/", "/s/", "/wc/"]) {
            return "Zoom"
        }
        if matches(host, ["meet.google.com"]), isGoogleMeetCode(path) || path.hasPrefix("/lookup/") {
            return "Google Meet"
        }
        if matches(host, ["teams.microsoft.com"]), hasPrefix(path, ["/l/meetup-join/", "/meet/"]) {
            return "Microsoft Teams"
        }
        if matches(host, ["teams.live.com"]), path.hasPrefix("/meet/") {
            return "Microsoft Teams"
        }
        if matches(host, ["webex.com"]), ["/j.php", "/meet/", "/join/"].contains(where: { path.contains($0) }) {
            return "Webex"
        }
        if matches(host, ["chime.aws"]), isDigits(rest) {
            return "Amazon Chime"
        }
        if matches(host, ["whereby.com"]), hasTail(path) {
            return "Whereby"
        }
        if matches(host, ["meet.jit.si"]), hasTail(path) {
            return "Jitsi Meet"
        }
        if matches(host, ["app.slack.com"]), path.hasPrefix("/huddle/") {
            return "Slack Huddle"
        }
        if matches(host, ["facetime.apple.com"]), path.hasPrefix("/join") {
            return "FaceTime"
        }
        if matches(host, ["meet.goto.com"]), isDigits(rest) {
            return "GoTo Meeting"
        }
        if matches(host, ["gotomeeting.com"]), path.hasPrefix("/join/") {
            return "GoTo Meeting"
        }
        if matches(host, ["bluejeans.com"]), isBlueJeansRoom(rest) {
            return "BlueJeans"
        }
        return nil
    }

    private static func matches(_ host: String, _ domains: [String]) -> Bool {
        domains.contains { hostMatches(host, $0) }
    }

    private static func hostMatches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func hasPrefix(_ path: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { path.hasPrefix($0) }
    }

    private static func hasTail(_ path: String) -> Bool {
        !path.drop(while: { $0 == "/" }).isEmpty
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
    }

    /// Google Meet codes are three, four and three letters joined by hyphens.
    private static func isGoogleMeetCode(_ path: String) -> Bool {
        let parts = path.dropFirst().split(separator: "-", omittingEmptySubsequences: false)
        return parts.map(\.count) == [3, 4, 3] && parts.allSatisfy { $0.allSatisfy(\.isLetter) }
    }

    /// BlueJeans rooms are digits, optionally followed by a slash and more path.
    private static func isBlueJeansRoom(_ rest: Substring) -> Bool {
        guard let room = rest.split(separator: "/", maxSplits: 1).first else { return false }
        return isDigits(room)
    }
}
