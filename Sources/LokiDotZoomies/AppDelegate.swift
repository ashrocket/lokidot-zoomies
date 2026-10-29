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
    private var characterItem: NSMenuItem!
    private var characters: [SpriteArtwork] = []
    private var rejectedDefaults = 0
    private var showAllCharacters = CommandLine.arguments.contains("--all-ready") || UserDefaults.standard.bool(forKey: "showAllCharacters")
    private var activeArtworks: [SpriteArtwork] {
        showAllCharacters ? characters : artwork.map { [$0] } ?? []
    }
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
        statusItem.button?.title = " Zoomies"
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("LokiDot Zoomies")
        statusItem.menu = menu
        menu.delegate = self
        loadCharacters()
        buildMenu()
        loadInitialArtwork()
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
        guard !activeArtworks.isEmpty else { mode = .needsArtwork; updateMenu(); return }
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
        overlay = Overlay(screen: screen, artworks: activeArtworks)
        rebuildDisplayMenu()
        overlay?.window.orderFrontRegardless()
        if reducedMotion { mode = .reducedMotion }
        else if wasPaused { mode = .pausedRest }
        else { startLap() }
        updateMenu()
    }

    private func startLap() {
        guard !activeArtworks.isEmpty else { mode = .needsArtwork; updateMenu(); return }
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
        guard !activeArtworks.isEmpty else { return }
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
        panel.title = "Import Sprite Pack"
        panel.message = "Choose a folder containing manifest.json and a complete PNG sprite set."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            artwork = try SpriteArtwork(url: url)
            showAllCharacters = false
            UserDefaults.standard.set(false, forKey: "showAllCharacters")
            UserDefaults.standard.set(url.path, forKey: "selectedSpritePackPath")
            UserDefaults.standard.removeObject(forKey: "selectedCharacterID")
            rebuildCharacterMenu()
            configureDisplay()
        } catch {
            showArtworkError(error)
        }
    }

    private func loadCharacters() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true),
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for url in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                let candidate = try SpriteArtwork(url: url)
                guard !characters.contains(where: { $0.pack.manifest.id == candidate.pack.manifest.id }) else {
                    rejectedDefaults += 1; continue
                }
                characters.append(candidate)
            } catch { rejectedDefaults += 1 }
        }
    }

    private func loadInitialArtwork() {
        do {
            // Explicit input and saved choices never silently fall back to Loki.
            if CommandLine.arguments.contains("--pack"), let url = SpriteArtwork.initialURL() {
                artwork = try SpriteArtwork(url: url)
                showAllCharacters = false
            } else if let saved = UserDefaults.standard.string(forKey: "selectedSpritePackPath") {
                artwork = try SpriteArtwork(url: URL(fileURLWithPath: saved, isDirectory: true))
            } else if let id = UserDefaults.standard.string(forKey: "selectedCharacterID") {
                guard let selected = characters.first(where: { $0.pack.manifest.id == id }) else {
                    throw SpritePackError("The saved character is unavailable. Choose a ready character or import a complete pack.")
                }
                artwork = selected
            } else if let url = SpriteArtwork.initialURL() {
                artwork = try SpriteArtwork(url: url)
            } else {
                artwork = characters.first(where: { $0.pack.manifest.id == "robot-loki" }) ?? characters.first
            }
        } catch { showArtworkError(error) }
        if characters.isEmpty { showAllCharacters = false }
        rebuildCharacterMenu()
    }

    @objc private func selectCharacter(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let selected = characters.first(where: { $0.pack.manifest.id == id }) else { return }
        artwork = selected
        showAllCharacters = false
        UserDefaults.standard.set(false, forKey: "showAllCharacters")
        UserDefaults.standard.set(id, forKey: "selectedCharacterID")
        UserDefaults.standard.removeObject(forKey: "selectedSpritePackPath")
        rebuildCharacterMenu()
        configureDisplay()
    }

    @objc private func selectAllCharacters() {
        guard characters.count > 1 else { return }
        showAllCharacters = true
        UserDefaults.standard.set(true, forKey: "showAllCharacters")
        rebuildCharacterMenu()
        configureDisplay()
    }

    private func showArtworkError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Sprite pack could not be loaded"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func rebuildCharacterMenu() {
        guard characterItem != nil else { return }
        let choices = NSMenu()
        choices.autoenablesItems = false
        let all = NSMenuItem(title: "Show All Ready Characters", action: #selector(selectAllCharacters), keyEquivalent: "")
        all.target = self
        all.isEnabled = characters.count > 1
        all.state = showAllCharacters ? .on : .off
        choices.addItem(all)
        choices.addItem(.separator())
        for candidate in characters {
            let item = NSMenuItem(title: candidate.name, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.pack.manifest.id
            item.state = !showAllCharacters && artwork?.sourceURL == candidate.sourceURL ? .on : .off
            choices.addItem(item)
        }
        if let artwork, !characters.contains(where: { $0.sourceURL == artwork.sourceURL }) {
            let current = NSMenuItem(title: "\(artwork.name) · Imported", action: nil, keyEquivalent: "")
            current.state = showAllCharacters ? .off : .on; current.isEnabled = false
            choices.addItem(current)
        }
        if rejectedDefaults > 0 {
            let notice = NSMenuItem(title: "\(rejectedDefaults) incomplete pack(s) unavailable", action: nil, keyEquivalent: "")
            notice.isEnabled = false; choices.addItem(notice)
        }
        choices.addItem(.separator())
        let importer = NSMenuItem(title: "Import Sprite Pack…", action: #selector(chooseArtwork), keyEquivalent: "")
        importer.target = self
        choices.addItem(importer)
        characterItem.submenu = choices
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
        characterItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        menu.addItem(characterItem)
        rebuildCharacterMenu()
        menu.addItem(.separator())
        // A background pet should not consume Command-Q intended for another app.
        add("Quit LokiDot Zoomies", action: #selector(quit), key: "")
        rebuildDisplayMenu()
    }

    private func updateMenu() {
        guard statusLabel != nil else { return }
        let status: String
        let petName = showAllCharacters ? "\(characters.count) pets" : artwork?.name ?? "Your pet"
        let verb = showAllCharacters ? "are" : "is"
        switch mode {
        case .running: status = "\(petName) \(verb) doing zoomies"
        case .resting: status = repeatEnabled ? "Catching a breath · repeats gently" : "\(petName) \(verb) resting"
        case .pausedRun, .pausedRest: status = "\(petName) \(verb) paused"
        case .reducedMotion: status = "Resting · Reduce Motion is on"
        case .needsArtwork: status = "Import a complete sprite pack to begin"
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
        statusItem.button?.title = showAllCharacters ? " All Pets" : " \(String((artwork?.name ?? "Zoomies").prefix(16)))"
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
            "characterCount": overlay.petCount,
            "showAllCharacters": showAllCharacters,
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
