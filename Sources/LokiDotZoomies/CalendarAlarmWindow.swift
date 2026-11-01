import AppKit
import ZoomiesCore

@MainActor
final class CalendarAlarmWindow: NSWindowController {
    var onConnect: (() -> Void)?
    var onChange: ((CalendarAlarmSettings) -> Void)?
    var onRefresh: (() -> Void)?
    var onTest: (() -> Void)?
    private var settings = CalendarAlarmSettings()
    private var displayedCalendars: [CalendarAlarmController.CalendarChoice] = []
    private let enabled = NSButton(checkboxWithTitle: "Let my pets remind me", target: nil, action: nil)
    private let sound = NSButton(checkboxWithTitle: "Play a gentle sound", target: nil, action: nil)
    private let titles = NSButton(checkboxWithTitle: "Show event titles in alerts", target: nil, action: nil)
    private let lead = NSPopUpButton(frame: .zero, pullsDown: false)
    private let connect = NSButton(title: "Connect calendars…", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let calendarList = NSStackView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Calendar alarms"; window.isReleasedWhenClosed = false
        super.init(window: window)
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "A little nudge from your pet.")
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        root.addArrangedSubview(heading)
        root.addArrangedSubview(label("Apple Calendar and Google calendars synced to this Mac. Your events stay on your Mac; Zoomies never edits them."))
        connect.target = self; connect.action = #selector(connectCalendars); connect.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshCalendars)); refresh.bezelStyle = .rounded
        root.addArrangedSubview(NSStackView(views: [connect, refresh]))
        status.font = .systemFont(ofSize: 12, weight: .medium)
        root.addArrangedSubview(status)
        for button in [enabled, sound, titles] { button.target = self; button.action = #selector(changed) }
        root.addArrangedSubview(enabled)
        let calendarsHeading = NSTextField(labelWithString: "Remind me about these calendars")
        calendarsHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        root.addArrangedSubview(calendarsHeading)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        calendarList.orientation = .vertical; calendarList.alignment = .leading; calendarList.spacing = 8
        calendarList.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        calendarList.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = calendarList
        root.addArrangedSubview(scroll)
        for minutes in CalendarAlarmSettings.allowedLeadMinutes {
            lead.addItem(withTitle: minutes == 0 ? "At the start" : "\(minutes) minute\(minutes == 1 ? "" : "s") before")
            lead.lastItem?.representedObject = minutes
        }
        lead.setAccessibilityLabel("Remind me"); lead.target = self; lead.action = #selector(changed)
        root.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "Remind me"), lead]))
        root.addArrangedSubview(sound); root.addArrangedSubview(titles)
        let test = NSButton(title: "Try a pet alarm", target: self, action: #selector(testAlarm)); test.bezelStyle = .rounded
        let google = NSButton(title: "Set up Google Calendar…", target: self, action: #selector(googleHelp)); google.bezelStyle = .rounded
        root.addArrangedSubview(NSStackView(views: [test, google]))
        root.addArrangedSubview(label("Keep Zoomies open and your Mac awake. Closing the playground is fine. All-day, cancelled and declined events are skipped. Alarms have Snooze 5 min and Dismiss; paused pets stay still."))
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -22),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(equalToConstant: 142),
            calendarList.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            status.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func label(_ value: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 492
        return field
    }

    func update(settings: CalendarAlarmSettings, calendars: [CalendarAlarmController.CalendarChoice],
                hasAccess: Bool, requesting: Bool, status: String) {
        self.settings = settings
        enabled.state = settings.enabled ? .on : .off; enabled.isEnabled = hasAccess
        sound.state = settings.sound ? .on : .off; titles.state = settings.showEventTitles ? .on : .off
        if let item = lead.itemArray.first(where: { $0.representedObject as? Int == Int(settings.leadInterval / 60) }) { lead.select(item) }
        connect.isEnabled = !hasAccess && !requesting; connect.title = hasAccess ? "Calendars connected" : "Connect calendars…"
        self.status.stringValue = status
        if displayedCalendars != calendars || calendarList.arrangedSubviews.isEmpty {
            displayedCalendars = calendars
            for view in calendarList.arrangedSubviews { calendarList.removeArrangedSubview(view); view.removeFromSuperview() }
            if calendars.isEmpty { calendarList.addArrangedSubview(label(hasAccess ? "No calendars found. Add an account in Apple Calendar, then refresh." : "Your calendars appear here after you connect.")) }
            for calendar in calendars {
                let button = NSButton(checkboxWithTitle: calendar.title, target: self, action: #selector(calendarChanged(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(calendar.id)
                button.lineBreakMode = .byTruncatingTail
                calendarList.addArrangedSubview(button)
                button.widthAnchor.constraint(lessThanOrEqualTo: calendarList.widthAnchor, constant: -20).isActive = true
            }
        }
        for case let button as NSButton in calendarList.arrangedSubviews {
            button.state = settings.calendarIDs.contains(button.identifier?.rawValue ?? "") ? .on : .off
        }
    }

    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func connectCalendars() { onConnect?() }
    @objc private func refreshCalendars() { onRefresh?() }
    @objc private func testAlarm() { onTest?() }
    @objc private func changed() {
        settings.enabled = enabled.state == .on; settings.sound = sound.state == .on
        settings.showEventTitles = titles.state == .on; settings.leadMinutes = lead.selectedItem?.representedObject as? Int ?? 5
        onChange?(settings)
    }
    @objc private func calendarChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if sender.state == .on { settings.calendarIDs.insert(id) } else { settings.calendarIDs.remove(id) }
        onChange?(settings)
    }
    @objc private func googleHelp() {
        NSWorkspace.shared.open(URL(string: "https://support.google.com/calendar/answer/99358?hl=en")!)
    }
}

@MainActor
final class PetAlarmWindow: NSWindowController, NSWindowDelegate {
    var onDismiss: (() -> Void)?
    var onSnooze: (() -> Void)?
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let snooze = NSButton(title: "Snooze 5 min", target: nil, action: nil)
    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "LokiDot pet alarm"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        heading.font = .systemFont(ofSize: 19, weight: .semibold); heading.maximumNumberOfLines = 2
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        snooze.target = self; snooze.action = #selector(snoozeAlarm); snooze.bezelStyle = .rounded
        let dismiss = NSButton(title: "Dismiss", target: self, action: #selector(dismissAlarm)); dismiss.bezelStyle = .rounded
        let root = NSStackView(views: [heading, detail, NSStackView(views: [snooze, dismiss])])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false; panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor, constant: -18),
            heading.widthAnchor.constraint(equalTo: root.widthAnchor), detail.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present(title: String, detail: String) {
        heading.stringValue = title; self.detail.stringValue = detail; snooze.isHidden = onSnooze == nil
        if let screen = NSScreen.main ?? NSScreen.screens.first, let window {
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 22,
                                                y: screen.visibleFrame.maxY - 22))
        }
        window?.orderFrontRegardless()
    }
    func hide() { window?.orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onDismiss?(); return false }
    @objc private func dismissAlarm() { onDismiss?() }
    @objc private func snoozeAlarm() { onSnooze?() }
}
