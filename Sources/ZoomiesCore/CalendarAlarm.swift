import Foundation

/// Calendar data stays local. Scheduling uses absolute instants, so DST and
/// timezone changes don't turn a five-minute reminder into a different alarm.
public struct CalendarAlarmEvent: Equatable {
    public let id: String
    public let calendarID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let occurrence: Date
    public let isAllDay: Bool
    public let isCancelled: Bool
    public let isDeclined: Bool
    /// One-click join link found in the event (Zoom, Meet, Teams, Webex…).
    public let joinURL: URL?

    public init(id: String, calendarID: String, title: String, start: Date, end: Date,
                occurrence: Date? = nil, isAllDay: Bool = false,
                isCancelled: Bool = false, isDeclined: Bool = false, joinURL: URL? = nil) {
        self.id = id; self.calendarID = calendarID; self.title = title
        self.start = start; self.end = end; self.occurrence = occurrence ?? start
        self.isAllDay = isAllDay; self.isCancelled = isCancelled; self.isDeclined = isDeclined
        self.joinURL = joinURL
    }

    // A recurring series can share an event identifier. The original occurrence
    // also stays stable if a detached occurrence is moved to a different time.
    public var key: String {
        [Data(calendarID.utf8).base64EncodedString(), Data(id.utf8).base64EncodedString(),
         String(occurrence.timeIntervalSince1970)].joined(separator: ".")
    }

    /// Converts parsed feed instances. Feed events use `feed:<id>` calendar IDs.
    public static func fromFeed(_ events: [FeedEvent], calendarID: String) -> [CalendarAlarmEvent] {
        events.map {
            CalendarAlarmEvent(id: $0.uid, calendarID: calendarID, title: $0.title.isEmpty ? "Calendar event" : $0.title,
                               start: $0.start, end: $0.end, occurrence: $0.occurrence, isAllDay: $0.isAllDay,
                               isCancelled: $0.isCancelled, isDeclined: $0.isDeclined,
                               joinURL: MeetingLink.find(in: [$0.conferenceURL, $0.url, $0.location, $0.notes]))
        }
    }

    /// The same meeting often arrives twice: from Apple Calendar's synced
    /// Google account and from that calendar's ICS link. Keep one, preferring
    /// the copy with a join link.
    public static func deduplicated(_ events: [CalendarAlarmEvent]) -> [CalendarAlarmEvent] {
        var seen: [String: Int] = [:]
        var result: [CalendarAlarmEvent] = []
        for event in events.sorted(by: { $0.start == $1.start ? $0.key < $1.key : $0.start < $1.start }) {
            let identity = "\(event.start.timeIntervalSince1970)|\(event.title.lowercased())"
            if let index = seen[identity] {
                if result[index].joinURL == nil && event.joinURL != nil { result[index] = event }
                continue
            }
            seen[identity] = result.count
            result.append(event)
        }
        return result
    }
}

/// A Google "secret address in iCal format" or an Outlook published-calendar
/// ICS link, read directly so it doesn't depend on Apple Calendar sync.
public struct CalendarFeedConfig: Codable, Equatable {
    public let id: String
    public var name: String
    public let url: String
    public init(id: String = UUID().uuidString, name: String, url: String) {
        self.id = id; self.name = name; self.url = url
    }
    public var calendarID: String { "feed:" + id }

    /// Accepts https:// and webcal:// links; returns the https URL to fetch.
    public static func normalizedURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if value.lowercased().hasPrefix("webcal://") { value = "https://" + value.dropFirst("webcal://".count) }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// A short, non-secret label for a feed URL: never shows the private token.
    public static func suggestedName(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("calendar.google.com") {
            return ICSFeed.ownerEmail(fromFeedURL: url).map { "Google · \($0)" } ?? "Google Calendar"
        }
        if host.hasSuffix("outlook.office365.com") || host.hasSuffix("outlook.live.com") || host.hasSuffix("outlook.office.com") {
            return "Outlook calendar"
        }
        return host.isEmpty ? "Calendar link" : host
    }
}

public struct CalendarAlarmSettings: Codable, Equatable {
    public var enabled = false
    public var calendarIDs: Set<String> = []
    public var leadMinutes = 5
    /// A second reminder when the meeting starts, after the heads-up.
    public var alsoAtStart = true
    public var sound = true
    /// Titles help you act on a reminder. Turn off before screen sharing.
    public var showEventTitles = true
    public var feeds: [CalendarFeedConfig] = []
    public init() {}
    public static let allowedLeadMinutes = [0, 1, 2, 5, 10, 15]
    public var leadInterval: TimeInterval {
        TimeInterval(Self.allowedLeadMinutes.contains(leadMinutes) ? leadMinutes : 5) * 60
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, calendarIDs, leadMinutes, alsoAtStart, sound, showEventTitles, feeds
    }
    // Settings saved by older builds lack newer fields; keep their values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        calendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .calendarIDs) ?? []
        leadMinutes = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? 5
        alsoAtStart = try c.decodeIfPresent(Bool.self, forKey: .alsoAtStart) ?? true
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        showEventTitles = try c.decodeIfPresent(Bool.self, forKey: .showEventTitles) ?? true
        feeds = try c.decodeIfPresent([CalendarFeedConfig].self, forKey: .feeds) ?? []
    }
}

