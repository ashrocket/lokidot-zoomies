import Foundation

/// Thrown when feed text is not an iCalendar document.
public struct ICSFeedError: LocalizedError {
    /// Human-readable reason the feed was rejected.
    public let message: String
    /// Same text as `message`, used by `LocalizedError`.
    public var errorDescription: String? { message }
}

/// One occurrence of a calendar event, with recurrence already expanded.
public struct FeedEvent: Equatable {
    /// UID shared by every occurrence of the series.
    public let uid: String
    /// SUMMARY text, empty when absent.
    public let title: String
    /// Start of this occurrence.
    public let start: Date
    /// End of this occurrence, never before `start`.
    public let end: Date
    /// RECURRENCE-ID instant for overrides, otherwise this occurrence's computed start.
    public let occurrence: Date
    /// True when the event has a date-only DTSTART.
    public let isAllDay: Bool
    /// True when STATUS is CANCELLED.
    public let isCancelled: Bool
    /// True when the owner's address declined the invitation.
    public let isDeclined: Bool
    /// LOCATION text, nil when empty or absent.
    public let location: String?
    /// DESCRIPTION text, nil when empty or absent.
    public let notes: String?
    /// URL property, nil when absent.
    public let url: String?
    /// Meeting link from the first conference property present.
    public let conferenceURL: String?
}

/// Parses iCalendar (ICS) feeds into event occurrences for a time window.
public enum ICSFeed {
    /// Returns every occurrence that overlaps `window`, sorted by start, then UID.
    /// - Parameters:
    ///   - text: ICS document with CRLF or LF line endings.
    ///   - window: Time range to return. The end is exclusive.
    ///   - ownerEmail: Address whose `PARTSTAT=DECLINED` marks an event declined. Nil never marks one declined.
    ///   - defaultTimeZone: Zone for floating times and all-day dates.
    /// - Throws: `ICSFeedError` if the text has no `BEGIN:VCALENDAR`.
    public static func events(from text: String, window: DateInterval, ownerEmail: String? = nil,
                              defaultTimeZone: TimeZone = .current) throws -> [FeedEvent] {
        let lines = contentLines(text)
        guard lines.contains(where: { $0.name == "BEGIN" && $0.value.uppercased() == "VCALENDAR" }) else {
            throw ICSFeedError(message: "Feed is not an iCalendar document (no BEGIN:VCALENDAR).")
        }
        let raws = eventBlocks(lines).compactMap {
            RawEvent(lines: $0, ownerEmail: ownerEmail, defaultZone: defaultTimeZone)
        }
        let masters = raws.filter { $0.recurrenceID == nil }
        let overrides = raws.filter { $0.recurrenceID != nil }
        let overridesByUID = Dictionary(grouping: overrides, by: \.uid)
        var result = masters.flatMap { $0.occurrences(overrides: overridesByUID[$0.uid] ?? [], window: window) }
        result += overrides.map { $0.event(at: $0.start.date, occurrence: $0.recurrenceID?.date ?? $0.start.date) }
        return result
            .filter { overlaps($0, window) }
            .sorted { $0.start == $1.start ? $0.uid < $1.uid : $0.start < $1.start }
    }

    /// Returns the account address from a Google Calendar private ICS URL, or nil for other hosts.
    /// - Parameter url: Feed URL, for example `https://calendar.google.com/calendar/ical/<email>/…`.
    public static func ownerEmail(fromFeedURL url: URL) -> String? {
        guard url.host?.lowercased() == "calendar.google.com" else { return nil }
        // `url.path` is already percent-decoded, so the address arrives as typed.
        let parts = url.path.split(separator: "/")
        guard parts.count >= 3, parts[0] == "calendar", parts[1] == "ical" else { return nil }
        let email = String(parts[2])
        return email.contains("@") ? email : nil
    }
}

// MARK: - Content lines

fileprivate struct ICSLine {
    let name: String
    let params: [String: String]
    let value: String
}

fileprivate struct ICSTime {
    let date: Date
    let zone: TimeZone
    let isDateOnly: Bool
}

fileprivate struct Rule {
    enum Frequency { case daily, weekly, monthly, yearly }
    typealias DaySpec = (weekday: Int, ordinal: Int?)
    let frequency: Frequency
    let interval: Int
    let count: Int?
    /// Exclusive upper bound from UNTIL.
    let untilLimit: Date?
    let days: [DaySpec]
    let monthDays: [Int]
    let months: [Int]
    /// Calendar weekday (1 = Sunday) that starts a week, from WKST.
    let weekStart: Int
}

