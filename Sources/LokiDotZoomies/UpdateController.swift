import AppKit
import ZoomiesCore

@MainActor
final class UpdateController: NSObject {
    private let defaults = UserDefaults.standard
    private let automaticKey = "automaticallyCheckForUpdates"
    private let lastCheckKey = "lastUpdateCheckDate"
    private let lastOfferedKey = "lastOfferedUpdateVersion"
    private var timer: Timer?
    private var transport: UpdateTransport?
    private var busy = false
    private var checkItems: [NSMenuItem] = []
    private var automaticItems: [NSMenuItem] = []
    private var progressPanel: NSPanel?
    private var downloadCancelled = false
    private let supported = Bundle.main.bundleIdentifier == "com.ashrocket.LokiDotZoomies"
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unsupported"
        #endif
    }

    func addMenuItems(to menu: NSMenu) {
        guard supported else { return }
        defaults.register(defaults: [automaticKey: true])
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkManually), keyEquivalent: "")
        check.target = self; menu.addItem(check); checkItems.append(check)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomatic), keyEquivalent: "")
        automatic.target = self; menu.addItem(automatic); automaticItems.append(automatic)
        refreshMenu()
    }

    func start() {
        guard supported else { return }
        defaults.register(defaults: [automaticKey: true])
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; transport?.cancel() }

    @objc private func toggleAutomatic() {
        defaults.set(!defaults.bool(forKey: automaticKey), forKey: automaticKey)
        refreshMenu()
        checkIfDue()
    }

    private func checkIfDue() {
        guard defaults.bool(forKey: automaticKey) else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86400 { return }
        check(manual: false)
    }

    @objc private func checkManually() { check(manual: true) }

    private func check(manual: Bool) {
        guard supported, !busy else { return }
        busy = true; refreshMenu()
        defaults.set(Date(), forKey: lastCheckKey)
        do {
            let task = try UpdateTransport { [weak self] result in
                DispatchQueue.main.async { self?.didCheck(result, manual: manual) }
            }
            transport = task; task.start()
        } catch { didCheck(.failure(error), manual: manual) }
    }

    private func didCheck(_ result: Result<UpdateTransport.Output, Error>, manual: Bool) {
        busy = false; transport = nil; refreshMenu(); MemoryRelief.soon()
        guard manual || defaults.bool(forKey: automaticKey) else { return }
        do {
            guard case .metadata(let data) = try result.get() else { throw UpdateError("The release response is invalid.") }
            guard let release = try UpdateRelease.parse(data, currentVersion: currentVersion, architecture: architecture) else {
                if manual { showMessage("You’re up to date", "LokiDot Zoomies \(currentVersion) is the latest supported stable version.") }
                return
            }
            guard manual || defaults.string(forKey: lastOfferedKey) != release.version.description else { return }
            offer(release)
        } catch {
            // Offline/rate-limit/invalid-feed errors never interrupt background use.
            if manual { showMessage("Couldn’t check for updates", error.localizedDescription) }
        }
    }

    private func offer(_ release: UpdateRelease) {
        busy = true; refreshMenu()
        defaults.set(release.version.description, forKey: lastOfferedKey)
        let alert = NSAlert()
        alert.messageText = "LokiDot Zoomies \(release.version) is available"
        var message = "You’re using \(currentVersion). Download the update (\(ByteCountFormatter.string(fromByteCount: Int64(release.size), countStyle: .file))) and open macOS Installer?\n\nInstaller will ask you to confirm and finish installation in ~/Applications. Zoomies will quit when Installer opens; reopen it after installation. Your dog packs and preferences are preserved."
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/LokiDot Zoomies.app").standardizedFileURL
        if Bundle.main.bundleURL.standardizedFileURL != expected {
            message += "\n\nThis copy is running elsewhere. Installer updates ~/Applications/LokiDot Zoomies.app; it does not replace this other copy. Open the copy in ~/Applications afterward."
        }
        alert.informativeText = message
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { download(release) }
        else { busy = false; refreshMenu() }
    }

    private func download(_ release: UpdateRelease) {
        downloadCancelled = false
        showProgress(version: release.version.description)
        do {
            let task = try UpdateTransport(release: release) { [weak self] result in
                DispatchQueue.main.async { self?.didDownload(result) }
            }
            transport = task; task.start()
        } catch { didDownload(.failure(error)) }
    }

    @objc private func cancelDownload() { downloadCancelled = true; transport?.cancel() }

    private func didDownload(_ result: Result<UpdateTransport.Output, Error>) {
        transport = nil
        progressPanel?.close(); progressPanel = nil
        guard !downloadCancelled else { busy = false; refreshMenu(); return }
        do {
            guard case .package(let url, let release) = try result.get() else { throw UpdateError("The installer download is invalid.") }
            try UpdateTransport.verifyStagedPackage(at: url, release: release)
            let installer = URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app", isDirectory: true)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: installer, configuration: configuration) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.busy = false; self.refreshMenu()
                        self.showMessage("Couldn’t open Installer", error.localizedDescription)
                    } else { NSApp.terminate(nil) }
                }
            }
        } catch {
            busy = false; refreshMenu()
            if (error as NSError).code != NSURLErrorCancelled {
                showMessage("Update wasn’t installed", error.localizedDescription)
            }
        }
    }

    private func refreshMenu() {
        for item in checkItems { item.isEnabled = !busy }
        for item in automaticItems { item.state = defaults.bool(forKey: automaticKey) ? .on : .off }
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }

    private func showProgress(version: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Updating LokiDot Zoomies"
        let label = NSTextField(wrappingLabelWithString: "Downloading and verifying version \(version)…\nInstaller opens after verification.")
        label.frame = NSRect(x: 24, y: 65, width: 382, height: 52)
        let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 26, width: 24, height: 24))
        spinner.style = .spinning; spinner.startAnimation(nil)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelDownload))
        cancel.frame = NSRect(x: 320, y: 20, width: 90, height: 32)
        panel.contentView?.addSubview(label); panel.contentView?.addSubview(spinner); panel.contentView?.addSubview(cancel)
        panel.center(); panel.makeKeyAndOrderFront(nil); progressPanel = panel
    }
}
