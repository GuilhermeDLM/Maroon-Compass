import EventKit
import Foundation

@MainActor
final class CalendarExportService {
    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard

    func export(
        course: Course,
        engine: ScheduleEngine,
        locationForOccurrence: (ScheduleOccurrence) -> CourseLocation?
    ) async throws -> CalendarExportReport {
        guard try await eventStore.requestWriteOnlyAccessToEvents() else {
            throw CalendarExportError.accessDenied
        }
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarExportError.noWritableCalendar
        }
        guard let firstDay = engine.date(engine.term.firstClassDate), let lastDay = engine.date(engine.term.lastClassDate) else {
            throw CalendarExportError.invalidTerm
        }

        var exported = defaults.dictionary(forKey: "calendarExportIdentifiers") as? [String: String] ?? [:]
        var added = 0
        var existing = 0
        var day = firstDay

        while day <= lastDay {
            for occurrence in engine.occurrences(on: day) where occurrence.course.id == course.id {
                if exported[occurrence.id] != nil {
                    existing += 1
                    continue
                }

                let event = EKEvent(eventStore: eventStore)
                event.calendar = targetCalendar
                event.title = occurrence.isSpecial ? occurrence.title : "\(course.code) · \(course.title)"
                event.startDate = occurrence.start
                event.endDate = occurrence.end
                event.timeZone = engine.campusTimeZone
                event.location = locationForOccurrence(occurrence).map { value in
                    [value.feature.name, value.room].compactMap { $0 }.joined(separator: " · ")
                }
                event.notes = "Maroon Compass · \(engine.term.name) · Source event \(occurrence.sourceMeetingID)"
                try eventStore.save(event, span: .thisEvent, commit: false)
                exported[occurrence.id] = event.eventIdentifier ?? occurrence.id
                added += 1
            }
            guard let nextDay = engine.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        if added > 0 { try eventStore.commit() }
        defaults.set(exported, forKey: "calendarExportIdentifiers")
        return CalendarExportReport(addedCount: added, existingCount: existing, calendarTitle: targetCalendar.title)
    }
}

enum CalendarExportError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case invalidTerm

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Calendar access was not granted. You can change this in iOS Settings."
        case .noWritableCalendar:
            "No writable calendar is available on this device."
        case .invalidTerm:
            "The semester dates could not be read."
        }
    }
}
