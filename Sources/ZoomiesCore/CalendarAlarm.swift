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

    public init(id: String, calendarID: String, title: String, start: Date, end: Date,
                occurrence: Date? = nil, isAllDay: Bool = false,
                isCancelled: Bool = false, isDeclined: Bool = false) {
        self.id = id; self.calendarID = calendarID; self.title = title
        self.start = start; self.end = end; self.occurrence = occurrence ?? start
        self.isAllDay = isAllDay; self.isCancelled = isCancelled; self.isDeclined = isDeclined
    }

    // A recurring series can share an event identifier. The original occurrence
    // also stays stable if a detached occurrence is moved to a different time.
    public var key: String {
        [Data(calendarID.utf8).base64EncodedString(), Data(id.utf8).base64EncodedString(),
         String(occurrence.timeIntervalSince1970)].joined(separator: ".")
    }
}

public struct CalendarAlarmSettings: Codable, Equatable {
    public var enabled = false
    public var calendarIDs: Set<String> = []
    public var leadMinutes = 5
    public var sound = true
    public var showEventTitles = false
    public init() {}
    public static let allowedLeadMinutes = [0, 1, 5, 10, 15]
    public var leadInterval: TimeInterval {
        TimeInterval(Self.allowedLeadMinutes.contains(leadMinutes) ? leadMinutes : 5) * 60
    }
}

/// Only opaque event keys and delivery times are persisted, never event titles.
public struct CalendarAlarmReceipt: Codable, Equatable {
    public var key: String
    public var expires: Date
    public var snoozedUntil: Date?
    public init(key: String, expires: Date, snoozedUntil: Date? = nil) {
        self.key = key; self.expires = expires; self.snoozedUntil = snoozedUntil
    }
}

public struct CalendarAlarmScheduler {
    public private(set) var receipts: [CalendarAlarmReceipt]
    public static let catchUpInterval: TimeInterval = 120
    public init(receipts: [CalendarAlarmReceipt] = []) { self.receipts = receipts }

    public func eligible(_ event: CalendarAlarmEvent, settings: CalendarAlarmSettings, now: Date) -> Bool {
        settings.enabled && settings.calendarIDs.contains(event.calendarID) &&
        !event.isAllDay && !event.isCancelled && !event.isDeclined &&
        event.end > now && event.end >= event.start
    }

    public func nextDate(for event: CalendarAlarmEvent, settings: CalendarAlarmSettings) -> Date? {
        if let receipt = receipts.first(where: { $0.key == event.key }) { return receipt.snoozedUntil }
        return event.start.addingTimeInterval(-settings.leadInterval)
    }

    public mutating func due(events: [CalendarAlarmEvent], settings: CalendarAlarmSettings,
                             now: Date) -> [CalendarAlarmEvent] {
        receipts.removeAll { $0.expires < now }
        guard settings.enabled else { return [] }
        var result: [CalendarAlarmEvent] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            guard eligible(event, settings: settings, now: now),
                  let fire = nextDate(for: event, settings: settings), fire <= now,
                  now.timeIntervalSince(fire) <= Self.catchUpInterval else { continue }
            if let index = receipts.firstIndex(where: { $0.key == event.key }) {
                receipts[index].snoozedUntil = nil
                receipts[index].expires = max(receipts[index].expires, event.end.addingTimeInterval(86400))
            } else {
                receipts.append(CalendarAlarmReceipt(key: event.key, expires: event.end.addingTimeInterval(86400)))
            }
            result.append(event)
        }
        return result
    }

    public mutating func snooze(_ event: CalendarAlarmEvent, now: Date) {
        guard let index = receipts.firstIndex(where: { $0.key == event.key }) else { return }
        receipts[index].snoozedUntil = now.addingTimeInterval(5 * 60)
    }
}