extension ICSFeed {
    fileprivate static let eventCap = 20_000
    fileprivate static let periodCap = 100_000
    fileprivate static let utc = TimeZone(secondsFromGMT: 0) ?? .current

    fileprivate static let supportedRuleKeys: Set<String> = [
        "FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "WKST",
    ]
    fileprivate static let weekdayNumbers: [String: Int] = [
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7,
    ]
    /// Windows zone names that appear in TZID values, mapped to IANA identifiers.
    fileprivate static let windowsZones: [String: String] = [
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage",
        "Hawaiian Standard Time": "Pacific/Honolulu",
        "Atlantic Standard Time": "America/Halifax",
        "US Mountain Standard Time": "America/Phoenix",
        "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik",
        "UTC": "UTC",
        "W. Europe Standard Time": "Europe/Berlin",
        "Romance Standard Time": "Europe/Paris",
        "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw",
        "E. Europe Standard Time": "Europe/Bucharest",
        "FLE Standard Time": "Europe/Helsinki",
        "GTB Standard Time": "Europe/Athens",
        "Israel Standard Time": "Asia/Jerusalem",
        "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai",
        "Tokyo Standard Time": "Asia/Tokyo",
        "Korea Standard Time": "Asia/Seoul",
        "Singapore Standard Time": "Asia/Singapore",
        "AUS Eastern Standard Time": "Australia/Sydney",
        "E. Australia Standard Time": "Australia/Brisbane",
        "New Zealand Standard Time": "Pacific/Auckland",
        "SA Pacific Standard Time": "America/Bogota",
        "E. South America Standard Time": "America/Sao_Paulo",
        "Central Standard Time (Mexico)": "America/Mexico_City",
        "Arabian Standard Time": "Asia/Dubai",
        "Russian Standard Time": "Europe/Moscow",
    ]

    /// Splits text on `separator` wherever it sits outside double quotes.
    fileprivate static func splitOutsideQuotes(_ text: Substring, _ separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var start = text.startIndex
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                quoted.toggle()
            } else if character == separator && !quoted {
                parts.append(text[start..<index])
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }
        parts.append(text[start...])
        return parts
    }

    /// Normalizes line endings, joins folded lines, and parses each content line.
    fileprivate static func contentLines(_ text: String) -> [ICSLine] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var logical: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !logical.isEmpty {
                logical[logical.count - 1] += String(raw.dropFirst())
            } else {
                logical.append(String(raw))
            }
        }
        return logical.compactMap(parseLine)
    }

    fileprivate static func parseLine(_ line: String) -> ICSLine? {
        let pieces = splitOutsideQuotes(Substring(line), ":")
        guard pieces.count >= 2 else { return nil }
        let head = splitOutsideQuotes(pieces[0], ";")
        let name = head[0].uppercased()
        guard !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for piece in head.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let key = piece[..<equals].uppercased()
            params[key] = String(piece[piece.index(after: equals)...]).replacingOccurrences(of: "\"", with: "")
        }
        return ICSLine(name: name, params: params, value: pieces.dropFirst().joined(separator: ":"))
    }

    /// Returns the VEVENT content lines, skipping nested components such as VALARM.
    fileprivate static func eventBlocks(_ lines: [ICSLine]) -> [[ICSLine]] {
        var blocks: [[ICSLine]] = []
        var current: [ICSLine] = []
        var inEvent = false
        var nested = 0
        for line in lines {
            let kind = line.value.uppercased()
            if !inEvent {
                if line.name == "BEGIN", kind == "VEVENT", blocks.count < eventCap {
                    inEvent = true
                    current = []
                }
            } else if line.name == "BEGIN" {
                nested += 1
            } else if line.name == "END", nested > 0 {
                nested -= 1
            } else if line.name == "END", kind == "VEVENT" {
                blocks.append(current)
                inEvent = false
            } else if nested == 0 {
                current.append(line)
            }
        }
        return blocks
    }

    fileprivate static func unescape(_ value: String) -> String {
        var output = ""
        var escaping = false
        for character in value {
            if escaping {
                output.append(character == "n" || character == "N" ? "\n" : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                output.append(character)
            }
        }
        if escaping { output.append("\\") }
        return output
    }

    fileprivate static func mailtoAddress(_ value: String) -> String? {
        guard value.lowercased().hasPrefix("mailto:") else { return nil }
        return String(value.dropFirst(7))
    }

    fileprivate static func calendar(_ zone: TimeZone) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = zone
        return result
    }

    fileprivate static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    fileprivate static func zoneNamed(_ name: String?, fallback: TimeZone) -> TimeZone {
        guard let name, !name.isEmpty else { return fallback }
        return TimeZone(identifier: windowsZones[name] ?? name) ?? fallback
    }
}

