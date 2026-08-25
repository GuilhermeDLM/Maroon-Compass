import Foundation

struct ScheduleEngine: Sendable {
    let term: Term
    let courses: [Course]
    let patterns: [MeetingPattern]
    let oneTimeEvents: [OneTimeEvent]
    let exceptions: [AcademicException]

    var campusTimeZone: TimeZone {
        TimeZone(identifier: term.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: -21_600) ?? .gmt
    }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = campusTimeZone
        value.firstWeekday = 2
        return value
    }

    func date(_ day: String, hour: Int = 12, minute: Int = 0) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            timeZone: campusTimeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: hour,
            minute: minute
        ))
    }

    func dateString(for value: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func occurrenceDate(on day: Date, hour: Int, minute: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func academicException(on day: Date) -> AcademicException? {
        let key = dateString(for: day)
        return exceptions.first { $0.date == key }
    }

    func occurrences(on day: Date) -> [ScheduleOccurrence] {
        guard let first = date(term.firstClassDate), let last = date(term.lastClassDate) else { return [] }
        let startOfDay = calendar.startOfDay(for: day)
        let firstDay = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: last)
        let key = dateString(for: day)

        var result: [ScheduleOccurrence] = []
        let exception = academicException(on: day)

        if startOfDay >= firstDay, startOfDay <= lastDay, exception?.kind != .noClass {
            let effectiveWeekday: Weekday?
            if exception?.kind == .redefinedFriday {
                effectiveWeekday = .friday
            } else {
                effectiveWeekday = Weekday(calendarWeekday: calendar.component(.weekday, from: day))
            }

            if let effectiveWeekday {
                for pattern in patterns where
                    !pattern.excludedDates.contains(key) &&
                    (pattern.weekdays.contains(effectiveWeekday) || pattern.additionalDates.contains(key)) {
                    guard
                        let course = courses.first(where: { $0.id == pattern.courseID }),
                        let start = occurrenceDate(on: day, hour: pattern.startHour, minute: pattern.startMinute),
                        let end = occurrenceDate(on: day, hour: pattern.endHour, minute: pattern.endMinute)
                    else { continue }

                    result.append(ScheduleOccurrence(
                        id: "\(pattern.id)-\(key)",
                        course: course,
                        start: start,
                        end: end,
                        title: course.title,
                        isSpecial: false,
                        sourceMeetingID: pattern.id
                    ))
                }
            }
        }

        for event in oneTimeEvents where event.date == key {
            guard
                let course = courses.first(where: { $0.id == event.courseID }),
                let start = occurrenceDate(on: day, hour: event.startHour, minute: event.startMinute),
                let end = occurrenceDate(on: day, hour: event.endHour, minute: event.endMinute)
            else { continue }

            result.append(ScheduleOccurrence(
                id: event.id,
                course: course,
                start: start,
                end: end,
                title: event.title,
                isSpecial: true,
                sourceMeetingID: event.id
            ))
        }

        return result.sorted { $0.start < $1.start }
    }

    func nextOccurrence(after now: Date, searchDays: Int = 150) -> ScheduleOccurrence? {
        for offset in 0...searchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let next = occurrences(on: day).first(where: { $0.end > now }) {
                return next
            }
        }
        return nil
    }

    func week(containing day: Date) -> [Date] {
        let start: Date
        if let interval = calendar.dateInterval(of: .weekOfYear, for: day) {
            start = interval.start
        } else {
            start = calendar.startOfDay(for: day)
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func freeGaps(on day: Date, dayStartHour: Int = 8, dayEndHour: Int = 20) -> [TimeGap] {
        guard
            let dayStart = occurrenceDate(on: day, hour: dayStartHour, minute: 0),
            let dayEnd = occurrenceDate(on: day, hour: dayEndHour, minute: 0)
        else { return [] }

        let meetings = occurrences(on: day)
        var cursor = dayStart
        var gaps: [TimeGap] = []

        for meeting in meetings {
            if meeting.start > cursor {
                gaps.append(TimeGap(start: cursor, end: meeting.start))
            }
            if meeting.end > cursor { cursor = meeting.end }
        }
        if cursor < dayEnd { gaps.append(TimeGap(start: cursor, end: dayEnd)) }
        return gaps.filter { $0.duration >= 30 * 60 }
    }

    func conflicts(on day: Date) -> [(ScheduleOccurrence, ScheduleOccurrence)] {
        let meetings = occurrences(on: day)
        guard meetings.count > 1 else { return [] }
        var result: [(ScheduleOccurrence, ScheduleOccurrence)] = []
        for leftIndex in 0..<(meetings.count - 1) {
            for rightIndex in (leftIndex + 1)..<meetings.count {
                let left = meetings[leftIndex]
                let right = meetings[rightIndex]
                if left.start < right.end && right.start < left.end {
                    result.append((left, right))
                }
            }
        }
        return result
    }
}
