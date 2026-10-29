import AppKit
import Foundation
import ZoomiesCore

let help = """
LokiDot Zoomies — a little pack of desktop companions

  lokidot                       Open the playground
  lokidot all [zoomies|circle|prance]
  lokidot zoomies [all|robot-loki|beagle|whippet]
  lokidot circle [all|robot-loki|beagle|whippet]
  lokidot prance [all|robot-loki|beagle|whippet]
  lokidot dog FOLDER [zoomies|circle|prance]
  lokidot pause | resume | quit | status
  lokidot validate FOLDER        Check your dog's sprite pack
  lokidot new-dog FOLDER [NAME]   Make a starter pack you can draw over
  lokidot dog-prompt             Print a setup prompt for your agent
  lokidot --version | --help

Commands reach the running app; they do not create duplicate pets.
Prancing needs the jumping poses in a complete pet-v2 pack.
"""

func fail(_ message: String, code: Int32 = 1) -> Never { fputs("lokidot: \(message)\n", stderr); exit(code) }
func appURL() throws -> URL {
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
        throw SpritePackError("Cannot locate the app. Re-run ./lokidot install from the project folder.")
    }
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier != nil else {
        throw SpritePackError("This launcher belongs inside LokiDot Zoomies.app. Re-run ./lokidot install.")
    }
    return app
}
func style(_ raw: String) throws -> MotionStyle {
    guard let value = MotionStyle(rawValue: raw) else { throw SpritePackError("Choose zoomies, circle, or prance.") }
    return value
}
func folder(_ raw: String) -> URL { URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath, isDirectory: true).standardizedFileURL }

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "show"
if ["--help", "-h", "help"].contains(command) { print(help); exit(0) }

do {
    let app = try appURL()
    let bundle = Bundle(url: app)!
    let id = bundle.bundleIdentifier!
    if command == "--version" {
        print("LokiDot Zoomies \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown")"); exit(0)
    }
    if command == "dog-prompt" {
        guard args.count == 1 else { throw SpritePackError("Usage: lokidot dog-prompt") }
        let url = app.appendingPathComponent("Contents/Resources/DogSetupPrompt.txt")
        print(try String(contentsOf: url, encoding: .utf8)); exit(0)
    }
    if ["status", "quit"].contains(command) {
        guard args.count == 1 else { throw SpritePackError("Usage: lokidot \(command)") }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        if command == "status" {
            if running.isEmpty { print("LokiDot is resting offscreen. Run lokidot to wake it up."); exit(1) }
            print("LokiDot is running (\(running.map { String($0.processIdentifier) }.joined(separator: ", "))).")
        } else {
            for process in running { guard process.terminate() else { throw SpritePackError("Quit LokiDot from its paw menu, then try again.") } }
            let deadline = Date().addingTimeInterval(5)
            while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            guard running.allSatisfy(\.isTerminated) else { throw SpritePackError("LokiDot is still closing. Quit it from the paw menu; it has not been force-stopped.") }
            print(running.isEmpty ? "LokiDot is already closed." : "LokiDot has gone for a nap.")
        }
        exit(0)
    }
    if command == "validate" {
        guard args.count == 2 else { throw SpritePackError("Usage: lokidot validate FOLDER") }
        let pack = try SpritePack.load(directory: folder(args[1]))
        print("VALID: \(pack.manifest.name). Ready for zoomies and little circles\(pack.frames["jumping"] == nil ? "." : ", plus happy prancing.")")
        exit(0)
    }
    if command == "new-dog" {
        guard (2...3).contains(args.count) else { throw SpritePackError("Usage: lokidot new-dog NEW_FOLDER [NAME]") }
        let destination = folder(args[1])
        let name = args.count == 3 ? args[2] : destination.lastPathComponent
        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/SpritePackTool")
        process.arguments = ["sample", destination.path, name]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
        print("Your starter is in \(destination.path)\nReplace atlas.png with your dog, keeping the grid and transparent background.\nThen: lokidot validate \(destination.path.debugDescription)\nTry it: lokidot dog \(destination.path.debugDescription)")
        exit(0)
    }
    let request: LaunchRequest
    switch command {
    case "show", "start", "play":
        guard args.count <= 2 else { throw SpritePackError("Usage: lokidot \(command) [zoomies|circle|prance]") }
        request = try LaunchRequest(action: command == "show" ? .show : .play,
                                    motion: args.count == 2 ? try style(args[1]) : nil)
    case "all", "--all-ready":
        guard args.count <= 2 else { throw SpritePackError("Usage: lokidot all [zoomies|circle|prance]") }
        request = try LaunchRequest(action: .play, motion: args.count == 2 ? try style(args[1]) : nil, character: "all")
    case "zoomies", "circle", "prance":
        guard args.count <= 2 else { throw SpritePackError("Usage: lokidot \(command) [all|robot-loki|beagle|whippet]") }
        request = try LaunchRequest(action: .play, motion: try style(command), character: args.count == 2 ? args[1] : nil)
    case "dog", "--pack":
        guard (2...3).contains(args.count) else { throw SpritePackError("Usage: lokidot dog FOLDER [zoomies|circle|prance]") }
        let path = folder(args[1])
        let pack = try SpritePack.load(directory: path)
        let motion = args.count == 3 ? try style(args[2]) : .zoomies
        guard motion != .prance || pack.frames["jumping"] != nil else { throw SpritePackError("This pack has no jumping poses. Try zoomies or circle.") }
        request = try LaunchRequest(action: .play, motion: motion, packPath: path.path)
    case "pause", "resume":
        guard args.count == 1 else { throw SpritePackError("Usage: lokidot \(command)") }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else {
            throw SpritePackError("LokiDot is not running. Start it with lokidot first.")
        }
        request = try LaunchRequest(action: command == "pause" ? .pause : .resume)
    default: fail("Unknown command \(command). Run lokidot --help.", code: 2)
    }
    // LaunchServices can otherwise route a new build's URL to an older copy
    // with the same bundle id. Close only that copy, politely, before switching.
    let olderCopies = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter {
        $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL != app.standardizedFileURL
    }
    for process in olderCopies {
        guard process.terminate() else { throw SpritePackError("Quit the older LokiDot from its paw menu, then launch this build.") }
    }
    let switchDeadline = Date().addingTimeInterval(5)
    while olderCopies.contains(where: { !$0.isTerminated }) && Date() < switchDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard olderCopies.allSatisfy(\.isTerminated) else { throw SpritePackError("The older LokiDot is still closing; it has not been force-stopped.") }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = request.action == .show
    configuration.arguments = ["--background"]
    var completed = false
    var launchError: Error?
    NSWorkspace.shared.open([request.url], withApplicationAt: app, configuration: configuration) { _, error in
        launchError = error; completed = true
    }
    let deadline = Date().addingTimeInterval(15)
    while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard completed else { throw SpritePackError("macOS has not confirmed launch yet. Check the app before retrying.") }
    if let error = launchError { throw error }
    print(request.action == .show ? "Opening the LokiDot playground." : "Sent \(request.motion?.title.lowercased() ?? request.action.rawValue) to LokiDot.")
} catch { fail(error.localizedDescription) }
