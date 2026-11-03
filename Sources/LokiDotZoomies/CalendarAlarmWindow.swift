import AppKit
import ZoomiesCore

@MainActor
final class CalendarAlarmWindow: NSWindowController {
    var onConnect: (() -> Void)?
    var onChange: ((CalendarAlarmSettings) -> Void)?
    var onRefresh: (() -> Void)?
    var onTest: (() -> Void)?
    var onAddFeed: ((String) -> String)?
    var onRemoveFeed: ((String) -> Void)?
    var onLoginItem: ((Bool) -> Void)?
    private var settings = CalendarAlarmSettings()
    private var displayedCalendars: [CalendarAlarmController.CalendarChoice] = []
    private var displayedFeeds: [CalendarAlarmController.FeedRow] = []
    private let enabled = NSButton(checkboxWithTitle: "Remind me about meetings", target: nil, action: nil)
    private let atStart = NSButton(checkboxWithTitle: "Remind me again when it starts", target: nil, action: nil)
    private let sound = NSButton(checkboxWithTitle: "Play a sound", target: nil, action: nil)
    private let titles = NSButton(checkboxWithTitle: "Show meeting titles (turn off before screen sharing)", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Open LokiDot at login, so reminders survive restarts", target: nil, action: nil)
    private let lead = NSPopUpButton(frame: .zero, pullsDown: false)
    private let connect = NSButton(title: "Connect Apple Calendar…", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let calendarList = NSStackView()
    private let feedList = NSStackView()
    private let feedField = NSTextField()
    private let feedMessage = NSTextField(wrappingLabelWithString: "")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Meeting reminders"; window.isReleasedWhenClosed = false
        super.init(window: window)
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "Your whippet watches the clock.")
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        root.addArrangedSubview(heading)
        status.font = .systemFont(ofSize: 12, weight: .medium)
        root.addArrangedSubview(status)
        for button in [enabled, atStart, sound, titles] { button.target = self; button.action = #selector(changed) }
        login.target = self; login.action = #selector(loginChanged)
        root.addArrangedSubview(enabled)

        root.addArrangedSubview(sectionTitle("Apple Calendar"))
        root.addArrangedSubview(label("Includes iCloud and any Google or Exchange accounts added to this Mac. Zoomies reads events only; it never edits them."))
        connect.target = self; connect.action = #selector(connectCalendars); connect.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshCalendars)); refresh.bezelStyle = .rounded
        root.addArrangedSubview(NSStackView(views: [connect, refresh]))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        calendarList.orientation = .vertical; calendarList.alignment = .leading; calendarList.spacing = 6
        calendarList.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        calendarList.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = calendarList
        root.addArrangedSubview(scroll)

        root.addArrangedSubview(sectionTitle("Google or Outlook calendar link"))
        root.addArrangedSubview(label("Google: Calendar settings → your calendar → “Secret address in iCal format”. Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS link. Use this for work Outlook calendars that no longer sync to Apple Calendar. Links are private; Zoomies keeps them only on this Mac."))
        feedField.placeholderString = "https://… or webcal://… .ics"
        feedField.lineBreakMode = .byTruncatingMiddle
        let add = NSButton(title: "Add link", target: self, action: #selector(addFeed)); add.bezelStyle = .rounded
        let feedRow = NSStackView(views: [feedField, add]); feedRow.spacing = 8
        root.addArrangedSubview(feedRow)
        feedMessage.font = .systemFont(ofSize: 11); feedMessage.textColor = .secondaryLabelColor
        root.addArrangedSubview(feedMessage)
        feedList.orientation = .vertical; feedList.alignment = .leading; feedList.spacing = 6
        root.addArrangedSubview(feedList)

        root.addArrangedSubview(sectionTitle("How to remind me"))
        for minutes in CalendarAlarmSettings.allowedLeadMinutes {
            lead.addItem(withTitle: minutes == 0 ? "At the start" : "\(minutes) minute\(minutes == 1 ? "" : "s") before")
            lead.lastItem?.representedObject = minutes
        }
        lead.setAccessibilityLabel("First reminder"); lead.target = self; lead.action = #selector(changed)
        root.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "First reminder"), lead]))
        root.addArrangedSubview(atStart); root.addArrangedSubview(sound); root.addArrangedSubview(titles); root.addArrangedSubview(login)
        let test = NSButton(title: "Try a reminder", target: self, action: #selector(testAlarm)); test.bezelStyle = .rounded
        root.addArrangedSubview(test)
        root.addArrangedSubview(label("The whippet runs across your screen and a card shows the meeting with Join, Remind me at start, and Dismiss. All-day, cancelled and declined events are skipped. Keep Zoomies open; it uses no CPU between reminders."))
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(equalToConstant: 110),
            calendarList.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            status.widthAnchor.constraint(equalTo: root.widthAnchor),
            feedRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            feedList.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func label(_ value: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 512
        return field
    }
    private func sectionTitle(_ value: String) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        return field
    }

    func update(settings: CalendarAlarmSettings, calendars: [CalendarAlarmController.CalendarChoice],
                feeds: [CalendarAlarmController.FeedRow], hasAccess: Bool, canEnable: Bool, requesting: Bool,
                opensAtLogin: Bool, status: String) {
        self.settings = settings
        enabled.state = settings.enabled ? .on : .off; enabled.isEnabled = canEnable
        atStart.state = settings.alsoAtStart ? .on : .off
        atStart.isEnabled = settings.leadMinutes != 0
        sound.state = settings.sound ? .on : .off; titles.state = settings.showEventTitles ? .on : .off
        login.state = opensAtLogin ? .on : .off
        if let item = lead.itemArray.first(where: { $0.representedObject as? Int == Int(settings.leadInterval / 60) }) { lead.select(item) }
        connect.isEnabled = !hasAccess && !requesting; connect.title = hasAccess ? "Apple Calendar connected" : "Connect Apple Calendar…"
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
        if displayedFeeds != feeds {
            displayedFeeds = feeds
            for view in feedList.arrangedSubviews { feedList.removeArrangedSubview(view); view.removeFromSuperview() }
            for feed in feeds {
                let name = NSTextField(labelWithString: feed.name); name.font = .systemFont(ofSize: 12, weight: .medium)
                name.lineBreakMode = .byTruncatingTail
                let detail = NSTextField(labelWithString: feed.status); detail.font = .systemFont(ofSize: 11)
                detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
                let text = NSStackView(views: [name, detail]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
                let remove = NSButton(title: "Remove", target: self, action: #selector(removeFeed(_:)))
                remove.bezelStyle = .rounded; remove.controlSize = .small
                remove.identifier = NSUserInterfaceItemIdentifier(feed.id)
                let row = NSStackView(views: [text, remove]); row.spacing = 10
                text.setContentHuggingPriority(.defaultLow, for: .horizontal)
                feedList.addArrangedSubview(row)
            }
        }
    }

    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func connectCalendars() { onConnect?() }
    @objc private func refreshCalendars() { onRefresh?() }
    @objc private func testAlarm() { onTest?() }
    @objc private func loginChanged() { onLoginItem?(login.state == .on) }
    @objc private func addFeed() {
        feedMessage.stringValue = onAddFeed?(feedField.stringValue) ?? ""
        if feedMessage.stringValue.hasPrefix("Added") { feedField.stringValue = "" }
    }
    @objc private func removeFeed(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue { onRemoveFeed?(id) }
    }
    @objc private func changed() {
        settings.enabled = enabled.state == .on; settings.sound = sound.state == .on
        settings.alsoAtStart = atStart.state == .on
        settings.showEventTitles = titles.state == .on; settings.leadMinutes = lead.selectedItem?.representedObject as? Int ?? 5
        onChange?(settings)
    }
    @objc private func calendarChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if sender.state == .on { settings.calendarIDs.insert(id) } else { settings.calendarIDs.remove(id) }
        onChange?(settings)
    }
}