/// Only opaque event keys and delivery times are persisted, never event titles.
public struct CalendarAlarmReceipt: Codable, Equatable {
    public var key: String
    public var expires: Date
    public var snoozedUntil: Date?
    /// Set once the at-start reminder (or a reminder at/after the start) was shown.
    public var startDelivered: Bool?
    public init(key: String, expires: Date, snoozedUntil: Date? = nil, startDelivered: Bool? = nil) {
        self.key = key; self.expires = expires; self.snoozedUntil = snoozedUntil; self.startDelivered = startDelivered
    }
}

public struct CalendarAlarmScheduler {
    public private(set) var receipts: [CalendarAlarmReceipt]
    /// A missed heads-up still shows while the meeting hasn't started. A missed
    /// start reminder shows for this long after the start, if the meeting is on.
    public static let lateStartInterval: TimeInterval = 10 * 60
    public init(receipts: [CalendarAlarmReceipt] = []) { self.receipts = receipts }

    public func eligible(_ event: CalendarAlarmEvent, settings: CalendarAlarmSettings, now: Date) -> Bool {
        settings.enabled && settings.calendarIDs.contains(event.calendarID) &&
        !event.isAllDay && !event.isCancelled && !event.isDeclined &&
        event.end > now && event.end >= event.start
    }

    /// The next reminder instant still owed for this event, or nil.
    public func nextDate(for event: CalendarAlarmEvent, settings: CalendarAlarmSettings) -> Date? {
        let lead = settings.leadInterval
        guard let receipt = receipts.first(where: { $0.key == event.key }) else {
            return event.start.addingTimeInterval(-lead)
        }
        if let snoozed = receipt.snoozedUntil { return snoozed }
        if receipt.startDelivered != true && lead > 0 && settings.alsoAtStart { return event.start }
        return nil
    }

    /// The earliest instant at which `due` could return something. The app
    /// sleeps until then instead of polling.
    public func nextFireDate(events: [CalendarAlarmEvent], settings: CalendarAlarmSettings, now: Date) -> Date? {
        guard settings.enabled else { return nil }
        return events.filter { eligible($0, settings: settings, now: now) }
            .compactMap { event in nextDate(for: event, settings: settings).flatMap { lateLimitHolds($0, event, now) ? $0 : nil } }
            .min()
    }

    private func lateLimitHolds(_ fire: Date, _ event: CalendarAlarmEvent, _ now: Date) -> Bool {
        fire > now || now < event.start || now.timeIntervalSince(event.start) <= Self.lateStartInterval
    }

    public mutating func due(events: [CalendarAlarmEvent], settings: CalendarAlarmSettings,
                             now: Date) -> [CalendarAlarmEvent] {
        receipts.removeAll { $0.expires < now }
        guard settings.enabled else { return [] }
        var result: [CalendarAlarmEvent] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            guard eligible(event, settings: settings, now: now),
                  let fire = nextDate(for: event, settings: settings), fire <= now else { continue }
            let started = now >= event.start
            // A missed start reminder is only useful shortly after the start.
            guard !started || now.timeIntervalSince(event.start) <= Self.lateStartInterval else {
                markDelivered(event, started: true); continue
            }
            markDelivered(event, started: started)
            result.append(event)
        }
        return result
    }

    private mutating func markDelivered(_ event: CalendarAlarmEvent, started: Bool) {
        let expires = event.end.addingTimeInterval(86400)
        if let index = receipts.firstIndex(where: { $0.key == event.key }) {
            receipts[index].snoozedUntil = nil
            receipts[index].expires = max(receipts[index].expires, expires)
            if started { receipts[index].startDelivered = true }
        } else {
            receipts.append(CalendarAlarmReceipt(key: event.key, expires: expires, startDelivered: started ? true : nil))
        }
    }

    /// Snoozes to the meeting start when it is more than a minute away,
    /// otherwise for one minute.
    public mutating func snooze(_ event: CalendarAlarmEvent, now: Date) {
        guard let index = receipts.firstIndex(where: { $0.key == event.key }) else { return }
        receipts[index].snoozedUntil = Self.snoozeTarget(for: event, now: now)
    }

    public static func snoozeTarget(for event: CalendarAlarmEvent, now: Date) -> Date {
        event.start.timeIntervalSince(now) > 60 ? event.start : now.addingTimeInterval(60)
    }
}