// MARK: - Dates and durations

extension ICSFeed {
    /// Parses `yyyymmdd` (date) or `yyyymmddThhmmss` (time) as wall-clock time in `zone`.
    fileprivate static func localDate(_ text: String, time: Bool, zone: TimeZone) -> Date? {
        let characters = Array(text)
        guard characters.count == (time ? 15 : 8), !time || characters[8] == "T" else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            let part = String(characters[range])
            return isDigits(part) ? Int(part) : nil
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var parts = DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        if time {
            guard let hour = number(9..<11), let minute = number(11..<13), let second = number(13..<15),
                  hour < 24, minute < 60, second < 61 else { return nil }
            parts.hour = hour
            parts.minute = minute
            parts.second = second
        }
        return calendar(zone).date(from: parts)
    }

    /// Parses one DATE or DATE-TIME value. Date-only values use `defaultZone`; `Z` means UTC.
    fileprivate static func time(_ value: String, params: [String: String], defaultZone: TimeZone) -> ICSTime? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if params["VALUE"] == "DATE" || (text.count == 8 && isDigits(text)) {
            guard let date = localDate(text, time: false, zone: defaultZone) else { return nil }
            return ICSTime(date: date, zone: defaultZone, isDateOnly: true)
        }
        let isUTC = text.hasSuffix("Z")
        let zone = isUTC ? utc : zoneNamed(params["TZID"], fallback: defaultZone)
        guard let date = localDate(isUTC ? String(text.dropLast()) : text, time: true, zone: zone) else { return nil }
        return ICSTime(date: date, zone: zone, isDateOnly: false)
    }

    /// Parses a comma-separated list of date values, such as EXDATE or RDATE.
    fileprivate static func times(_ line: ICSLine, defaultZone: TimeZone) -> [ICSTime] {
        line.value.split(separator: ",").compactMap {
            time(String($0), params: line.params, defaultZone: defaultZone)
        }
    }

    /// Parses at most nine ASCII digits, so later arithmetic on the value cannot overflow.
    fileprivate static func boundedInt(_ text: String) -> Int? {
        guard text.count <= 9, isDigits(text) else { return nil }
        return Int(text)
    }

    /// Like `boundedInt`, with an optional leading sign.
    fileprivate static func signedInt(_ text: Substring) -> Int? {
        if let sign = text.first, sign == "-" || sign == "+" {
            return boundedInt(String(text.dropFirst())).map { sign == "-" ? -$0 : $0 }
        }
        return boundedInt(String(text))
    }

    /// Parses an ISO 8601 duration such as `PT1H30M`, `P1D`, or `P1W` into whole days and seconds.
    /// Each total is clamped to 400 days, so hostile input cannot produce an absurd event length.
    fileprivate static func durationParts(_ text: String) -> (days: Int, seconds: Int)? {
        let upper = text.uppercased()
        guard upper.hasPrefix("P") else { return nil }
        var days = 0
        var seconds = 0
        var number = ""
        var inTime = false
        var sawUnit = false
        for character in upper.dropFirst() {
            if character == "T" {
                inTime = true
            } else if character.isASCII && character.isNumber {
                number.append(character)
            } else {
                guard let amount = boundedInt(number) else { return nil }
                number = ""
                sawUnit = true
                switch (character, inTime) {
                case ("W", false): days += 7 * amount
                case ("D", false): days += amount
                case ("H", true): seconds += 3_600 * amount
                case ("M", true): seconds += 60 * amount
                case ("S", true): seconds += amount
                default: return nil
                }
            }
        }
        guard number.isEmpty, sawUnit else { return nil }
        return (min(days, 400), min(seconds, 400 * 86_400))
    }

    /// Length of an event from DTEND, else DURATION, else a one-day all-day span or zero.
    fileprivate static func length(of start: ICSTime, end: ICSTime?, duration: String?) -> TimeInterval {
        if let end { return max(0, end.date.timeIntervalSince(start.date)) }
        let cal = calendar(start.zone)
        if let duration, let parts = durationParts(duration) {
            let dayStop = cal.date(byAdding: .day, value: parts.days, to: start.date) ?? start.date
            return max(0, dayStop.addingTimeInterval(TimeInterval(parts.seconds)).timeIntervalSince(start.date))
        }
        if start.isDateOnly, let stop = cal.date(byAdding: .day, value: 1, to: start.date) {
            return stop.timeIntervalSince(start.date)
        }
        return 0
    }

    /// True when an EXDATE or RDATE value names the same instant, or the same calendar day for date-only values.
    /// True when an EXDATE or RDATE value names the same instant, or the same calendar day for date-only values.
    fileprivate static func matches(_ time: ICSTime, _ date: Date, zone: TimeZone) -> Bool {
        guard time.isDateOnly else { return time.date == date }
        return dayNumber(time.date, in: time.zone) == dayNumber(date, in: zone)
    }

    fileprivate static func dayNumber(_ date: Date, in zone: TimeZone) -> Int {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    fileprivate static func overlaps(_ event: FeedEvent, _ window: DateInterval) -> Bool {
        if event.start == event.end { return window.start <= event.start && event.start < window.end }
        return event.start < window.end && event.end > window.start
    }
}

