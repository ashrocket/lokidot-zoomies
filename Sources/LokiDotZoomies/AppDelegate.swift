import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ZoomiesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CAAnimationDelegate {
    enum Mode: String { case running, resting, pausedRun, pausedRest, reducedMotion, needsArtwork }
    private var mode: Mode = .resting
    private var repeatEnabled = true
    private var overlay: Overlay?
    private var artwork: SpriteArtwork?
    private var selectedDisplay: CGDirectDisplayID?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusLabel: NSMenuItem!
    private var zoomiesItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var repeatItem: NSMenuItem!
    private var displayItem: NSMenuItem!
    private var restTimer: Timer?
    private var restDeadline: TimeInterval?
    private var restRemaining = MotionRoute.restDuration
    private var resumeAfterWake = false
    private let forcedReducedMotion = CommandLine.arguments.contains("--reduce-motion")
    private var reducedMotion: Bool {
        forcedReducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch must not produce a second mascot or menu-bar item.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.ashrocket.LokiDotZoomies")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "LokiDot Zoomies")
        statusItem.button?.title = " Loki"
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("LokiDot Zoomies")
        statusItem.menu = menu
        menu.delegate = self
        buildMenu()
        if let url = SpriteArtwork.initialURL() { artwork = try? SpriteArtwork(url: url) }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        configureDisplay()
        updateMenu()

        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.writeDiagnostics(to: url) }
            }
        }
    }

    private func configureDisplay() {
        guard let artwork else { mode = .needsArtwork; updateMenu(); return }
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { displayID($0) == selectedDisplay })
            ?? screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? screens.first else { return }
        let wasPaused = mode == .pausedRun || mode == .pausedRest
        restTimer?.invalidate()
        restTimer = nil
        mode = .resting
        overlay?.settle()
        overlay?.window.close()
        selectedDisplay = displayID(screen)
        overlay = Overlay(screen: screen, artwork: artwork)
        rebuildDisplayMenu()
        overlay?.window.orderFrontRegardless()
        if reducedMotion { mode = .reducedMotion }
        else if wasPaused { mode = .pausedRest }
        else { startLap() }
        updateMenu()
    }

    private func startLap() {
        guard artwork != nil else { mode = .needsArtwork; updateMenu(); return }
        guard !reducedMotion else { mode = .reducedMotion; updateMenu(); return }
        restTimer?.invalidate()
        restTimer = nil
        restDeadline = nil
        mode = .running
        overlay?.run(delegate: self)
        updateMenu()
    }

    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        Task { @MainActor [weak self] in self?.lapFinished() }
    }

    private func lapFinished() {
        guard mode == .running else { return }
        mode = .resting
        overlay?.settle()
        if repeatEnabled { scheduleRest(seconds: MotionRoute.restDuration) }
        updateMenu()
    }

    private func scheduleRest(seconds: TimeInterval) {
        restTimer?.invalidate()
        restRemaining = seconds
        restDeadline = ProcessInfo.processInfo.systemUptime + seconds
        restTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .resting, self.repeatEnabled else { return }
                self.startLap()
            }
        }
        restTimer?.tolerance = 0.5
    }

    @objc private func zoomies() {
        switch mode {
        case .pausedRun: togglePause()
        case .resting, .pausedRest: startLap()
        case .running, .reducedMotion, .needsArtwork: break
        }
    }

    @objc private func togglePause() {
        switch mode {
        case .running:
            overlay?.pause()
            mode = .pausedRun
        case .pausedRun:
            overlay?.resume()
            mode = .running
        case .resting:
            restRemaining = restDeadline.map { max(0.1, $0 - ProcessInfo.processInfo.systemUptime) } ?? MotionRoute.restDuration
            restTimer?.invalidate()
            restTimer = nil
            mode = .pausedRest
        case .pausedRest:
            mode = .resting
            if repeatEnabled { scheduleRest(seconds: restRemaining) }
        case .reducedMotion, .needsArtwork: break
        }
        updateMenu()
    }

    @objc private func toggleRepeat() {
        repeatEnabled.toggle()
        if mode == .resting {
            if repeatEnabled { scheduleRest(seconds: MotionRoute.restDuration) }
            else { restTimer?.invalidate(); restTimer = nil; restDeadline = nil }
        }
        updateMenu()
    }

    @objc private func selectDisplay(_ item: NSMenuItem) {
        selectedDisplay = item.representedObject as? CGDirectDisplayID
        configureDisplay()
    }

    @objc private func displaysChanged() { configureDisplay() }

    @objc private func accessibilityChanged() {
        guard artwork != nil else { return }
        if reducedMotion {
            restTimer?.invalidate()
            restTimer = nil
            mode = .reducedMotion
            overlay?.settle(keepPosition: true)
        } else if mode == .reducedMotion {
            overlay?.settle()
            startLap()
        }
        updateMenu()
    }

    @objc private func sleeping() {
        if mode == .running || mode == .resting {
            resumeAfterWake = true
            togglePause()
        }
        overlay?.window.orderOut(nil)
    }

    @objc private func waking() {
        overlay?.window.orderFrontRegardless()
        if resumeAfterWake {
            resumeAfterWake = false
            if mode == .pausedRun || mode == .pausedRest { togglePause() }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.title = "Choose Loki Artwork"
        panel.message = "Choose your local pet sprite sheet. It stays on this Mac."
        panel.allowedContentTypes = [.png]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            artwork = try SpriteArtwork(url: url)
            configureDisplay()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Artwork could not be loaded"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        restTimer?.invalidate()
        overlay?.window.close()
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }

    private func buildMenu() {
        menu.autoenablesItems = false
        statusLabel = NSMenuItem(title: "LokiDot Zoomies", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())
        zoomiesItem = add("Zoomies!", action: #selector(zoomies), key: "z")
        pauseItem = add("Pause", action: #selector(togglePause), key: "p")
        repeatItem = add("Repeat gently", action: #selector(toggleRepeat), key: "r")
        menu.addItem(.separator())
        displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        menu.addItem(displayItem)
        add("Choose Loki Artwork…", action: #selector(chooseArtwork), key: "")
        menu.addItem(.separator())
        // A background pet should not consume Command-Q intended for another app.
        add("Quit LokiDot Zoomies", action: #selector(quit), key: "")
        rebuildDisplayMenu()
    }

    private func updateMenu() {
        guard statusLabel != nil else { return }
        let status: String
        switch mode {
        case .running: status = "LokiDot is doing zoomies"
        case .resting: status = repeatEnabled ? "Catching a breath · repeats gently" : "LokiDot is resting"
        case .pausedRun, .pausedRest: status = "LokiDot is paused"
        case .reducedMotion: status = "Resting · Reduce Motion is on"
        case .needsArtwork: status = "Choose Loki Artwork to begin"
        }
        // Keep menu item identities and positions stable while tracking a menu.
        statusLabel.title = status
        zoomiesItem.isEnabled = mode != .needsArtwork && mode != .reducedMotion && mode != .running
        let paused = mode == .pausedRun || mode == .pausedRest
        pauseItem.title = paused ? "Resume" : "Pause"
        pauseItem.isEnabled = mode != .needsArtwork && mode != .reducedMotion
        repeatItem.isEnabled = mode != .needsArtwork
        repeatItem.state = repeatEnabled ? .on : .off
        statusItem.button?.toolTip = "LokiDot Zoomies — \(status)"
    }

    private func rebuildDisplayMenu() {
        let displays = NSMenu()
        for (index, screen) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title: "\(screen.localizedName) (\(index + 1))", action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = displayID(screen)
            item.state = displayID(screen) == selectedDisplay ? .on : .off
            displays.addItem(item)
        }
        displayItem.submenu = displays
    }

    @discardableResult
    private func add(_ title: String, action: Selector, key: String, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        menu.autoenablesItems = false
        menu.addItem(item)
        return item
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func writeDiagnostics(to url: URL) {
        guard let overlay else { return }
        let position = overlay.pet.presentation()?.position ?? overlay.pet.position
        let report: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "mode": mode.rawValue,
            "reduceMotion": reducedMotion,
            "repeatEnabled": repeatEnabled,
            "windowNumber": overlay.window.windowNumber,
            "windowVisible": overlay.window.isVisible,
            "clickThrough": overlay.window.ignoresMouseEvents,
            "canBecomeKey": overlay.window.canBecomeKey,
            "windowLevel": overlay.window.level.rawValue,
            "displayCount": NSScreen.screens.count,
            "visibleFrame": NSStringFromRect(overlay.window.frame),
            "petPosition": NSStringFromPoint(position),
            "hasLapAnimation": overlay.pet.animation(forKey: "zoomies") != nil,
            "activeRestTimer": restTimer?.isValid ?? false
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { NSLog("Could not write requested diagnostics: %@", error.localizedDescription) }
    }
}
