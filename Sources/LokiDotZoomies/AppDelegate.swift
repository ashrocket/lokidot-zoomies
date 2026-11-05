import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ZoomiesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CAAnimationDelegate {
    enum Mode: String { case running, resting, pausedRun, pausedRest, reducedMotion, needsArtwork, unloaded }
    /// A pack the app can show. Listing reads manifests only; artwork is
    /// decoded when the pet actually runs and released when it leaves.
    struct Character {
        let id: String
        let name: String
        let url: URL
        let canPrance: Bool
        let trusted: Bool
    }
    private var mode: Mode = .resting
    /// Off by default: between reminders the whippet rests off screen, so the
    /// app keeps no overlay window, animation or decoded artwork.
    private var repeatEnabled = UserDefaults.standard.bool(forKey: "ambientRepeat")
    private var overlay: Overlay?
    private var selectedID: String?
    private var artworkCache: [String: SpriteArtwork] = [:]
    private var countdownTimer: Timer?
    private var selectedDisplay: CGDirectDisplayID?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusLabel: NSMenuItem!
    private var zoomiesItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var repeatItem: NSMenuItem!
    private var displayItem: NSMenuItem!
    private var characterItem: NSMenuItem!
    private var motionItem: NSMenuItem!
    private var playground: PlaygroundWindow?
    private let updates = UpdateController()
    private let calendarAlarms = CalendarAlarmController()
    private var pendingRequests: [LaunchRequest] = []
    private var motionStyle = MotionStyle(rawValue: UserDefaults.standard.string(forKey: "motionStyle") ?? "") ?? .zoomies
    private var canPrance: Bool { !activeCharacters.isEmpty && activeCharacters.allSatisfy(\.canPrance) }
    private var characters: [Character] = []
    private let petLibrary = SavedPetLibrary(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ashrocket.LokiDotZoomies", isDirectory: true)
        .appendingPathComponent("ImportedPets", isDirectory: true))
    private var savedPets: [SavedPet] = []
    private var savedCharacters: [String: Character] = [:]
    private var unloadedSavedPetIDs = Set(UserDefaults.standard.stringArray(forKey: "unloadedSavedPetIDs") ?? [])
    private var petsHidden = UserDefaults.standard.bool(forKey: "petsHidden")
    private var savedPetsWindow: SavedPetsWindow?
    private var readyCharacters: [Character] {
        characters + savedPets.compactMap { pet in
            unloadedSavedPetIDs.contains(pet.id) ? nil : savedCharacters[pet.id]
        }
    }
    private var selected: Character? { readyCharacters.first { $0.id == selectedID } }
    private var rejectedDefaults = 0
    private var showAllCharacters = CommandLine.arguments.contains("--all-ready") || UserDefaults.standard.bool(forKey: "showAllCharacters")
    private var activeCharacters: [Character] {
        showAllCharacters ? readyCharacters : selected.map { [$0] } ?? []
    }
    private var restTimer: Timer?
    private var restDeadline: TimeInterval?
    private var restRemaining = MotionRoute.restDuration
    private var resumeAfterWake = false
    private var screensAwake = true
    private var userSessionActive = true
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
        // The owner asked for the line-drawn whippet by default. Move every
        // existing install to it once; later choices are respected.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "whippetDefaultApplied") {
            defaults.set("whippet", forKey: "selectedCharacterID")
            defaults.set(false, forKey: "showAllCharacters")
            defaults.removeObject(forKey: "selectedSpritePackPath")
            defaults.set(true, forKey: "whippetDefaultApplied")
            showAllCharacters = CommandLine.arguments.contains("--all-ready")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = Bundle.main.url(forResource: "MenuBarWhippet", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        icon?.isTemplate = true
        icon?.size = NSSize(width: 26, height: 18)
        statusItem.button?.image = icon ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "LokiDot Zoomies")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("LokiDot Zoomies")
        statusItem.menu = menu
        menu.delegate = self
        loadCharacters()
        do { try reloadSavedPets() } catch { showArtworkError(error) }
        buildMenu()
        loadInitialArtwork()
        if let index = CommandLine.arguments.firstIndex(of: "--motion"),
           let style = MotionStyle(rawValue: CommandLine.arguments[index + 1]) { motionStyle = style }
        if motionStyle == .prance && !canPrance { motionStyle = .zoomies }
        buildApplicationMenu()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sleeping(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        if repeatEnabled { configureDisplay(play: true) } else { settleMode() }
        updateMenu()
        for request in pendingRequests { accept(request) }
        pendingRequests.removeAll()
        // Once reminders are on, the app starts quietly in the menu bar.
        if !CommandLine.arguments.contains("--background") && !calendarAlarms.settings.enabled { showPlayground() }
        // The update check is not urgent; keep it off the launch path.
        Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.updates.start() }
        }
        calendarAlarms.onPetAlert = { [weak self] in
            // Reminders stay visible when pets are paused or Reduce Motion is on.
            // Only a resting, unpaused pet starts a new lap.
            guard let self, self.mode == .resting else { return }
            self.startLap()
        }
        calendarAlarms.onUpcomingChanged = { [weak self] in self?.refreshCountdown() }
        calendarAlarms.start()
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } }
        calendarAlarms.enableDebugSources(feedFile: value("--feed-file"), feedURL: value("--feed-url"))
        refreshCountdown()

        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            for delay in [2.0, 20.0] {
                Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.writeDiagnostics(to: url) }
                }
            }
        }
    }

    /// Reflects the resting state without creating a window.
    private func settleMode() {
        if petsHidden { mode = .unloaded }
        else if activeCharacters.isEmpty { mode = .needsArtwork }
        else if reducedMotion { mode = .reducedMotion }
        else if mode != .pausedRest && mode != .pausedRun { mode = .resting }
    }

    /// Decodes only the active pets. Everything else is released.
    private func loadActiveArtworks() -> [SpriteArtwork] {
        var kept: [String: SpriteArtwork] = [:]
        var result: [SpriteArtwork] = []
        for character in activeCharacters {
            if let cached = artworkCache[character.id] { kept[character.id] = cached; result.append(cached); continue }
            do {
                let artwork = try SpriteArtwork(url: character.url, trusted: character.trusted)
                kept[character.id] = artwork; result.append(artwork)
            } catch {
                NSLog("LokiDot could not load %@: %@", character.name, error.localizedDescription)
            }
        }
        artworkCache = kept
        return result
    }

    private func teardownOverlay() {
        let hadOverlay = overlay != nil
        overlay?.settle(); overlay?.window.close(); overlay = nil
        artworkCache.removeAll()
        if hadOverlay { MemoryRelief.soon() }
    }

    /// Rebuilds the overlay for the current pets and display. With `play` the
    /// pet takes a lap now; otherwise an existing ambient pet is replaced.
    private func configureDisplay(play: Bool = false) {
        guard !petsHidden, !activeCharacters.isEmpty else {
            restTimer?.invalidate(); restTimer = nil; restDeadline = nil
            resumeAfterWake = false
            teardownOverlay()
            mode = petsHidden ? .unloaded : .needsArtwork
            updateMenu(); return
        }
        let wasPaused = mode == .pausedRun || mode == .pausedRest
        restTimer?.invalidate()
        restTimer = nil
        guard play || overlay != nil || repeatEnabled else { settleMode(); rebuildDisplayMenu(); updateMenu(); return }
        guard buildOverlay() else { updateMenu(); return }
        mode = .resting
        if reducedMotion { mode = .reducedMotion }
        else if wasPaused && !play { mode = .pausedRest }
        else { startLap() }
        updateMenu()
    }

    @discardableResult
    private func buildOverlay() -> Bool {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { displayID($0) == selectedDisplay })
            ?? screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? screens.first else { return false }
        teardownOverlay()
        let artworks = loadActiveArtworks()
        guard !artworks.isEmpty else { mode = .needsArtwork; return false }
        selectedDisplay = displayID(screen)
        overlay = Overlay(screen: screen, artworks: artworks)
        rebuildDisplayMenu()
        if screensAwake && userSessionActive { overlay?.window.orderFrontRegardless() }
        return true
    }

    private func startLap() {
        guard !petsHidden else { mode = .unloaded; updateMenu(); return }
        guard !activeCharacters.isEmpty else { mode = .needsArtwork; updateMenu(); return }
        guard !reducedMotion else { mode = .reducedMotion; updateMenu(); return }
        restTimer?.invalidate()
        restTimer = nil
        restDeadline = nil
        if overlay == nil { guard buildOverlay() else { updateMenu(); return } }
        if motionStyle == .prance && !canPrance { motionStyle = .zoomies }
        mode = .running
        overlay?.run(style: motionStyle, delegate: self)
        updateMenu()
    }

    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        Task { @MainActor [weak self] in self?.lapFinished() }
    }

    private func lapFinished() {
        guard mode == .running else { return }
        mode = .resting
        if repeatEnabled {
            overlay?.settle()
            scheduleRest(seconds: MotionRoute.restDuration)
        } else {
            // The whippet leaves the screen and its frames are freed until the
            // next reminder or a manual Zoomies!
            teardownOverlay()
        }
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
        case .unloaded: setPetsHidden(false); configureDisplay(play: true)
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
        case .reducedMotion, .needsArtwork, .unloaded: break
        }
        updateMenu()
    }

    @objc private func toggleRepeat() {
        repeatEnabled.toggle()
        UserDefaults.standard.set(repeatEnabled, forKey: "ambientRepeat")
        if mode == .resting {
            if repeatEnabled { startLap() }
            else { restTimer?.invalidate(); restTimer = nil; restDeadline = nil; teardownOverlay() }
        }
        updateMenu()
    }

    @objc private func selectDisplay(_ item: NSMenuItem) {
        selectedDisplay = item.representedObject as? CGDirectDisplayID
        configureDisplay()
    }

    @objc private func displaysChanged() {
        if overlay != nil { configureDisplay() } else { rebuildDisplayMenu() }
    }

    @objc private func accessibilityChanged() {
        guard !petsHidden, !activeCharacters.isEmpty else { return }
        if reducedMotion {
            restTimer?.invalidate()
            restTimer = nil
            mode = .reducedMotion
            overlay?.settle(keepPosition: true)
        } else if mode == .reducedMotion {
            overlay?.settle()
            mode = .resting
            if repeatEnabled { startLap() } else { teardownOverlay() }
        }
        updateMenu()
    }

    @objc private func sleeping(_ notification: Notification) {
        if notification.name == NSWorkspace.screensDidSleepNotification { screensAwake = false }
        else { userSessionActive = false }
        calendarAlarms.setSessionActive(false)
        if mode == .running || mode == .resting {
            resumeAfterWake = true
            togglePause()
        }
        overlay?.window.orderOut(nil)
    }

    @objc private func waking(_ notification: Notification) {
        if notification.name == NSWorkspace.screensDidWakeNotification { screensAwake = true }
        else { userSessionActive = true }
        guard screensAwake && userSessionActive else { return }
        calendarAlarms.setSessionActive(true)
        refreshCountdown()
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
        panel.message = "Choose a finished sprite-pack folder. LokiDot saves its own copy so you can move the original later."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let saved = try saveImportedPack(at: url)
            activateCharacter(id: saved.id)
        } catch {
            showArtworkError(error)
        }
    }

    /// Reads bundled manifests only. Bundled packs were validated at build time.
    private func loadCharacters() {
        var folders: [URL] = []
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true),
           let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            folders = children.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if !CommandLine.arguments.contains("--pack"), let custom = SpriteArtwork.initialURL() { folders.insert(custom, at: 0) }
        for url in folders {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                let manifest = try SpritePack.readManifest(directory: url)
                guard !characters.contains(where: { $0.id == manifest.id }) else { rejectedDefaults += 1; continue }
                characters.append(Character(id: manifest.id, name: manifest.name, url: url,
                                            canPrance: manifest.animations["jumping"] != nil, trusted: true))
            } catch { rejectedDefaults += 1 }
        }
    }

    private func loadInitialArtwork() {
        do {
            // Explicit input and saved choices never silently fall back to another dog.
            if CommandLine.arguments.contains("--pack"), let url = SpriteArtwork.initialURL() {
                let saved = try saveImportedPack(at: url)
                selectedID = saved.id
                rememberSelection(saved.id)
                setPetsHidden(false)
                showAllCharacters = false
                UserDefaults.standard.set(false, forKey: "showAllCharacters")
            } else if let saved = UserDefaults.standard.string(forKey: "selectedSpritePackPath") {
                // Migrate the previously remembered external folder once. The old
                // path is cleared only after a complete managed copy exists.
                let migrated = try saveImportedPack(at: URL(fileURLWithPath: saved, isDirectory: true))
                selectedID = migrated.id
                rememberSelection(migrated.id)
            } else if let id = UserDefaults.standard.string(forKey: "selectedCharacterID") {
                guard readyCharacters.contains(where: { $0.id == id }) else {
                    throw SpritePackError("The saved character is unavailable. Choose a ready character or import a complete pack.")
                }
                selectedID = id
            } else {
                selectedID = (characters.first(where: { $0.id == "whippet" }) ?? characters.first)?.id
            }
        } catch { showArtworkError(error) }
        if readyCharacters.isEmpty { showAllCharacters = false }
        rebuildCharacterMenu()
    }

    @objc private func selectCharacter(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              readyCharacters.contains(where: { $0.id == id }) else { return }
        activateCharacter(id: id)
    }

    private func activateCharacter(id: String) {
        selectedID = id
        showAllCharacters = false
        setPetsHidden(false)
        UserDefaults.standard.set(false, forKey: "showAllCharacters")
        rememberSelection(id)
        if motionStyle == .prance && !canPrance { motionStyle = .zoomies }
        rebuildCharacterMenu()
        configureDisplay(play: true)
    }

    @objc private func selectAllCharacters() {
        guard readyCharacters.count > 1 else { return }
        showAllCharacters = true
        setPetsHidden(false)
        UserDefaults.standard.set(true, forKey: "showAllCharacters")
        if motionStyle == .prance && !canPrance {
            motionStyle = .zoomies
            UserDefaults.standard.set(motionStyle.rawValue, forKey: "motionStyle")
        }
        rebuildCharacterMenu()
        configureDisplay(play: true)
    }

    private func showArtworkError(_ error: Error, title: String = "Sprite pack could not be loaded") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func rebuildCharacterMenu() {
        guard characterItem != nil else { return }
        let choices = NSMenu()
        choices.autoenablesItems = false
        let all = NSMenuItem(title: "Show All Ready Characters", action: #selector(selectAllCharacters), keyEquivalent: "")
        all.target = self
        all.isEnabled = readyCharacters.count > 1
        all.state = showAllCharacters ? .on : .off
        choices.addItem(all)
        choices.addItem(.separator())
        for candidate in readyCharacters {
            let title = candidate.name + (SavedPetLibrary.isSavedID(candidate.id) ? " · Saved" : "")
            let item = NSMenuItem(title: title, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.id
            item.state = !showAllCharacters && selectedID == candidate.id ? .on : .off
            choices.addItem(item)
        }
        if rejectedDefaults > 0 {
            let notice = NSMenuItem(title: "\(rejectedDefaults) incomplete pack(s) unavailable", action: nil, keyEquivalent: "")
            notice.isEnabled = false; choices.addItem(notice)
        }
        choices.addItem(.separator())
        let importer = NSMenuItem(title: "Import Sprite Pack…", action: #selector(chooseArtwork), keyEquivalent: "")
        importer.target = self
        choices.addItem(importer)
        let saved = NSMenuItem(title: "Saved pets…", action: #selector(showSavedPets), keyEquivalent: "")
        saved.target = self; choices.addItem(saved)
        characterItem.submenu = choices
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPlayground()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                let request = try LaunchRequest(url: url)
                if statusLabel == nil { pendingRequests.append(request) }
                else { accept(request) }
            } catch { showArtworkError(error) }
        }
    }

    private func accept(_ request: LaunchRequest) {
        switch request.action {
        case .quit: NSApp.terminate(nil); return
        case .calendars: showCalendarAlarms(); return
        case .alarmTest: calendarAlarms.testAlarm(); return
        case .pets: showSavedPets(); return
        case .unload: unloadPets(); return
        case .pause:
            if mode == .running || mode == .resting { togglePause() }; return
        case .resume:
            if petsHidden { setPetsHidden(false); configureDisplay(play: true); return }
            if mode == .pausedRun || mode == .pausedRest { togglePause() }; return
        case .show, .play: break
        }
        do {
            var candidate = selectedID
            var all = showAllCharacters
            if let path = request.packPath {
                candidate = try saveImportedPack(at: URL(fileURLWithPath: path, isDirectory: true)).id; all = false
            } else if let id = request.character {
                if id == "all" { all = true }
                else if readyCharacters.contains(where: { $0.id == id }) { candidate = id; all = false }
                else { throw SpritePackError("That dog is unavailable. Try whippet, beagle, robot-loki, loki-vampire, or all.") }
            }
            let selectedStyle = request.motion ?? motionStyle
            let selectedPacks = all ? readyCharacters : readyCharacters.filter { $0.id == candidate }
            guard !selectedPacks.isEmpty else { throw SpritePackError("Add a complete sprite pack first.") }
            guard selectedStyle != .prance || selectedPacks.allSatisfy(\.canPrance) else {
                throw SpritePackError("Prancing needs a pet-v2 pack with jumping poses. This dog can still do zoomies and little circles.")
            }
            selectedID = candidate; showAllCharacters = all; motionStyle = selectedStyle
            UserDefaults.standard.set(all, forKey: "showAllCharacters")
            UserDefaults.standard.set(selectedStyle.rawValue, forKey: "motionStyle")
            if !all, let candidate { rememberSelection(candidate) }
            rebuildCharacterMenu()
            if request.action == .play || request.character != nil || request.packPath != nil || request.motion != nil {
                setPetsHidden(false)
                mode = .resting
                configureDisplay(play: true)
            }
            if request.action == .show { showPlayground() }
            updateMenu()
        } catch { showArtworkError(error) }
    }

    @objc private func selectMotion(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let style = MotionStyle(rawValue: raw),
              let request = try? LaunchRequest(action: .play, motion: style) else { return }
        accept(request)
    }

    @objc private func showPlayground() {
        if playground == nil {
            let controller = PlaygroundWindow()
            controller.onPlay = { [weak self] id, style in
                if let request = try? LaunchRequest(action: .play, motion: style, character: id) { self?.accept(request) }
            }
            controller.onPause = { [weak self] in self?.togglePause() }
            controller.onImport = { [weak self] in self?.chooseArtwork() }
            controller.onCalendars = { [weak self] in self?.showCalendarAlarms() }
            controller.onSavedPets = { [weak self] in self?.showSavedPets() }
            controller.onUnload = { [weak self] in self?.unloadPets() }
            controller.onClose = { [weak self] in DispatchQueue.main.async { self?.playground = nil; MemoryRelief.soon() } }
            playground = controller
        }
        playground?.present()
        updateMenu()
    }

    private func buildApplicationMenu() {
        let main = NSMenu(), appMenu = NSMenu(), root = NSMenuItem()
        appMenu.autoenablesItems = false
        let show = NSMenuItem(title: "Show LokiDot Zoomies", action: #selector(showPlayground), keyEquivalent: "0")
        show.target = self; appMenu.addItem(show); appMenu.addItem(.separator())
        let calendars = NSMenuItem(title: "Meeting reminders…", action: #selector(showCalendarAlarms), keyEquivalent: ",")
        calendars.target = self; appMenu.addItem(calendars); appMenu.addItem(.separator())
        let saved = NSMenuItem(title: "Saved pets…", action: #selector(showSavedPets), keyEquivalent: "")
        saved.target = self; appMenu.addItem(saved)
        let unload = NSMenuItem(title: "Put pets away", action: #selector(unloadPets), keyEquivalent: "")
        unload.target = self; appMenu.addItem(unload); appMenu.addItem(.separator())
        updates.addMenuItems(to: appMenu)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LokiDot Zoomies", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit); root.submenu = appMenu; main.addItem(root)
        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        calendarAlarms.stop()
        countdownTimer?.invalidate()
        updates.stop()
        restTimer?.invalidate()
        overlay?.window.close()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMeetingItems(); updateMenu() }

    private var meetingItems: [NSMenuItem] = []

    /// The next few meetings, newest data first, with one-click Join.
    private func rebuildMeetingItems() {
        for item in meetingItems { menu.removeItem(item) }
        meetingItems.removeAll()
        let now = Date()
        let soon = calendarAlarms.upcoming.filter { $0.end > now && $0.start < now.addingTimeInterval(12 * 3600) }.prefix(4)
        guard calendarAlarms.settings.enabled else { return }
        var items: [NSMenuItem] = []
        if soon.isEmpty {
            let none = NSMenuItem(title: "No meetings in the next 12 hours", action: nil, keyEquivalent: "")
            none.isEnabled = false; items.append(none)
        }
        for meeting in soon {
            let time = meeting.start <= now ? "Now" : meeting.start.formatted(date: .omitted, time: .shortened)
            let join = meeting.joinURL.flatMap { MeetingLink.provider(for: $0) }.map { " — Join \($0)" } ?? ""
            let title = calendarAlarms.settings.showEventTitles ? String(meeting.title.prefix(48)) : "Meeting"
            let item = NSMenuItem(title: "\(time)  \(title)\(join)",
                                  action: meeting.joinURL == nil ? nil : #selector(joinMeeting(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = meeting.joinURL
            item.isEnabled = meeting.joinURL != nil
            items.append(item)
        }
        items.append(.separator())
        for (offset, item) in items.enumerated() { menu.insertItem(item, at: 1 + offset) }
        meetingItems = items
    }

    @objc private func joinMeeting(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        calendarAlarms.join(url)
    }

    /// Menu-bar countdown to the next meeting in the coming hour. The timer
    /// fires once per minute only while a meeting is that close.
    private func refreshCountdown() {
        countdownTimer?.invalidate(); countdownTimer = nil
        guard let button = statusItem?.button else { return }
        let now = Date()
        var title = "", wake: Date?
        if calendarAlarms.settings.enabled,
           let next = calendarAlarms.upcoming.first(where: { $0.end > now && $0.start > now.addingTimeInterval(-600) }) {
            let untilStart = next.start.timeIntervalSince(now)
            var label = ""
            if untilStart <= 0 {
                label = "now"; wake = min(next.end, next.start.addingTimeInterval(600))
            } else if untilStart <= 3600 {
                let minutes = Int(ceil(untilStart / 60))
                label = "\(minutes)m"
                wake = now.addingTimeInterval(untilStart - Double(minutes - 1) * 60)
            } else {
                wake = next.start.addingTimeInterval(-3600)
            }
            if !label.isEmpty {
                title = calendarAlarms.settings.showEventTitles ? " \(String(next.title.prefix(18))) · \(label)" : " \(label)"
            }
        }
        if button.title != title { button.title = title }
        if let wake {
            let timer = Timer(fire: max(wake, now.addingTimeInterval(1)), interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refreshCountdown() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        }
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        statusLabel = NSMenuItem(title: "LokiDot Zoomies", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        add("Show playground…", action: #selector(showPlayground), key: "")
        add("Meeting reminders…", action: #selector(showCalendarAlarms), key: ",")
        add("Saved pets…", action: #selector(showSavedPets), key: "")
        add("Put pets away", action: #selector(unloadPets), key: "")
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
        motionItem = NSMenuItem(title: "Moves", action: nil, keyEquivalent: "")
        let moves = NSMenu(); moves.autoenablesItems = false
        for style in MotionStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectMotion(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = style.rawValue; moves.addItem(item)
        }
        motionItem.submenu = moves; menu.addItem(motionItem)
        menu.addItem(.separator())
        updates.addMenuItems(to: menu)
        menu.addItem(.separator())
        // A background pet should not consume Command-Q intended for another app.
        add("Quit LokiDot Zoomies", action: #selector(quit), key: "")
        rebuildDisplayMenu()
    }

    private func updateMenu() {
        guard statusLabel != nil else { return }
        let status: String
        let petName = showAllCharacters ? "\(readyCharacters.count) pets" : selected?.name ?? "Your pet"
        let verb = showAllCharacters ? "are" : "is"
        switch mode {
        case .running: status = "\(petName) · \(motionStyle.title.lowercased())"
        case .resting: status = repeatEnabled ? "Catching a breath · repeats gently" : "\(petName) \(verb) waiting for your next reminder"
        case .pausedRun, .pausedRest: status = "\(petName) \(verb) paused"
        case .reducedMotion: status = "Resting · Reduce Motion is on"
        case .needsArtwork: status = "Import a complete sprite pack to begin"
        case .unloaded: status = "Pets are put away. Choose a pet and press Let’s go!"
        }
        // Keep menu item identities and positions stable while tracking a menu.
        statusLabel.title = status
        zoomiesItem.isEnabled = mode != .needsArtwork && mode != .reducedMotion && mode != .running
        let paused = mode == .pausedRun || mode == .pausedRest
        pauseItem.title = paused ? "Resume" : "Pause"
        pauseItem.isEnabled = mode != .needsArtwork && mode != .reducedMotion && !petsHidden && (overlay != nil || repeatEnabled)
        repeatItem.isEnabled = mode != .needsArtwork
        repeatItem.state = repeatEnabled ? .on : .off
        statusItem.button?.toolTip = "LokiDot Zoomies — \(status)"
        refreshCountdown()
        for item in motionItem?.submenu?.items ?? [] {
            let style = item.representedObject as? String
            item.state = style == motionStyle.rawValue ? .on : .off
            item.isEnabled = mode != .needsArtwork && (style != "prance" || canPrance)
        }
        guard let playground, playground.window?.isVisible == true else { return }
        var choices = readyCharacters.map { (id: $0.id, name: $0.name + (SavedPetLibrary.isSavedID($0.id) ? " · Saved" : ""), canPrance: $0.canPrance) }
        if readyCharacters.count > 1 { choices.insert((id: "all", name: "The whole pack", canPrance: readyCharacters.allSatisfy(\.canPrance)), at: 0) }
        let current = showAllCharacters ? "all" : selectedID ?? "whippet"
        playground.update(characters: choices, selected: current, motion: motionStyle, status: status,
                          paused: paused, canPlay: !choices.isEmpty, canPause: !activeCharacters.isEmpty && !reducedMotion && !petsHidden,
                          petsHidden: petsHidden)
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

    @objc private func showCalendarAlarms() { calendarAlarms.showSettings() }

    private func reloadSavedPets() throws {
        savedPets = try petLibrary.pets()
        var entries: [String: Character] = [:]
        for pet in savedPets where pet.problem == nil {
            guard let manifest = try? SpritePack.readManifest(directory: pet.directory) else { continue }
            entries[pet.id] = Character(id: pet.id, name: manifest.name, url: pet.directory,
                                        canPrance: manifest.animations["jumping"] != nil, trusted: false)
        }
        savedCharacters = entries
        updateSavedPetsWindow()
    }

    /// Imports validate every byte and pixel, then save a managed copy. The
    /// display copy is decoded later, only when the pet runs.
    private func saveImportedPack(at url: URL) throws -> SavedPet {
        let pet = try petLibrary.save(SpritePack.load(directory: url))
        unloadedSavedPetIDs.remove(pet.id)
        UserDefaults.standard.set(unloadedSavedPetIDs.sorted(), forKey: "unloadedSavedPetIDs")
        try reloadSavedPets()
        return pet
    }

    private func rememberSelection(_ id: String) {
        UserDefaults.standard.set(id, forKey: "selectedCharacterID")
        UserDefaults.standard.removeObject(forKey: "selectedSpritePackPath")
    }

    private func setPetsHidden(_ value: Bool) {
        petsHidden = value
        UserDefaults.standard.set(value, forKey: "petsHidden")
    }

    @objc private func unloadPets() {
        setPetsHidden(true)
        configureDisplay()
    }

    @objc private func showSavedPets() {
        if savedPetsWindow == nil {
            let window = SavedPetsWindow()
            window.onImport = { [weak self] in self?.chooseArtwork() }
            window.onLoad = { [weak self] id in self?.loadSavedPet(id) }
            window.onUnload = { [weak self] id in self?.unloadSavedPet(id) }
            window.onRemove = { [weak self] id in self?.removeSavedPet(id) }
            window.onClose = { [weak self] in DispatchQueue.main.async { self?.savedPetsWindow = nil; MemoryRelief.soon() } }
            savedPetsWindow = window
        }
        do { try reloadSavedPets() } catch { showArtworkError(error, title: "Saved pets could not be opened") }
        rebuildCharacterMenu(); updateMenu()
        savedPetsWindow?.present()
    }

    private func updateSavedPetsWindow() {
        savedPetsWindow?.update(savedPets.map { .init(pet: $0, loaded: savedCharacters[$0.id] != nil && !unloadedSavedPetIDs.contains($0.id)) })
    }

    private func loadSavedPet(_ id: String) {
        do {
            let directory = try petLibrary.directory(for: id)
            _ = try SpriteArtwork(url: directory) // Check the artwork before it joins the pack.
            unloadedSavedPetIDs.remove(id)
            UserDefaults.standard.set(unloadedSavedPetIDs.sorted(), forKey: "unloadedSavedPetIDs")
            try reloadSavedPets()
            activateCharacter(id: id)
            updateSavedPetsWindow()
        } catch { showArtworkError(error) }
    }

    private func unloadSavedPet(_ id: String) {
        guard savedPets.contains(where: { $0.id == id }) else { return }
        let wasSelected = selectedID == id
        unloadedSavedPetIDs.insert(id)
        UserDefaults.standard.set(unloadedSavedPetIDs.sorted(), forKey: "unloadedSavedPetIDs")
        if wasSelected {
            selectedID = nil
            UserDefaults.standard.removeObject(forKey: "selectedCharacterID")
            UserDefaults.standard.removeObject(forKey: "selectedSpritePackPath")
            if !showAllCharacters { setPetsHidden(true) }
        }
        rebuildCharacterMenu(); configureDisplay(); updateSavedPetsWindow()
    }

    private func removeSavedPet(_ id: String) {
        guard let pet = savedPets.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(pet.name) from Saved pets?"
        alert.informativeText = "LokiDot’s saved copy will move to Trash. Your original sprite-pack folder stays untouched. You can import it again later."
        alert.addButton(withTitle: "Move saved copy to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try petLibrary.remove(id) { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
            unloadSavedPet(id)
            unloadedSavedPetIDs.remove(id)
            UserDefaults.standard.set(unloadedSavedPetIDs.sorted(), forKey: "unloadedSavedPetIDs")
            try reloadSavedPets()
            rebuildCharacterMenu(); configureDisplay()
        } catch { showArtworkError(error, title: "Saved copy could not be removed") }
    }

    private func writeDiagnostics(to url: URL) {
        let position = overlay?.pet.presentation()?.position ?? overlay?.pet.position ?? .zero
        let report: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "characterCount": overlay?.petCount ?? 0,
            "decodedArtworkCount": artworkCache.count,
            "overlayExists": overlay != nil,
            "savedPetCount": savedPets.count,
            "loadedSavedPetCount": savedCharacters.keys.filter { !unloadedSavedPetIDs.contains($0) }.count,
            "petsHidden": petsHidden,
            "showAllCharacters": showAllCharacters,
            "mode": mode.rawValue,
            "motion": motionStyle.rawValue,
            "bundlePath": Bundle.main.bundlePath,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
            "characters": activeCharacters.map(\.id),
            "playgroundVisible": playground?.window?.isVisible ?? false,
            "reduceMotion": reducedMotion,
            "repeatEnabled": repeatEnabled,
            "windowNumber": overlay?.window.windowNumber ?? 0,
            "windowVisible": overlay?.window.isVisible ?? false,
            "clickThrough": overlay?.window.ignoresMouseEvents ?? true,
            "canBecomeKey": overlay?.window.canBecomeKey ?? false,
            "windowLevel": overlay?.window.level.rawValue ?? 0,
            "displayCount": NSScreen.screens.count,
            "visibleFrame": NSStringFromRect(overlay?.window.frame ?? .zero),
            "petPosition": NSStringFromPoint(position),
            "hasLapAnimation": overlay?.pet.animation(forKey: "zoomies") != nil,
            "activeRestTimer": restTimer?.isValid ?? false,
            "menuBarTitle": statusItem.button?.title ?? "",
            "calendar": calendarAlarms.diagnostics
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { NSLog("Could not write requested diagnostics: %@", error.localizedDescription) }
    }
}