// MARK: - RRULE

extension ICSFeed {
    /// Parses an RRULE value. Returns nil for unsupported frequencies or parts, which makes the event non-recurring.
    fileprivate static func parseRule(_ text: String, zone: TimeZone) -> Rule? {
        var parts: [String: String] = [:]
        for piece in text.uppercased().split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            parts[String(pair[0])] = String(pair[1])
        }
        guard Set(parts.keys).isSubset(of: supportedRuleKeys) else { return nil }
        let frequencies: [String: Rule.Frequency] = ["DAILY": .daily, "WEEKLY": .weekly, "MONTHLY": .monthly, "YEARLY": .yearly]
        guard let frequency = parts["FREQ"].flatMap({ frequencies[$0] }),
              let days = parseList(parts["BYDAY"], weekdayToken),
              let monthDays = parseList(parts["BYMONTHDAY"], monthDayToken),
              let months = parseList(parts["BYMONTH"], monthToken) else { return nil }
        if days.contains(where: { $0.ordinal != nil }) && frequency != .monthly { return nil }
        var interval = 1
        if let raw = parts["INTERVAL"] {
            guard let value = boundedInt(raw) else { return nil }
            interval = min(max(value, 1), 1_000)
        }
        var count: Int?
        if let raw = parts["COUNT"] {
            guard let value = boundedInt(raw), value >= 1 else { return nil }
            count = min(value, 100_000)
        }
        var weekStart = 2
        if let raw = parts["WKST"] {
            guard let value = weekdayNumbers[raw] else { return nil }
            weekStart = value
        }
        var untilLimit: Date?
        if let raw = parts["UNTIL"] {
            guard let limit = untilBound(raw, zone: zone) else { return nil }
            untilLimit = limit
        }
        return Rule(frequency: frequency, interval: interval, count: count, untilLimit: untilLimit,
                    days: days, monthDays: monthDays, months: months, weekStart: weekStart)
    }

    /// Returns the first instant that UNTIL excludes. Date-only UNTIL includes its whole day.
    fileprivate static func untilBound(_ raw: String, zone: TimeZone) -> Date? {
        if raw.count == 8 {
            guard let day = localDate(raw, time: false, zone: zone) else { return nil }
            return calendar(zone).date(byAdding: .day, value: 1, to: day)
        }
        let isUTC = raw.hasSuffix("Z")
        guard let instant = localDate(isUTC ? String(raw.dropLast()) : raw, time: true,
                                      zone: isUTC ? utc : zone) else { return nil }
        return instant.addingTimeInterval(1)
    }

    fileprivate static func parseList<T>(_ raw: String?, _ parse: (Substring) -> T?) -> [T]? {
        var values: [T] = []
        for token in (raw ?? "").split(separator: ",") {
            guard let value = parse(token) else { return nil }
            values.append(value)
        }
        return values
    }

    fileprivate static func weekdayToken(_ token: Substring) -> Rule.DaySpec? {
        guard token.count >= 2, let weekday = weekdayNumbers[String(token.suffix(2))] else { return nil }
        let prefix = token.dropLast(2)
        if prefix.isEmpty { return (weekday, nil) }
        guard let ordinal = signedInt(prefix), ordinal != 0, (-53...53).contains(ordinal) else { return nil }
        return (weekday, ordinal)
    }

    fileprivate static func monthDayToken(_ token: Substring) -> Int? {
        guard let day = signedInt(token), day != 0, (-31...31).contains(day) else { return nil }
        return day
    }

    fileprivate static func monthToken(_ token: Substring) -> Int? {
        guard let month = boundedInt(String(token)), (1...12).contains(month) else { return nil }
        return month
    }
}

