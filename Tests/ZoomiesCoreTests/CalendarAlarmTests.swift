import XCTest
@testable import ZoomiesCore

final class CalendarAlarmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var settings: CalendarAlarmSettings {
        var value = CalendarAlarmSettings(); value.enabled = true; value.calendarIDs = ["apple", "google"]
        return value
    }
    private func event(_ id: String = "event", calendar: String = "apple", start: TimeInterval = 300,
                       end: TimeInterval = 3900, occurrence: TimeInterval? = nil,
                       allDay: Bool = false, cancelled: Bool = false, declined: Bool = false) -> CalendarAlarmEvent {
        CalendarAlarmEvent(id: id, calendarID: calendar, title: "Synthetic meeting", start: now.addingTimeInterval(start),
                           end: now.addingTimeInterval(end), occurrence: occurrence.map { now.addingTimeInterval($0) },
                           isAllDay: allDay, isCancelled: cancelled, isDeclined: declined)
    }

    func testDefaultsAreOptInWithHeadsUpAndStartReminders() {
        let value = CalendarAlarmSettings()
        XCTAssertFalse(value.enabled); XCTAssertTrue(value.calendarIDs.isEmpty); XCTAssertTrue(value.showEventTitles)
        XCTAssertEqual(value.leadMinutes, 5); XCTAssertTrue(value.alsoAtStart); XCTAssertTrue(value.feeds.isEmpty)
        var scheduler = CalendarAlarmScheduler()
        XCTAssertTrue(scheduler.due(events: [event()], settings: value, now: now).isEmpty)
    }

    func testFiresAtLeadTimeButNeverEarlyOrTwice() {
        var scheduler = CalendarAlarmScheduler()
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(-0.1)).isEmpty)
        XCTAssertEqual(scheduler.due(events: [event(), event()], settings: settings, now: now), [event()])
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(1)).isEmpty)
    }

    func testAppleAndGoogleSelectionsAreIndependent() {
        var scheduler = CalendarAlarmScheduler(), selected = settings
        selected.calendarIDs = ["google"]
        XCTAssertEqual(scheduler.due(events: [event(), event(calendar: "google")], settings: selected, now: now), [event(calendar: "google")])
        selected.calendarIDs = []
        XCTAssertTrue(scheduler.due(events: [event()], settings: selected, now: now).isEmpty)
    }

    func testAllDayCancelledDeclinedExpiredAndInvalidEventsAreSkipped() {
        let skipped = [event("day", allDay: true), event("cancel", cancelled: true), event("decline", declined: true),
                       event("expired", start: -300, end: 0), event("invalid", start: 300, end: 100)]
        var scheduler = CalendarAlarmScheduler()
        XCTAssertTrue(scheduler.due(events: skipped, settings: settings, now: now).isEmpty)
        XCTAssertTrue(scheduler.receipts.isEmpty)
    }

    func testWakeShowsMissedHeadsUpBeforeStartAndStartOnlyBrieflyAfter() {
        var scheduler = CalendarAlarmScheduler()
        // Heads-up missed by minutes, meeting not started yet: still useful.
        XCTAssertEqual(scheduler.due(events: [event("soon", start: 60)], settings: settings, now: now).map(\.id), ["soon"])
        // Started 9 minutes ago with nothing shown: one start reminder.
        XCTAssertEqual(scheduler.due(events: [event("late", start: -540)], settings: settings, now: now).map(\.id), ["late"])
        XCTAssertTrue(scheduler.due(events: [event("late", start: -540)], settings: settings, now: now.addingTimeInterval(1)).isEmpty)
        // Started 11 minutes ago: too late, and never shown later either.
        XCTAssertTrue(scheduler.due(events: [event("stale", start: -660)], settings: settings, now: now).isEmpty)
        XCTAssertNil(scheduler.nextFireDate(events: [event("stale", start: -660)], settings: settings, now: now.addingTimeInterval(1)))
    }

    func testHeadsUpThenStartReminderEachFireOnce() {
        var scheduler = CalendarAlarmScheduler()
        XCTAssertEqual(scheduler.due(events: [event()], settings: settings, now: now), [event()])
        XCTAssertEqual(scheduler.nextFireDate(events: [event()], settings: settings, now: now.addingTimeInterval(1)), now.addingTimeInterval(300))
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(299)).isEmpty)
        XCTAssertEqual(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(300)), [event()])
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(301)).isEmpty)
        XCTAssertNil(scheduler.nextFireDate(events: [event()], settings: settings, now: now.addingTimeInterval(301)))
    }

    func testStartReminderCanBeTurnedOff() {
        var scheduler = CalendarAlarmScheduler(), single = settings
        single.alsoAtStart = false
        XCTAssertEqual(scheduler.due(events: [event()], settings: single, now: now), [event()])
        XCTAssertTrue(scheduler.due(events: [event()], settings: single, now: now.addingTimeInterval(300)).isEmpty)
    }

    func testNextFireDateIsTheEarliestOwedReminderOnly() {
        let scheduler = CalendarAlarmScheduler()
        let events = [event("b", start: 1200, end: 4800), event("a", start: 600, end: 4200), event("x", calendar: "other", start: 400)]
        XCTAssertEqual(scheduler.nextFireDate(events: events, settings: settings, now: now), now.addingTimeInterval(300))
        var off = settings; off.enabled = false
        XCTAssertNil(scheduler.nextFireDate(events: events, settings: off, now: now))
    }

    func testSnoozeGoesToStartOrOneMinute() {
        XCTAssertEqual(CalendarAlarmScheduler.snoozeTarget(for: event(), now: now), now.addingTimeInterval(300))
        XCTAssertEqual(CalendarAlarmScheduler.snoozeTarget(for: event(), now: now.addingTimeInterval(270)), now.addingTimeInterval(330))
    }

    func testOlderSavedSettingsKeepValuesAndGainNewDefaults() throws {
        let old = #"{"enabled":true,"calendarIDs":["a"],"leadMinutes":10,"sound":false,"showEventTitles":false}"#
        let value = try JSONDecoder().decode(CalendarAlarmSettings.self, from: Data(old.utf8))
        XCTAssertTrue(value.enabled); XCTAssertEqual(value.calendarIDs, ["a"]); XCTAssertEqual(value.leadMinutes, 10)
        XCTAssertFalse(value.sound); XCTAssertFalse(value.showEventTitles); XCTAssertTrue(value.alsoAtStart); XCTAssertTrue(value.feeds.isEmpty)
        let receipt = try JSONDecoder().decode(CalendarAlarmReceipt.self, from: Data(#"{"key":"k","expires":0}"#.utf8))
        XCTAssertNil(receipt.startDelivered)
    }

    func testFeedLinksAcceptHTTPSAndWebcalOnly() {
        XCTAssertEqual(CalendarFeedConfig.normalizedURL(" webcal://outlook.office365.com/owa/calendar/a/b/calendar.ics ")?.absoluteString,
                       "https://outlook.office365.com/owa/calendar/a/b/calendar.ics")
        XCTAssertNotNil(CalendarFeedConfig.normalizedURL("https://calendar.google.com/calendar/ical/a%40b.com/private-x/basic.ics"))
        for bad in ["http://example.com/a.ics", "file:///etc/passwd", "https://user:pw@example.com/a.ics", "https://", "", "https://a b.com/x"] {
            XCTAssertNil(CalendarFeedConfig.normalizedURL(bad), bad)
        }
        let google = URL(string: "https://calendar.google.com/calendar/ical/ash%40example.com/private-secret/basic.ics")!
        XCTAssertEqual(CalendarFeedConfig.suggestedName(for: google), "Google · ash@example.com")
        XCTAssertFalse(CalendarFeedConfig.suggestedName(for: google).contains("secret"))
        XCTAssertEqual(CalendarFeedConfig.suggestedName(for: URL(string: "https://outlook.office365.com/owa/calendar/x/y/calendar.ics")!), "Outlook calendar")
    }

    func testReminderDoesNotRepeatWhenTheOtherSourceWinsDeduplication() {
        var scheduler = CalendarAlarmScheduler()
        let synced = event("ek", calendar: "apple")
        // Apple Calendar copy arrives first and is delivered.
        XCTAssertEqual(scheduler.due(events: CalendarAlarmEvent.deduplicated([synced]), settings: settings, now: now).count, 1)
        // The ICS copy with a join link arrives later and wins deduplication.
        let feed = CalendarAlarmEvent(id: "ics", calendarID: "google", title: "Synthetic meeting", start: synced.start, end: synced.end,
                                      joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        let merged = CalendarAlarmEvent.deduplicated([synced, feed])
        XCTAssertEqual(merged.first?.calendarID, "google")
        XCTAssertTrue(scheduler.due(events: merged, settings: settings, now: now.addingTimeInterval(1)).isEmpty)
        // The start reminder still fires exactly once, and survives the feed disappearing.
        XCTAssertEqual(scheduler.due(events: merged, settings: settings, now: now.addingTimeInterval(300)).count, 1)
        XCTAssertTrue(scheduler.due(events: [synced], settings: settings, now: now.addingTimeInterval(301)).isEmpty)
    }

    func testFeedEventsCarryJoinLinksAndDuplicatesCollapse() {
        let start = now.addingTimeInterval(300)
        let feed = FeedEvent(uid: "u1", title: "Standup", start: start, end: start.addingTimeInterval(900), occurrence: start,
                             isAllDay: false, isCancelled: false, isDeclined: false, location: "Room 4",
                             notes: "Join https://us02web.zoom.us/j/123?pwd=x", url: nil, conferenceURL: nil)
        let converted = CalendarAlarmEvent.fromFeed([feed], calendarID: "feed:1")
        XCTAssertEqual(converted.first?.joinURL?.absoluteString, "https://us02web.zoom.us/j/123?pwd=x")
        XCTAssertEqual(converted.first?.calendarID, "feed:1")
        let synced = CalendarAlarmEvent(id: "ek", calendarID: "google", title: "standup", start: start, end: start.addingTimeInterval(900))
        let merged = CalendarAlarmEvent.deduplicated([synced] + converted + [event("other", start: 900, end: 1800)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertNotNil(merged.first?.joinURL)
    }

    func testRecurringOccurrencesGetSeparateAlarms() {
        let first = event(), second = event(start: 86400 + 300, end: 86400 + 3900)
        var scheduler = CalendarAlarmScheduler()
        XCTAssertEqual(scheduler.due(events: [first, second], settings: settings, now: now), [first])
        XCTAssertEqual(scheduler.due(events: [first, second], settings: settings, now: now.addingTimeInterval(86400)), [second])
    }

    func testMovedRecurringOccurrenceDoesNotRepeatDeliveredAlarm() {
        var scheduler = CalendarAlarmScheduler()
        _ = scheduler.due(events: [event(occurrence: 300)], settings: settings, now: now)
        let moved = event(start: 900, end: 4500, occurrence: 300)
        XCTAssertTrue(scheduler.due(events: [moved], settings: settings, now: now.addingTimeInterval(600)).isEmpty)
    }

    func testReceiptsSurviveRestartWithoutStoringTitles() throws {
        var scheduler = CalendarAlarmScheduler()
        _ = scheduler.due(events: [event()], settings: settings, now: now)
        let data = try JSONEncoder().encode(scheduler.receipts)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Synthetic meeting"))
        var restored = CalendarAlarmScheduler(receipts: try JSONDecoder().decode([CalendarAlarmReceipt].self, from: data))
        XCTAssertTrue(restored.due(events: [event()], settings: settings, now: now.addingTimeInterval(1)).isEmpty)
        var changedLead = settings; changedLead.leadMinutes = 0
        XCTAssertTrue(restored.due(events: [event()], settings: changedLead, now: now.addingTimeInterval(300)).isEmpty)
    }

    func testSnoozeSurvivesRestartAndFiresOnceAfterFiveMinutes() throws {
        var scheduler = CalendarAlarmScheduler()
        _ = scheduler.due(events: [event()], settings: settings, now: now)
        scheduler.snooze(event(), now: now)
        let data = try JSONEncoder().encode(scheduler.receipts)
        scheduler = CalendarAlarmScheduler(receipts: try JSONDecoder().decode([CalendarAlarmReceipt].self, from: data))
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(299)).isEmpty)
        XCTAssertEqual(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(300)), [event()])
        XCTAssertTrue(scheduler.due(events: [event()], settings: settings, now: now.addingTimeInterval(301)).isEmpty)
    }

    func testSnoozeDoesNotResurrectRemovedOrCancelledEvents() {
        var scheduler = CalendarAlarmScheduler()
        _ = scheduler.due(events: [event()], settings: settings, now: now)
        scheduler.snooze(event(), now: now)
        XCTAssertTrue(scheduler.due(events: [], settings: settings, now: now.addingTimeInterval(300)).isEmpty)
        XCTAssertTrue(scheduler.due(events: [event(cancelled: true)], settings: settings, now: now.addingTimeInterval(300)).isEmpty)
        var disabled = settings; disabled.enabled = false
        XCTAssertTrue(scheduler.due(events: [event()], settings: disabled, now: now.addingTimeInterval(300)).isEmpty)
    }

    func testAtStartAlarmAndInvalidLeadPreference() {
        var scheduler = CalendarAlarmScheduler(), atStart = settings
        atStart.leadMinutes = 0
        XCTAssertTrue(scheduler.due(events: [event()], settings: atStart, now: now).isEmpty)
        XCTAssertEqual(scheduler.due(events: [event()], settings: atStart, now: now.addingTimeInterval(300)), [event()])
        atStart.leadMinutes = -999
        XCTAssertEqual(atStart.leadInterval, 300)
    }

    func testDSTFallbackUsesAbsoluteTime() {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2026-11-01T01:30:00-05:00")!
        let fire = formatter.date(from: "2026-11-01T01:25:00-05:00")!
        let earlySameWallClock = formatter.date(from: "2026-11-01T01:25:00-04:00")!
        let meeting = CalendarAlarmEvent(id: "dst", calendarID: "apple", title: "Clock change", start: start, end: start.addingTimeInterval(3600))
        var scheduler = CalendarAlarmScheduler()
        XCTAssertTrue(scheduler.due(events: [meeting], settings: settings, now: earlySameWallClock).isEmpty)
        XCTAssertEqual(scheduler.due(events: [meeting], settings: settings, now: fire), [meeting])
    }

    func testReceiptRetentionIsBounded() {
        var scheduler = CalendarAlarmScheduler(receipts: [.init(key: "old", expires: now.addingTimeInterval(-1))])
        _ = scheduler.due(events: [], settings: settings, now: now)
        XCTAssertTrue(scheduler.receipts.isEmpty)
    }
}
