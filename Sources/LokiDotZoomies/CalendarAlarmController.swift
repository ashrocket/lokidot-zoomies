import AppKit
import EventKit
import ZoomiesCore

@MainActor
final class CalendarAlarmController: NSObject {
    struct CalendarChoice: Equatable {
        let id: String
        let title: String
    }
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private(set) var settings: CalendarAlarmSettings
    private var scheduler: CalendarAlarmScheduler
    private var calendars: [CalendarChoice] = []
    private var events: [CalendarAlarmEvent] = []
    private var queue: [CalendarAlarmEvent] = []
    private var active: CalendarAlarmEvent?
    private var timer: Timer?
    private var lastRefresh = Date.distantPast
    private var sessionActive = true
    private var requestingAccess = false
    private var permissionError: String?
    private var settingsWindow: CalendarAlarmWindow?
    private var alertWindow: PetAlarmWindow?
    var onPetAlert: (() -> Void)?

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

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .EKEventStoreChanged, object: store)
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.5
        refresh()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        alertWindow?.hide()
    }

    func setSessionActive(_ value: Bool) {
        sessionActive = value
        if value { refresh(); tick() }
        else { alertWindow?.hide() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = CalendarAlarmWindow()
            window.onConnect = { [weak self] in self?.requestAccess() }
            window.onChange = { [weak self] value in self?.changeSettings(value) }
            window.onRefresh = { [weak self] in self?.refresh() }
            window.onTest = { [weak self] in self?.testAlarm() }
            settingsWindow = window
        }
        settingsWindow?.present()
        refresh()
    }

    private func requestAccess() {
        guard !requestingAccess else { return }
        guard !hasAccess else { refresh(); return }
        requestingAccess = true; permissionError = nil; updateWindow()
        // This is reached only from the explicit Connect calendars button.
        // EventKit offers no read-only permission; the app never writes events.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if #available(macOS 14.0, *) { _ = try await self.store.requestFullAccessToEvents() }
                else { _ = try await self.store.requestAccess(to: .event) }
            } catch {
                self.permissionError = "Calendar access could not be requested. Check System Settings → Privacy & Security → Calendars."
            }
            self.requestingAccess = false
            self.store.reset()
            self.refresh()
        }
    }

    private func changeSettings(_ value: CalendarAlarmSettings) {
        settings = value
        if !hasAccess { settings.enabled = false }
        persist()
        queue.removeAll(); active = nil; alertWindow?.hide()
        refresh()
    }

    @objc private func storeChanged() { refresh() }

    private func refresh() {
        lastRefresh = Date()
        guard hasAccess else {
            calendars = []; events = []; queue = []; active = nil
            alertWindow?.hide(); updateWindow(); return
        }
        // A disabled background integration does not fetch the calendar store.
        guard settings.enabled || settingsWindow?.window?.isVisible == true else {
            calendars = []; events = []; updateWindow(); return
        }
        let available = store.calendars(for: .event)
        calendars = available.map {
            CalendarChoice(id: $0.calendarIdentifier, title: "\($0.title) · \($0.source.title)")
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let selected = available.filter { settings.calendarIDs.contains($0.calendarIdentifier) }
        guard settings.enabled && !selected.isEmpty else {
            events = []; queue = []; active = nil; alertWindow?.hide(); updateWindow(); return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-CalendarAlarmScheduler.catchUpInterval),
                                                 end: now.addingTimeInterval(86400), calendars: selected)
        events = store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate, let calendar = event.calendar else { return nil }
            return CalendarAlarmEvent(id: event.eventIdentifier ?? event.calendarItemIdentifier,
                                      calendarID: calendar.calendarIdentifier,
                                      title: event.title?.isEmpty == false ? event.title! : "Calendar event",
                                      start: start, end: end, occurrence: event.occurrenceDate,
                                      isAllDay: event.isAllDay, isCancelled: event.status == .canceled,
                                      isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
        // Update queued text/times, and drop cancelled, removed, expired or deselected events.
        let valid = events.filter { scheduler.eligible($0, settings: settings, now: now) }
        queue = queue.compactMap { queued in valid.first { $0.key == queued.key } }
        if let current = active {
            active = valid.first { $0.key == current.key }
            if active == nil { alertWindow?.hide() }
        }
        updateWindow()
    }

    private func tick() {
        guard sessionActive else { return }
        if Date().timeIntervalSince(lastRefresh) >= 60 { refresh() }
        guard hasAccess, settings.enabled else {
            if active != nil || !queue.isEmpty { active = nil; queue = []; alertWindow?.hide() }
            return
        }
        let before = scheduler.receipts
        queue.append(contentsOf: scheduler.due(events: events, settings: settings, now: Date()))
        if scheduler.receipts != before { persist(); updateWindow() }
        if let current = active, current.end <= Date() { active = nil; alertWindow?.hide() }
        showNext()
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
        let title = settings.showEventTitles ? String(event.title.prefix(160)) : "Your calendar is calling."
        let time = event.start.formatted(date: .omitted, time: .shortened)
        let detail = event.start > Date() ? "Starts at \(time). Your pet has your back." : "Started at \(time). Time to go!"
        showAlert(title: title, detail: detail, sound: sound, snooze: { [weak self] in
            guard let self else { return }
            self.scheduler.snooze(event, now: Date()); self.persist(); self.dismiss()
        })
    }

    private func showAlert(title: String, detail: String, sound: Bool, snooze: (() -> Void)?) {
        if alertWindow == nil { alertWindow = PetAlarmWindow() }
        alertWindow?.onDismiss = { [weak self] in self?.dismiss() }
        alertWindow?.onSnooze = snooze
        alertWindow?.present(title: title, detail: detail)
        if sound && settings.sound { NSSound(named: NSSound.Name("Glass"))?.play() }
        if sound { onPetAlert?() }
    }

    private func dismiss() {
        active = nil; alertWindow?.hide(); showNext()
    }

    func testAlarm() {
        guard sessionActive else { return }
        // Keep a real reminder intact; the preview never needs calendar access.
        guard active == nil else { return }
        showAlert(title: "Your pet is on alarm duty.", detail: "This is a test. No calendar event was created.", sound: true, snooze: nil)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "calendarAlarms.settings") }
        if let data = try? JSONEncoder().encode(scheduler.receipts) { defaults.set(data, forKey: "calendarAlarms.receipts") }
    }

    private func updateWindow() {
        let status: String
        if let permissionError { status = permissionError }
        else if requestingAccess { status = "Waiting for your calendar permission…" }
        else if !hasAccess {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .denied, .restricted:
                status = "Calendar access is off. Allow LokiDot in System Settings → Privacy & Security → Calendars, then refresh."
            default: status = "Connect your calendars, choose which ones to watch, then turn alarms on."
            }
        } else if !settings.enabled { status = "Connected. Choose your calendars and turn alarms on when you’re ready." }
        else if settings.calendarIDs.isDisjoint(with: Set(calendars.map(\.id))) { status = "Choose at least one available calendar below." }
        else {
            let now = Date()
            let next = events.filter { scheduler.eligible($0, settings: settings, now: now) }
                .compactMap { scheduler.nextDate(for: $0, settings: settings) }
                .filter { $0 >= now }.min()
            status = next.map { "Next pet alarm: \($0.formatted(date: .abbreviated, time: .shortened))." }
                ?? "Watching your calendars. No upcoming alarms in the next 24 hours."
        }
        settingsWindow?.update(settings: settings, calendars: calendars, hasAccess: hasAccess,
                               requesting: requestingAccess, status: status)
    }
}