// MARK: - Expansion

extension ICSFeed {
    /// Expands `rule` as instants that can overlap `window`. Without COUNT, leading periods that
    /// cannot overlap the window are skipped. With COUNT, every period is counted from DTSTART.
    /// DTSTART is always the first instance and counts toward COUNT.
    fileprivate static func expand(_ rule: Rule, start: Date, zone: TimeZone, window: DateInterval,
                                   length: TimeInterval) -> [Date] {
        let walker = Walker(rule: rule, calendar: calendar(zone), start: start)
        var index = rule.count == nil ? skippedPeriods(walker, window: window, length: length, interval: rule.interval) : 0
        var dates: [Date] = index == 0 ? [start] : []
        for _ in 0..<periodCap {
            if let count = rule.count, dates.count >= count { break }
            guard let anchor = walker.anchor(index), anchor < window.end else { break }
            for instant in walker.instances(in: index) {
                if instant >= window.end { return dates }
                if let limit = rule.untilLimit, instant >= limit { return dates }
                if let count = rule.count, dates.count >= count { return dates }
                dates.append(instant)
            }
            index += rule.interval
        }
        return dates
    }

    /// Number of leading periods, a multiple of `interval`, that end before the window can see an instance.
    /// One period of margin keeps a period that straddles the cutoff in the walk.
    fileprivate static func skippedPeriods(_ walker: Walker, window: DateInterval, length: TimeInterval, interval: Int) -> Int {
        let elapsed = walker.periodIndex(of: window.start.addingTimeInterval(-length))
        guard elapsed > 1 else { return 0 }
        return (elapsed - 1) / interval * interval
    }
}

