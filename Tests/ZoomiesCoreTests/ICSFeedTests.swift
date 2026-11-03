import XCTest
@testable import ZoomiesCore

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func calendarText(_ blocks: [String]...) -> String {
    (["BEGIN:VCALENDAR"] + blocks.flatMap { $0 } + ["END:VCALENDAR"]).joined(separator: "\n")
}

private func vevent(_ lines: String...) -> [String] {
    ["BEGIN:VEVENT"] + lines + ["END:VEVENT"]
}

final class ICSFeedTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let wide = DateInterval(start: utcDate(2026, 1, 1), end: utcDate(2027, 12, 31))

    private func parse(_ text: String, window: DateInterval? = nil, owner: String? = nil) throws -> [FeedEvent] {
        try ICSFeed.events(from: text, window: window ?? wide, ownerEmail: owner, defaultTimeZone: newYork)
    }

    func testFoldedTextUnescapesCommasAndNewlines() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DTEND:20261103T153000Z",
                                       "SUMMARY:Plan\\, rev", " iew\\nNext"))
        XCTAssertEqual(try parse(text).first?.title, "Plan, review\nNext")
    }

    func testCRLFInputParses() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DTEND:20261103T153000Z", "SUMMARY:Crlf"))
            .replacingOccurrences(of: "\n", with: "\r\n")
        let events = try parse(text)
        XCTAssertEqual(events.map(\.title), ["Crlf"])
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 15))
    }

    func testUTCTimes() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DTEND:20261103T153000Z")))
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 15))
        XCTAssertEqual(events.first?.end, utcDate(2026, 11, 3, 15, 30))
    }

    func testIANATZIDTime() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART;TZID=America/Los_Angeles:20261103T090000")))
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 17))
    }

    func testWindowsTZIDTime() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART;TZID=\"Eastern Standard Time\":20261103T100000")))
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 15))
    }

    func testFloatingTimeUsesDefaultZone() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART:20261103T100000")))
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 15))
    }

    func testDateOnlyEventIsAllDayAtDefaultZoneMidnight() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART;VALUE=DATE:20261103")))
        XCTAssertEqual(events.first?.isAllDay, true)
        XCTAssertEqual(events.first?.start, utcDate(2026, 11, 3, 5))
        XCTAssertEqual(events.first?.end, utcDate(2026, 11, 4, 5))
    }

    func testDurationSetsEnd() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DURATION:PT1H30M")))
        XCTAssertEqual(events.first?.end, events.first?.start.addingTimeInterval(5400))
    }

    func testCancelledStatus() throws {
        let events = try parse(calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "STATUS:CANCELLED")))
        XCTAssertEqual(events.first?.isCancelled, true)
    }

    func testDeclinedOnlyForOwnerAddress() throws {
        let declinedByOwner = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z",
                                                  "ATTENDEE;PARTSTAT=DECLINED:mailto:ASH@example.com"))
        XCTAssertEqual(try parse(declinedByOwner, owner: "ash@example.com").first?.isDeclined, true)
        XCTAssertEqual(try parse(declinedByOwner).first?.isDeclined, false)
        let declinedByOther = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z",
                                                  "ATTENDEE;PARTSTAT=DECLINED:mailto:other@example.com"))
        XCTAssertEqual(try parse(declinedByOther, owner: "ash@example.com").first?.isDeclined, false)
    }

    func testWeeklyByDayAcrossDST() throws {
        let text = calendarText(vevent("UID:a", "DTSTART;TZID=America/New_York:20261026T100000",
                                       "DTEND;TZID=America/New_York:20261026T110000",
                                       "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"))
        let window = DateInterval(start: utcDate(2026, 10, 26), end: utcDate(2026, 11, 7))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 10, 26, 14), utcDate(2026, 10, 28, 14), utcDate(2026, 10, 30, 14),
            utcDate(2026, 11, 2, 15), utcDate(2026, 11, 4, 15), utcDate(2026, 11, 6, 15),
        ])
    }

    func testExdateRemovesInstance() throws {
        let text = calendarText(vevent("UID:a", "DTSTART;TZID=America/New_York:20261026T100000",
                                       "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR",
                                       "EXDATE;TZID=America/New_York:20261028T100000"))
        let window = DateInterval(start: utcDate(2026, 10, 26), end: utcDate(2026, 11, 7))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 10, 26, 14), utcDate(2026, 10, 30, 14),
            utcDate(2026, 11, 2, 15), utcDate(2026, 11, 4, 15), utcDate(2026, 11, 6, 15),
        ])
    }

    func testOverrideReplacesInstance() throws {
        let text = calendarText(vevent("UID:series", "DTSTART;TZID=America/New_York:20261026T100000",
                                       "DTEND;TZID=America/New_York:20261026T110000",
                                       "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR", "SUMMARY:Standup"),
                                vevent("UID:series", "RECURRENCE-ID;TZID=America/New_York:20261030T100000",
                                       "DTSTART;TZID=America/New_York:20261030T130000",
                                       "DTEND;TZID=America/New_York:20261030T140000", "SUMMARY:Moved"))
        let window = DateInterval(start: utcDate(2026, 10, 26), end: utcDate(2026, 11, 7))
        let events = try parse(text, window: window)
        XCTAssertEqual(events.count, 6)
        XCTAssertFalse(events.contains { $0.start == utcDate(2026, 10, 30, 14) })
        let moved = events.first { $0.title == "Moved" }
        XCTAssertEqual(moved?.start, utcDate(2026, 10, 30, 17))
        XCTAssertEqual(moved?.occurrence, utcDate(2026, 10, 30, 14))
    }

    func testCancelledOverride() throws {
        let text = calendarText(vevent("UID:series", "DTSTART;TZID=America/New_York:20261026T100000",
                                       "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"),
                                vevent("UID:series", "RECURRENCE-ID;TZID=America/New_York:20261030T100000",
                                       "DTSTART;TZID=America/New_York:20261030T100000", "STATUS:CANCELLED"))
        let window = DateInterval(start: utcDate(2026, 10, 30), end: utcDate(2026, 10, 31))
        let events = try parse(text, window: window)
        XCTAssertEqual(events.map(\.isCancelled), [true])
    }

    func testCountIncludesInstancesBeforeWindow() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261101T090000Z", "RRULE:FREQ=DAILY;COUNT=3"))
        let window = DateInterval(start: utcDate(2026, 11, 2, 12), end: utcDate(2026, 11, 10))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [utcDate(2026, 11, 3, 9)])
    }

    func testUntilIsInclusive() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261101T090000Z",
                                       "RRULE:FREQ=DAILY;UNTIL=20261104T235959Z"))
        XCTAssertEqual(try parse(text).count, 4)
    }

    func testBiweeklyWithoutByDay() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "RRULE:FREQ=WEEKLY;INTERVAL=2"))
        let window = DateInterval(start: utcDate(2026, 11, 3), end: utcDate(2026, 12, 8))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 11, 3, 15), utcDate(2026, 11, 17, 15), utcDate(2026, 12, 1, 15),
        ])
    }

    func testMonthlyFirstTuesday() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20260901T140000Z", "RRULE:FREQ=MONTHLY;BYDAY=1TU"))
        let window = DateInterval(start: utcDate(2026, 9, 1), end: utcDate(2026, 12, 31))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 9, 1, 14), utcDate(2026, 10, 6, 14), utcDate(2026, 11, 3, 14), utcDate(2026, 12, 1, 14),
        ])
    }

    func testMonthlyLastFriday() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261030T140000Z", "RRULE:FREQ=MONTHLY;BYDAY=-1FR"))
        let window = DateInterval(start: utcDate(2026, 10, 30), end: utcDate(2026, 12, 31))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 10, 30, 14), utcDate(2026, 11, 27, 14), utcDate(2026, 12, 25, 14),
        ])
    }

    func testMonthlyByMonthDay() throws {
        let text = calendarText(vevent("UID:a", "DTSTART;TZID=America/New_York:20261115T100000",
                                       "RRULE:FREQ=MONTHLY;BYMONTHDAY=15"))
        let window = DateInterval(start: utcDate(2026, 11, 1), end: utcDate(2027, 1, 31))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [
            utcDate(2026, 11, 15, 15), utcDate(2026, 12, 15, 15), utcDate(2027, 1, 15, 15),
        ])
    }

    func testWindowOverlapRules() throws {
        let text = calendarText(
            vevent("UID:ended", "DTSTART:20261103T090000Z", "DTEND:20261103T100000Z"),
            vevent("UID:open", "DTSTART:20261103T093000Z", "DTEND:20261103T103000Z"))
        let window = DateInterval(start: utcDate(2026, 11, 3, 10), end: utcDate(2026, 11, 3, 12))
        XCTAssertEqual(try parse(text, window: window).map(\.uid), ["open"])
    }

    func testAlarmDescriptionDoesNotReplaceEventDescription() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DESCRIPTION:Event notes",
                                       "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:Alarm text", "END:VALARM"))
        XCTAssertEqual(try parse(text).first?.notes, "Event notes")
    }

    func testConferenceURLPriority() throws {
        let text = calendarText(
            vevent("UID:google", "DTSTART:20261103T150000Z", "X-GOOGLE-CONFERENCE:https://meet.example/g"),
            vevent("UID:teams", "DTSTART:20261103T150000Z",
                   "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.example/t"))
        let byUID = Dictionary(uniqueKeysWithValues: try parse(text).map { ($0.uid, $0.conferenceURL) })
        XCTAssertEqual(byUID["google"], "https://meet.example/g")
        XCTAssertEqual(byUID["teams"], "https://teams.example/t")
    }

    func testOwnerEmailFromGoogleFeedURL() throws {
        let google = URL(string: "https://calendar.google.com/calendar/ical/ash%40example.com/private-abc/basic.ics")!
        XCTAssertEqual(ICSFeed.ownerEmail(fromFeedURL: google), "ash@example.com")
        let outlook = URL(string: "https://outlook.live.com/owa/calendar/abc/calendar.ics")!
        XCTAssertNil(ICSFeed.ownerEmail(fromFeedURL: outlook))
    }

    func testMissingCalendarThrowsAndEventWithoutStartIsSkipped() throws {
        XCTAssertThrowsError(try parse("BEGIN:VEVENT\nUID:a\nDTSTART:20261103T150000Z\nEND:VEVENT"))
        let text = calendarText(vevent("UID:nostart", "SUMMARY:No start"),
                                vevent("UID:ok", "DTSTART:20261103T150000Z"))
        XCTAssertEqual(try parse(text).map(\.uid), ["ok"])
    }

    func testUnsupportedFrequencyIsNonRecurring() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "RRULE:FREQ=HOURLY"))
        XCTAssertEqual(try parse(text).map(\.start), [utcDate(2026, 11, 3, 15)])
    }

    func testHostileDurationAndNumbersDoNotTrap() throws {
        let huge = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DURATION:P2000000000000000000W"))
        XCTAssertEqual(try parse(huge).count, 1)
        let clamped = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "DURATION:P1000D"))
        XCTAssertEqual(try parse(clamped).first?.end, utcDate(2026, 11, 3, 15).addingTimeInterval(400 * 86_400))
        let interval = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z",
                                           "RRULE:FREQ=DAILY;INTERVAL=999999999999999999"))
        XCTAssertEqual(try parse(interval).count, 1)
        let count = calendarText(vevent("UID:a", "DTSTART:20261103T150000Z", "RRULE:FREQ=DAILY;COUNT=99999999999"))
        XCTAssertGreaterThanOrEqual(try parse(count).count, 1)
    }

    func testDailySeriesStartedLongAgoStillProducesToday() throws {
        let text = calendarText(vevent("UID:old", "DTSTART:20060101T150000Z", "RRULE:FREQ=DAILY"))
        let window = DateInterval(start: utcDate(2026, 11, 3), end: utcDate(2026, 11, 4))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [utcDate(2026, 11, 3, 15)])
    }

    func testCountOneReturnsOnlyDTSTART() throws {
        let daily = calendarText(vevent("UID:a", "DTSTART:20261102T150000Z", "RRULE:FREQ=DAILY;COUNT=1"))
        XCTAssertEqual(try parse(daily).map(\.start), [utcDate(2026, 11, 2, 15)])
        let weekly = calendarText(vevent("UID:b", "DTSTART:20261102T150000Z",
                                         "RRULE:FREQ=WEEKLY;COUNT=1;BYDAY=MO,TU"))
        XCTAssertEqual(try parse(weekly).map(\.start), [utcDate(2026, 11, 2, 15)])
    }

    func testCountIncludesDTSTARTInWeeklyByDay() throws {
        let text = calendarText(vevent("UID:a", "DTSTART:20261102T150000Z",
                                       "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO,WE"))
        XCTAssertEqual(try parse(text).map(\.start), [
            utcDate(2026, 11, 2, 15), utcDate(2026, 11, 4, 15), utcDate(2026, 11, 9, 15),
        ])
    }

    func testSpringForwardGapShiftsForward() throws {
        let text = calendarText(vevent("UID:a", "DTSTART;TZID=America/New_York:20260301T023000",
                                       "RRULE:FREQ=DAILY"))
        let window = DateInterval(start: utcDate(2026, 3, 8), end: utcDate(2026, 3, 9))
        XCTAssertEqual(try parse(text, window: window).map(\.start), [utcDate(2026, 3, 8, 7, 30)])
    }

    func testTimingWithManyMasters() throws {
        var blocks: [[String]] = []
        for index in 0..<300 {
            blocks.append(vevent("UID:w\(index)", "DTSTART:20161107T150000Z",
                                 "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"))
            blocks.append(vevent("UID:d\(index)", "DTSTART:20160101T150000Z", "RRULE:FREQ=DAILY"))
        }
        let text = calendarText(blocks.flatMap { $0 })
        let window = DateInterval(start: utcDate(2026, 11, 1, 12), end: utcDate(2026, 11, 4, 12))
        let started = Date()
        let events = try parse(text, window: window)
        let elapsed = Date().timeIntervalSince(started)
        // Daily masters hit Nov 1, 2, 3. Weekly masters hit Mon Nov 2 and Tue Nov 3.
        XCTAssertEqual(events.count, 300 * 3 + 300 * 2)
        XCTAssertLessThan(elapsed, 2.0)
    }
}
