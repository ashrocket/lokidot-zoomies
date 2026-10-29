import Foundation

/// The only commands accepted from a local launch URL. No executable text,
/// network resource, diagnostics destination, or arbitrary setting is accepted.
public struct LaunchRequest: Equatable {
    public enum Action: String { case show, play, pause, resume, quit }
    public let action: Action
    public let motion: MotionStyle?
    public let character: String?
    public let packPath: String?

    public init(action: Action = .show, motion: MotionStyle? = nil,
                character: String? = nil, packPath: String? = nil) throws {
        guard character == nil || packPath == nil else {
            throw SpritePackError("Choose one character, all, or one dog folder.")
        }
        if let character {
            guard character.range(of: "^[a-z][a-z0-9-]{0,31}$", options: .regularExpression) != nil else {
                throw SpritePackError("Use a character id such as beagle, whippet, robot-loki, or all.")
            }
        }
        if let packPath {
            guard packPath.hasPrefix("/"), packPath.utf8.count <= 4096,
                  !packPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SpritePackError("A dog folder must be an absolute local path.")
            }
        }
        guard action == .show || action == .play || (motion == nil && character == nil && packPath == nil) else {
            throw SpritePackError("Pause, resume, and quit do not accept character or motion options.")
        }
        self.action = action; self.motion = motion; self.character = character; self.packPath = packPath
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = "lokidot"; parts.host = "control"; parts.path = "/" + action.rawValue
        var items = [URLQueryItem]()
        if let motion { items.append(URLQueryItem(name: "motion", value: motion.rawValue)) }
        if let character { items.append(URLQueryItem(name: "character", value: character)) }
        if let packPath { items.append(URLQueryItem(name: "pack", value: packPath)) }
        if !items.isEmpty { parts.queryItems = items }
        return parts.url!
    }

    public init(url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "lokidot", parts.host == "control", parts.user == nil,
              parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.path.hasPrefix("/"), let action = Action(rawValue: String(parts.path.dropFirst())) else {
            throw SpritePackError("That is not a supported LokiDot command.")
        }
        var fields = [String: String]()
        for item in parts.queryItems ?? [] {
            guard ["motion", "character", "pack"].contains(item.name),
                  fields[item.name] == nil, let value = item.value, !value.isEmpty else {
                throw SpritePackError("Unknown, empty, or repeated LokiDot command option.")
            }
            fields[item.name] = value
        }
        let motion = fields["motion"].flatMap(MotionStyle.init(rawValue:))
        guard fields["motion"] == nil || motion != nil else { throw SpritePackError("Choose zoomies, circle, or prance.") }
        try self.init(action: action, motion: motion, character: fields["character"], packPath: fields["pack"])
    }
}