/// Generates the instances of one rule period by period, starting from DTSTART's period.
fileprivate struct Walker {
    let rule: Rule
    let calendar: Calendar
    let start: Date
    /// Year, month, day, and weekday of DTSTART in the event zone.
    let origin: DateComponents
    let startDay: Date
    /// First day of the week that contains DTSTART, using WKST.
    let weekAnchor: Date
    /// Wall-clock time of DTSTART, in seconds after midnight.
    let seconds: Int
    /// Months a day must fall in. A yearly rule with no day selector defaults to DTSTART's month.
    let months: [Int]

    init(rule: Rule, calendar: Calendar, start: Date) {
        self.rule = rule
        self.calendar = calendar
        self.start = start
        let origin = calendar.dateComponents([.year, .month, .day, .weekday], from: start)
        self.origin = origin
        let day = calendar.startOfDay(for: start)
        self.startDay = day
        let offset = ((origin.weekday ?? 1) - rule.weekStart + 7) % 7
        self.weekAnchor = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        self.seconds = (time.hour ?? 0) * 3_600 + (time.minute ?? 0) * 60 + (time.second ?? 0)
        let defaultMonth = rule.frequency == .yearly && rule.days.isEmpty && rule.monthDays.isEmpty && rule.months.isEmpty
        self.months = defaultMonth ? [origin.month ?? 1] : rule.months
    }

    /// First day of period `index`. Period 0 contains DTSTART.
    func anchor(_ index: Int) -> Date? {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: index, to: startDay)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * index, to: weekAnchor)
        case .monthly:
            let month = (origin.year ?? 0) * 12 + (origin.month ?? 1) - 1 + index
            return calendar.date(from: DateComponents(year: month / 12, month: month % 12 + 1, day: 1))
        case .yearly:
            return calendar.date(from: DateComponents(year: (origin.year ?? 0) + index, month: 1, day: 1))
        }
    }

    /// Index of the period containing `date`, counted from DTSTART's period.
    func periodIndex(of date: Date) -> Int {
        switch rule.frequency {
        case .daily:
            return calendar.dateComponents([.day], from: startDay, to: date).day ?? 0
        case .weekly:
            return (calendar.dateComponents([.day], from: weekAnchor, to: date).day ?? 0) / 7
        case .monthly:
            let parts = calendar.dateComponents([.year, .month], from: date)
            return ((parts.year ?? 0) - (origin.year ?? 0)) * 12 + (parts.month ?? 0) - (origin.month ?? 0)
        case .yearly:
            return (calendar.dateComponents([.year], from: date).year ?? 0) - (origin.year ?? 0)
        }
    }

    /// Wall-clock instants of period `index` that fall after DTSTART, in order.
    func instances(in index: Int) -> [Date] {
        days(in: index).compactMap { wallInstant($0) }.filter { $0 > start }
    }

    /// Days of period `index` that pass the rule's filters, in order.
    private func days(in index: Int) -> [Date] {
        guard let first = anchor(index) else { return [] }
        let span: Int
        switch rule.frequency {
        case .daily: span = 1
        case .weekly: span = 7
        case .monthly: span = 31
        case .yearly: span = 366
        }
        let bounded = rule.frequency == .monthly || rule.frequency == .yearly
        let firstParts = calendar.dateComponents([.year, .month], from: first)
        var result: [Date] = []
        var day = first
        for _ in 0..<span {
            if bounded {
                let parts = calendar.dateComponents([.year, .month], from: day)
                let leftPeriod = parts.year != firstParts.year || (rule.frequency == .monthly && parts.month != firstParts.month)
                if leftPeriod { break }
            }
            if accepts(day) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// The instant at DTSTART's wall-clock time on `day`. A time skipped by a DST gap moves forward
    /// by the length of the gap, as RFC 5545 requires.
    private func wallInstant(_ day: Date) -> Date? {
        guard let instant = calendar.date(bySettingHour: seconds / 3_600, minute: seconds / 60 % 60,
                                          second: seconds % 60, of: day) else {
            return calendar.date(byAdding: .second, value: seconds, to: day)
        }
        let actual = calendar.dateComponents([.hour, .minute, .second], from: instant)
        let actualSeconds = (actual.hour ?? 0) * 3_600 + (actual.minute ?? 0) * 60 + (actual.second ?? 0)
        return actualSeconds > seconds ? instant.addingTimeInterval(TimeInterval(actualSeconds - seconds)) : instant
    }

    /// Whether `day` passes the BYMONTH, BYMONTHDAY, and BYDAY filters, or the DTSTART-based default.
    private func accepts(_ day: Date) -> Bool {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        let month = parts.month ?? 0, dayOfMonth = parts.day ?? 0, weekday = parts.weekday ?? 1
        if !months.isEmpty && !months.contains(month) { return false }
        if rule.monthDays.isEmpty && rule.days.isEmpty {
            switch rule.frequency {
            case .daily: return true
            case .weekly: return weekday == origin.weekday
            case .monthly, .yearly: return dayOfMonth == origin.day
            }
        }
        let length = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
        let dayOK = rule.monthDays.isEmpty || rule.monthDays.contains { $0 > 0 ? $0 == dayOfMonth : dayOfMonth == length + $0 + 1 }
        let weekdayOK = rule.days.isEmpty || rule.days.contains { matches($0, weekday: weekday, day: dayOfMonth, length: length) }
        return dayOK && weekdayOK
    }

    /// Matches a BYDAY entry. An ordinal counts from the start of the month (positive) or its end (negative).
    private func matches(_ spec: Rule.DaySpec, weekday: Int, day: Int, length: Int) -> Bool {
        guard spec.weekday == weekday else { return false }
        guard let ordinal = spec.ordinal else { return true }
        return ordinal > 0 ? (day - 1) / 7 + 1 == ordinal : (length - day) / 7 + 1 == -ordinal
    }
}

// MARK: - Event instances

fileprivate struct RawEvent {
    let uid: String
    let title: String
    let start: ICSTime
    let length: TimeInterval
    let rule: Rule?
    /// True when an RRULE is present but outside the supported subset. Only DTSTART is then emitted.
    let hasUnsupportedRule: Bool
    let rdates: [ICSTime]
    let exdates: [ICSTime]
    let recurrenceID: ICSTime?
    let isCancelled: Bool
    let isDeclined: Bool
    let location: String?
    let notes: String?
    let url: String?
    let conferenceURL: String?

    init?(lines: [ICSLine], ownerEmail: String?, defaultZone: TimeZone) {
        var props: [String: [ICSLine]] = [:]
        for line in lines { props[line.name, default: []].append(line) }
        guard let startLine = props["DTSTART"]?.first,
              let start = ICSFeed.time(startLine.value, params: startLine.params, defaultZone: defaultZone) else { return nil }
        func raw(_ name: String) -> String? {
            guard let value = props[name]?.first?.value, !value.isEmpty else { return nil }
            return value
        }
        func text(_ name: String) -> String? {
            guard let value = raw(name) else { return nil }
            let unescaped = ICSFeed.unescape(value)
            return unescaped.isEmpty ? nil : unescaped
        }
        func time(_ name: String) -> ICSTime? {
            guard let line = props[name]?.first else { return nil }
            return ICSFeed.time(line.value, params: line.params, defaultZone: defaultZone)
        }
        let rruleText = raw("RRULE")
        let parsedRule = rruleText.flatMap { ICSFeed.parseRule($0, zone: start.zone) }
        let owner = ownerEmail?.lowercased()
        let declined = owner != nil && (props["ATTENDEE"] ?? []).contains { line in
            line.params["PARTSTAT"]?.uppercased() == "DECLINED" && ICSFeed.mailtoAddress(line.value)?.lowercased() == owner
        }
        let conference = ["X-GOOGLE-CONFERENCE", "X-MICROSOFT-SKYPETEAMSMEETINGURL", "X-MICROSOFT-ONLINEMEETINGCONFLINK"]
            .lazy.compactMap { raw($0) }.first

        self.uid = raw("UID") ?? ""
        self.title = text("SUMMARY") ?? ""
        self.start = start
        self.length = ICSFeed.length(of: start, end: time("DTEND"), duration: raw("DURATION"))
        self.rule = parsedRule
        self.hasUnsupportedRule = rruleText != nil && parsedRule == nil
        self.rdates = (props["RDATE"] ?? []).flatMap { ICSFeed.times($0, defaultZone: defaultZone) }
        self.exdates = (props["EXDATE"] ?? []).flatMap { ICSFeed.times($0, defaultZone: defaultZone) }
        self.recurrenceID = time("RECURRENCE-ID")
        self.isCancelled = raw("STATUS")?.uppercased() == "CANCELLED"
        self.isDeclined = declined
        self.location = text("LOCATION")
        self.notes = text("DESCRIPTION")
        self.url = raw("URL")
        self.conferenceURL = conference
    }

    /// Start instants of this series within the window, after EXDATE and RDATE are applied.
    func starts(window: DateInterval) -> [Date] {
        if hasUnsupportedRule { return [start.date] }
        var dates = rule.map { ICSFeed.expand($0, start: start.date, zone: start.zone, window: window, length: length) } ?? [start.date]
        dates += rdates.map(\.date)
        return Set(dates)
            .filter { date in !exdates.contains { ICSFeed.matches($0, date, zone: start.zone) } }
            .sorted()
    }

    /// Expands the series, dropping instances replaced by an override with a matching RECURRENCE-ID.
    func occurrences(overrides: [RawEvent], window: DateInterval) -> [FeedEvent] {
        let replaced = overrides.compactMap(\.recurrenceID)
        return starts(window: window)
            .filter { date in !replaced.contains { ICSFeed.matches($0, date, zone: start.zone) } }
            .map { event(at: $0, occurrence: $0) }
    }

    func event(at instant: Date, occurrence: Date) -> FeedEvent {
        FeedEvent(uid: uid, title: title, start: instant, end: instant.addingTimeInterval(length),
                  occurrence: occurrence, isAllDay: start.isDateOnly, isCancelled: isCancelled,
                  isDeclined: isDeclined, location: location, notes: notes, url: url,
                  conferenceURL: conferenceURL)
    }
}