/// The reminder card: top-right, above full-screen apps, never steals focus,
/// so a keystroke meant for another app can't join or dismiss a meeting.
@MainActor
final class PetAlarmWindow: NSWindowController, NSWindowDelegate {
    var onDismiss: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onJoin: (() -> Void)?
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let join = NSButton(title: "Join", target: nil, action: nil)
    private let snooze = NSButton(title: "Remind me at start", target: nil, action: nil)
    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Meeting"; panel.isReleasedWhenClosed = false
        panel.level = .statusBar; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        heading.font = .systemFont(ofSize: 18, weight: .semibold); heading.maximumNumberOfLines = 2
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        join.target = self; join.action = #selector(joinMeeting); join.bezelStyle = .rounded
        join.bezelColor = .controlAccentColor
        snooze.target = self; snooze.action = #selector(snoozeAlarm); snooze.bezelStyle = .rounded
        let dismiss = NSButton(title: "Dismiss", target: self, action: #selector(dismissAlarm)); dismiss.bezelStyle = .rounded
        let root = NSStackView(views: [heading, detail, NSStackView(views: [join, snooze, dismiss])])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false; panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 14),
            root.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor, constant: -14),
            heading.widthAnchor.constraint(equalTo: root.widthAnchor), detail.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present(title: String, detail: String, joinTitle: String?, snoozeTitle: String) {
        heading.stringValue = title; self.detail.stringValue = detail
        join.title = joinTitle ?? "Join"; join.isHidden = joinTitle == nil || onJoin == nil
        snooze.title = snoozeTitle; snooze.isHidden = onSnooze == nil
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen, let window {
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 18,
                                                y: screen.visibleFrame.maxY - 12))
        }
        window?.orderFrontRegardless()
    }
    func hide() { window?.orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onDismiss?(); return false }
    @objc private func dismissAlarm() { onDismiss?() }
    @objc private func snoozeAlarm() { onSnooze?() }
    @objc private func joinMeeting() { onJoin?() }
}
