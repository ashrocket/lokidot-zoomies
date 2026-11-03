import AppKit
import EventKit
import ServiceManagement
import ZoomiesCore

/// Meeting reminders from Apple Calendar (including Google and Exchange
/// accounts synced to this Mac) and from Google/Outlook ICS links.
///
/// Efficiency: one timer sleeps until the next owed reminder; there is no
/// per-second polling. EventKit is opened only after the owner connects it.
/// Links are fetched every 10 minutes, on wake, and on Refresh.
private struct FeedFetchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class CalendarAlarmController: NSObject {
    struct CalendarChoice: Equatable {
        let id: String
        let title: String
    }
    struct FeedRow: Equatable {
        let id: String
        let name: String
        let status: String
    }
    struct Upcoming {
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL?
    }

    static let feedRefreshInterval: TimeInterval = 600
    static let lookAhead: TimeInterval = 36 * 3600
    static let maxFeedBytes = 12 * 1024 * 1024

    private var store: EKEventStore?
    private let defaults: UserDefaults
    private(set) var settings: CalendarAlarmSettings
    private var scheduler: CalendarAlarmScheduler
    private var calendars: [CalendarChoice] = []
    private var systemEvents: [CalendarAlarmEvent] = []
    private var feedEvents: [String: [CalendarAlarmEvent]] = [:]
    private var feedStatus: [String: String] = [:]
    private var feedTasks: [String: URLSessionDataTask] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "LokiDotZoomies (calendar reminders)"]
        return URLSession(configuration: configuration)
    }()
    private var events: [CalendarAlarmEvent] = []
    private(set) var upcoming: [Upcoming] = []
    private var queue: [CalendarAlarmEvent] = []
    private var active: CalendarAlarmEvent?
    private var fireTimer: Timer?
    private var feedTimer: Timer?
    private var sessionActive = true
    private var requestingAccess = false
    private var permissionError: String?
    private var settingsWindow: CalendarAlarmWindow?
    private var alertWindow: PetAlarmWindow?
    var onPetAlert: (() -> Void)?
    var onUpcomingChanged: (() -> Void)?
    /// Verification only: sources from launch flags are never saved.
    private var debugMode = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: "calendarAlarms.settings")
            .flatMap { try? JSONDecoder().decode(CalendarAlarmSettings.self, from: $0) } ?? .init()
        let receipts = defaults.data(forKey: "calendarAlarms.receipts")
            .flatMap { try? JSONDecoder().decode([CalendarAlarmReceipt].self, from: $0) } ?? []
        scheduler = CalendarAlarmScheduler(receipts: receipts)
        super.init()
    }

    private var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    private var canEnable: Bool { hasAccess || !settings.feeds.isEmpty }

    func start() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        center.addObserver(self, selector: #selector(clockChanged), name: .NSCalendarDayChanged, object: nil)
        refreshSystem()
        refreshFeeds()
        scheduleFeedTimer()
    }

    func stop() {
        fireTimer?.invalidate(); fireTimer = nil
        feedTimer?.invalidate(); feedTimer = nil
        for task in feedTasks.values { task.cancel() }
        NotificationCenter.default.removeObserver(self)
        alertWindow?.hide()
    }

    func setSessionActive(_ value: Bool) {
        sessionActive = value
        if value { refreshSystem(); refreshFeeds(); tick() }
        else { fireTimer?.invalidate(); fireTimer = nil; alertWindow?.hide() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = CalendarAlarmWindow()
            window.onConnect = { [weak self] in self?.requestAccess() }
            window.onChange = { [weak self] value in self?.changeSettings(value) }
            window.onRefresh = { [weak self] in self?.refreshSystem(); self?.refreshFeeds() }
            window.onTest = { [weak self] in self?.testAlarm() }
            window.onAddFeed = { [weak self] text in self?.addFeed(text) ?? "" }
            window.onRemoveFeed = { [weak self] id in self?.removeFeed(id) }
            window.onLoginItem = { [weak self] on in self?.setOpenAtLogin(on) }
            settingsWindow = window
        }
        settingsWindow?.present()
        refreshSystem()
    }

    func join(_ url: URL) {
        NSWorkspace.shared.open(url)
        if let current = active, current.joinURL == url { dismiss() }
    }

    // MARK: Apple Calendar

    private func requestAccess() {
        guard !requestingAccess else { return }
        guard !hasAccess else { refreshSystem(); return }
        requestingAccess = true; permissionError = nil; updateWindow()
        // Reached only from the explicit Connect button. EventKit has no
        // read-only permission; the app never writes events.
        let store = self.store ?? EKEventStore()
        self.store = store
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if #available(macOS 14.0, *) { _ = try await store.requestFullAccessToEvents() }
                else { _ = try await store.requestAccess(to: .event) }
            } catch {
                self.permissionError = "Calendar access could not be requested. Check System Settings → Privacy & Security → Calendars."
            }
            self.requestingAccess = false
            store.reset()
            self.observeStore()
            self.refreshSystem()
        }
    }

    private var observingStore = false
    private func observeStore() {
        guard let store, !observingStore else { return }
        observingStore = true
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: store)
    }

    @objc private func storeChanged() { refreshSystem() }
    @objc private func clockChanged() { refreshSystem() }

    private func refreshSystem() {
        let windowOpen = settingsWindow?.window?.isVisible == true
        guard hasAccess, settings.enabled || windowOpen else {
            calendars = []; systemEvents = []
            recompute(); return
        }
        if store == nil { store = EKEventStore() }
        observeStore()
        guard let store else { return }
        let available = store.calendars(for: .event)
        if windowOpen {
            calendars = available.map {
                CalendarChoice(id: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)")
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } else { calendars = [] }
        let selected = available.filter { settings.calendarIDs.contains($0.calendarIdentifier) }
        guard settings.enabled && !selected.isEmpty else { systemEvents = []; recompute(); return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-CalendarAlarmScheduler.lateStartInterval),
                                                 end: now.addingTimeInterval(Self.lookAhead), calendars: selected)
        systemEvents = store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate, let calendar = event.calendar else { return nil }
            return CalendarAlarmEvent(id: event.eventIdentifier ?? event.calendarItemIdentifier,
                                      calendarID: calendar.calendarIdentifier,
                                      title: event.title?.isEmpty == false ? event.title! : "Calendar event",
                                      start: start, end: end, occurrence: event.occurrenceDate,
                                      isAllDay: event.isAllDay, isCancelled: event.status == .canceled,
                                      isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
                                      joinURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
        }
        recompute()
    }

    // MARK: Google / Outlook links

    /// Every 10 minutes: re-read links, and re-query Apple Calendar so the
    /// 36-hour look-ahead keeps moving even when the store doesn't change.
    private func scheduleFeedTimer() {
        feedTimer?.invalidate(); feedTimer = nil
        guard settings.enabled else { return }
        let timer = Timer(timeInterval: Self.feedRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSystem(); self?.refreshFeeds() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        feedTimer = timer
    }

    private func refreshFeeds() {
        let ids = Set(settings.feeds.map(\.id) + (debugMode ? ["debug-file"] : []))
        feedEvents = feedEvents.filter { ids.contains($0.key) }
        feedStatus = feedStatus.filter { ids.contains($0.key) }
        guard settings.enabled || settingsWindow?.window?.isVisible == true else { return }
        for feed in settings.feeds { fetch(feed) }
    }

    private func fetch(_ feed: CalendarFeedConfig) {
        guard feedTasks[feed.id] == nil, let url = CalendarFeedConfig.normalizedURL(feed.url) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let owner = ICSFeed.ownerEmail(fromFeedURL: url)
        let maxBytes = Self.maxFeedBytes, lookAhead = Self.lookAhead, late = CalendarAlarmScheduler.lateStartInterval
        let calendarID = feed.calendarID, feedID = feed.id
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var parsed: Result<[CalendarAlarmEvent], Error>
            if let error { parsed = .failure(error) }
            else if !(200..<300).contains(status) { parsed = .failure(FeedFetchError("The calendar link answered HTTP \(status).")) }
            else if let data, data.count <= maxBytes, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                // Parsing runs on URLSession's background queue, never the main thread.
                let now = Date()
                let window = DateInterval(start: now.addingTimeInterval(-late), end: now.addingTimeInterval(lookAhead))
                parsed = Result {
                    CalendarAlarmEvent.fromFeed(try ICSFeed.events(from: text, window: window, ownerEmail: owner),
                                                calendarID: calendarID)
                }
            } else { parsed = .failure(FeedFetchError("The calendar link returned no readable calendar (or more than 12 MB).")) }
            let result = parsed
            Task { @MainActor in self?.finishFetch(feedID, result) }
        }
        feedTasks[feed.id] = task
        task.resume()
    }

    private func finishFetch(_ id: String, _ result: Result<[CalendarAlarmEvent], Error>) {
        feedTasks[id] = nil
        guard settings.feeds.contains(where: { $0.id == id }) else { return }
        switch result {
        case .success(let events):
            feedEvents[id] = events
            feedStatus[id] = "Updated \(Date().formatted(date: .omitted, time: .shortened)) · \(events.count) upcoming"
        case .failure(let error):
            // Keep the last good events; a brief outage shouldn't cancel reminders.
            feedStatus[id] = "Couldn’t refresh: \(error.localizedDescription)"
        }
        recompute()
    }

    private func addFeed(_ text: String) -> String {
        guard let url = CalendarFeedConfig.normalizedURL(text) else {
            return "Paste an https:// or webcal:// calendar link (ICS)."
        }
        guard !settings.feeds.contains(where: { CalendarFeedConfig.normalizedURL($0.url) == url }) else {
            return "That calendar link is already added."
        }
        guard settings.feeds.count < 12 else { return "Up to 12 calendar links are supported." }
        let feed = CalendarFeedConfig(name: CalendarFeedConfig.suggestedName(for: url), url: url.absoluteString)
        var value = settings
        value.feeds.append(feed)
        value.calendarIDs.insert(feed.calendarID)
        if !hasAccess || !value.enabled { value.enabled = true }
        feedStatus[feed.id] = "Fetching…"
        changeSettings(value)
        return "Added \(feed.name)."
    }

    private func removeFeed(_ id: String) {
        var value = settings
        value.feeds.removeAll { $0.id == id }
        value.calendarIDs.remove("feed:" + id)
        feedTasks[id]?.cancel(); feedTasks[id] = nil
        feedEvents[id] = nil; feedStatus[id] = nil
        changeSettings(value)
    }

    // MARK: Scheduling

    private func changeSettings(_ value: CalendarAlarmSettings) {
        let wasEnabled = settings.enabled
        settings = value
        if !canEnable { settings.enabled = false }
        persist()
        queue.removeAll(); active = nil; alertWindow?.hide()
        scheduleFeedTimer()
        refreshSystem()
        if settings.enabled && (!wasEnabled || feedEvents.count < settings.feeds.count) { refreshFeeds() }
    }

    /// Merges sources, updates the menu-bar data and re-arms the single timer.
    private func recompute() {
        let now = Date()
        events = CalendarAlarmEvent.deduplicated(systemEvents + feedEvents.values.flatMap { $0 })
        let valid = events.filter { scheduler.eligible($0, settings: settings, now: now) }
        upcoming = valid.prefix(12).map { Upcoming(title: $0.title, start: $0.start, end: $0.end, joinURL: $0.joinURL) }
        // Update queued text/times, and drop cancelled, removed, expired or deselected events.
        queue = queue.compactMap { queued in valid.first { $0.key == queued.key } }
        if let current = active {
            active = valid.first { $0.key == current.key }
            if active == nil { alertWindow?.hide(); showNext() }
        }
        onUpcomingChanged?()
        updateWindow()
        tick()
    }

    private func tick() {
        fireTimer?.invalidate(); fireTimer = nil
        guard settings.enabled else {
            if active != nil || !queue.isEmpty { active = nil; queue = []; alertWindow?.hide() }
            return
        }
        // While the screen sleeps, keep the card and queue; show them on wake.
        guard sessionActive else { return }
        let now = Date()
        let before = scheduler.receipts
        for event in scheduler.due(events: events, settings: settings, now: now) {
            if event.key == active?.key { active = event; present(event) }
            else if !queue.contains(where: { $0.key == event.key }) { queue.append(event) }
        }
        if scheduler.receipts != before { persist() }
        if let current = active, current.end <= now { active = nil; alertWindow?.hide() }
        showNext()
        // Sleep until the next owed reminder or the end of the card on screen.
        var wake = scheduler.nextFireDate(events: events, settings: settings, now: now)
        if let current = active { wake = min(wake ?? current.end, current.end) }
        guard let wake else { return }
        let timer = Timer(fire: max(wake, now.addingTimeInterval(0.05)), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    private func showNext() {
        guard sessionActive else { return }
        if active == nil {
            while !queue.isEmpty {
                let next = queue.removeFirst()
                guard scheduler.eligible(next, settings: settings, now: Date()) else { continue }
                active = next; present(next); break
            }
        } else if alertWindow?.window?.isVisible != true, let active { present(active, sound: false) }
    }

    private func present(_ event: CalendarAlarmEvent, sound: Bool = true) {
        let now = Date()
        let title = settings.showEventTitles ? String(event.title.prefix(160)) : "Your next meeting"
        let time = event.start.formatted(date: .omitted, time: .shortened)
        let until = event.start.timeIntervalSince(now)
        let detail: String
        if until > 60 { detail = "Starts in \(Int((until / 60).rounded())) min · \(time)" }
        else if until > -60 { detail = "Starting now · \(time)" }
        else { detail = "Started \(Int((-until / 60).rounded())) min ago · \(time)" }
        let provider = event.joinURL.flatMap { MeetingLink.provider(for: $0) }
        let snoozeTitle = until > 60 ? "Remind me at start" : "Snooze 1 min"
        showAlert(title: title, detail: detail, joinTitle: provider.map { "Join \($0)" }, snoozeTitle: snoozeTitle, sound: sound,
                  join: event.joinURL.map { url in { [weak self] in self?.join(url) } },
                  snooze: { [weak self] in
                      guard let self else { return }
                      self.scheduler.snooze(event, now: Date()); self.persist(); self.dismiss()
                  })
    }

    private func showAlert(title: String, detail: String, joinTitle: String?, snoozeTitle: String, sound: Bool,
                           join: (() -> Void)?, snooze: (() -> Void)?) {
        if alertWindow == nil { alertWindow = PetAlarmWindow() }
        alertWindow?.onDismiss = { [weak self] in self?.dismiss() }
        alertWindow?.onSnooze = snooze
        alertWindow?.onJoin = join
        alertWindow?.present(title: title, detail: detail, joinTitle: joinTitle, snoozeTitle: snoozeTitle)
        if sound && settings.sound { NSSound(named: NSSound.Name("Glass"))?.play() }
        if sound { onPetAlert?() }
    }

    private func dismiss() {
        active = nil; alertWindow?.hide(); showNext(); tick()
    }

    func testAlarm() {
        guard sessionActive else { return }
        // Keep a real reminder intact; the preview never needs calendar access.
        guard active == nil else { return }
        showAlert(title: "Your whippet is on reminder duty.", detail: "This is a test. Real reminders show the meeting, its time and a Join button.",
                  joinTitle: nil, snoozeTitle: "Snooze 1 min", sound: true, join: nil, snooze: nil)
    }

    // MARK: Open at login

    private var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            permissionError = "Open at login could not be changed: \(error.localizedDescription)"
        }
        updateWindow()
        if on && SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// `--feed-file PATH` and `--feed-url URL` add an in-memory source for
    /// testing. Nothing about them is written to preferences.
    func enableDebugSources(feedFile: String?, feedURL: String?) {
        guard feedFile != nil || feedURL != nil else { return }
        debugMode = true
        settings.enabled = true
        if let feedFile {
            let calendarID = "feed:debug-file"
            settings.calendarIDs.insert(calendarID)
            let now = Date()
            do {
                let text = try String(contentsOfFile: feedFile, encoding: .utf8)
                let parsed = try ICSFeed.events(from: text, window: DateInterval(start: now.addingTimeInterval(-CalendarAlarmScheduler.lateStartInterval),
                                                                                 end: now.addingTimeInterval(Self.lookAhead)))
                feedEvents["debug-file"] = CalendarAlarmEvent.fromFeed(parsed, calendarID: calendarID)
                feedStatus["debug-file"] = "Loaded \(parsed.count) from file"
            } catch { feedStatus["debug-file"] = "File error: \(error.localizedDescription)" }
        }
        if let feedURL, let url = CalendarFeedConfig.normalizedURL(feedURL) {
            let feed = CalendarFeedConfig(id: "debug-url", name: "Debug link", url: url.absoluteString)
            settings.feeds.append(feed); settings.calendarIDs.insert(feed.calendarID)
            fetch(feed)
        }
        scheduleFeedTimer()
        recompute()
    }

    var diagnostics: [String: Any] {
        [
            "remindersEnabled": settings.enabled,
            "eventCount": events.count,
            "upcoming": upcoming.prefix(5).map { ["start": ISO8601DateFormatter().string(from: $0.start),
                                                  "hasJoinLink": $0.joinURL != nil] },
            "nextReminder": scheduler.nextFireDate(events: events, settings: settings, now: Date())
                .map { ISO8601DateFormatter().string(from: $0) } ?? "none",
            "cardVisible": alertWindow?.window?.isVisible ?? false,
            "cardHasJoin": active?.joinURL != nil,
            "queued": queue.count,
            "timerArmed": fireTimer?.isValid ?? false,
            "feedStatus": feedStatus,
            "eventKitOpened": store != nil
        ]
    }

    private func persist() {
        if !debugMode, let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "calendarAlarms.settings") }
        if let data = try? JSONEncoder().encode(scheduler.receipts) { defaults.set(data, forKey: "calendarAlarms.receipts") }
    }

    private func updateWindow() {
        guard let settingsWindow, settingsWindow.window?.isVisible == true else { return }
        let status: String
        if let permissionError { status = permissionError }
        else if requestingAccess { status = "Waiting for your calendar permission…" }
        else if !canEnable {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .denied, .restricted:
                status = "Apple Calendar access is off. Allow LokiDot in System Settings → Privacy & Security → Calendars, or add a Google/Outlook link below."
            default: status = "Connect Apple Calendar, or add a Google or Outlook calendar link below."
            }
        } else if !settings.enabled { status = "Connected. Choose calendars and turn reminders on when you’re ready." }
        else if settings.calendarIDs.isDisjoint(with: Set(calendars.map(\.id) + settings.feeds.map(\.calendarID))) && !calendars.isEmpty {
            status = "Choose at least one calendar below."
        } else {
            let next = scheduler.nextFireDate(events: events, settings: settings, now: Date())
            status = next.map { "Next reminder: \($0.formatted(date: .abbreviated, time: .shortened))." }
                ?? "Watching your calendars. No meetings in the next 36 hours."
        }
        let rows = settings.feeds.map { FeedRow(id: $0.id, name: $0.name, status: feedStatus[$0.id] ?? "Not fetched yet") }
        settingsWindow.update(settings: settings, calendars: calendars, feeds: rows, hasAccess: hasAccess,
                              canEnable: canEnable, requesting: requestingAccess, opensAtLogin: opensAtLogin, status: status)
    }
}
