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

    func testDefaultsArePrivateAndOptIn() {
        let value = CalendarAlarmSettings()
        XCTAssertFalse(value.enabled); XCTAssertTrue(value.calendarIDs.isEmpty); XCTAssertFalse(value.showEventTitles)
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

    func testWakeCatchesUpOnlyRecentAlarms() {
        var scheduler = CalendarAlarmScheduler()
        XCTAssertEqual(scheduler.due(events: [event("recent", start: 180), event("old", start: 179)], settings: settings, now: now).map(\.id), ["recent"])
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
