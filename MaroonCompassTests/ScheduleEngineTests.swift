import XCTest
@testable import MaroonCompass

final class ScheduleEngineTests: XCTestCase {
    private let engine = ScheduleEngine(
        term: ScheduleSeed.term,
        courses: ScheduleSeed.courses,
        patterns: ScheduleSeed.patterns,
        oneTimeEvents: ScheduleSeed.oneTimeEvents,
        exceptions: ScheduleSeed.exceptions
    )

    func testSeedCountsAndCredits() {
        XCTAssertEqual(engine.courses.count, 6)
        XCTAssertEqual(engine.patterns.count, 9)
        XCTAssertEqual(engine.oneTimeEvents.count, 3)
        XCTAssertEqual(engine.courses.reduce(0) { $0 + $1.credits }, 13)
    }

    func testEmbeddedScheduleIncludesVerifiedPDFDetails() throws {
        let chem = try XCTUnwrap(engine.patterns.first { $0.courseID == "CHEM-107-504" })
        XCTAssertEqual(chem.sourceLocationText, "ILCB · 113")
        XCTAssertEqual(chem.sourceNotes, "Instructor: Sungyub Han")

        let mathLocations = Set(engine.patterns
            .filter { $0.courseID == "MATH-151-531" }
            .compactMap(\.sourceLocationText))
        XCTAssertEqual(mathLocations, ["HELD · 100", "BLOC · 123"])
        XCTAssertTrue(engine.oneTimeEvents.allSatisfy { $0.sourceLocationText == "HECC · 203" })
    }

    func testChemDoesNotAppearOnSemesterAnchorMonday() throws {
        let monday = try XCTUnwrap(engine.date("2026-08-24"))
        let codes = engine.occurrences(on: monday).map(\.course.code)
        XCTAssertFalse(codes.contains("CHEM 107"))
        XCTAssertEqual(codes, ["POLS 207", "MATH 151", "FYEX 101", "ENGR 102", "ENGR 102"])
    }

    func testChemAppearsTuesdayAndThursday() throws {
        let tuesday = try XCTUnwrap(engine.date("2026-08-25"))
        let thursday = try XCTUnwrap(engine.date("2026-08-27"))
        XCTAssertTrue(engine.occurrences(on: tuesday).contains { $0.course.code == "CHEM 107" })
        XCTAssertTrue(engine.occurrences(on: thursday).contains { $0.course.code == "CHEM 107" })
    }

    func testLaborDayAndThanksgivingSuppressClasses() throws {
        for day in ["2026-09-07", "2026-11-25", "2026-11-26", "2026-11-27"] {
            XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date(day))).isEmpty, day)
        }
    }

    func testRedefinedDayUsesFridayPattern() throws {
        let redefined = try XCTUnwrap(engine.date("2026-12-01"))
        let meetings = engine.occurrences(on: redefined)
        XCTAssertEqual(meetings.map(\.course.code), ["POLS 207"])
        XCTAssertEqual(engine.calendar.component(.hour, from: try XCTUnwrap(meetings.first?.start)), 9)
        XCTAssertEqual(engine.calendar.component(.minute, from: try XCTUnwrap(meetings.first?.start)), 10)
    }

    func testNoRecurringClassesAfterLastClassDay() throws {
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-12-07"))).isEmpty)
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-12-10"))).isEmpty)
    }

    func testSpecialMeetingsAreOneTimeOnly() throws {
        let expectedDates = ["2026-09-17", "2026-10-22", "2026-11-19"]
        for day in expectedDates {
            let meetings = engine.occurrences(on: try XCTUnwrap(engine.date(day))).filter(\.isSpecial)
            XCTAssertEqual(meetings.count, 1, day)
            XCTAssertEqual(meetings.first?.title, "MATH 151 exam")
            XCTAssertEqual(meetings.first?.sourceMeetingID, engine.oneTimeEvents.first(where: { $0.date == day })?.id)
        }
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-09-24"))).filter(\.isSpecial).isEmpty)
    }

    func testCampusCivilTimeSurvivesDSTTransition() throws {
        let before = try XCTUnwrap(engine.date("2026-10-29"))
        let after = try XCTUnwrap(engine.date("2026-11-03"))
        let beforeChem = try XCTUnwrap(engine.occurrences(on: before).first { $0.course.code == "CHEM 107" })
        let afterChem = try XCTUnwrap(engine.occurrences(on: after).first { $0.course.code == "CHEM 107" })
        XCTAssertEqual(engine.calendar.component(.hour, from: beforeChem.start), 8)
        XCTAssertEqual(engine.calendar.component(.hour, from: afterChem.start), 8)
    }

    func testAdjacentMondayEngineeringMeetingsDoNotOverlap() throws {
        let monday = try XCTUnwrap(engine.date("2026-08-24"))
        let meetings = engine.occurrences(on: monday).filter { $0.course.code == "ENGR 102" }
        XCTAssertEqual(meetings.count, 2)
        XCTAssertLessThanOrEqual(try XCTUnwrap(meetings.first?.end), try XCTUnwrap(meetings.last?.start))
    }

    func testNextOccurrenceBeforeTermStart() throws {
        let now = try XCTUnwrap(engine.date("2026-08-18", hour: 12))
        let next = try XCTUnwrap(engine.nextOccurrence(after: now))
        XCTAssertEqual(next.course.code, "POLS 207")
        XCTAssertEqual(engine.dateString(for: next.start), "2026-08-24")
    }

    func testICSImportNormalizesHowdyAnchorAndPreservesOneTimeEvent() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//TAMU//Howdy//EN
        BEGIN:VEVENT
        UID:chem
        DTSTART;TZID=America/Chicago:20260824T080000
        DTEND;TZID=America/Chicago:20260824T091500
        RRULE:FREQ=WEEKLY;UNTIL=20261210T151500Z;BYDAY=TU,TH
        SUMMARY:CHEM-107-504
        END:VEVENT
        BEGIN:VEVENT
        UID:math-special
        DTSTART;TZID=America/Chicago:20260917T173000
        DTEND;TZID=America/Chicago:20260917T184500
        RRULE:FREQ=WEEKLY;UNTIL=20260917T234500Z;BYDAY=TH
        SUMMARY:MATH-151-531
        END:VEVENT
        END:VCALENDAR
        """

        let (bundle, report) = try ICSImportService().parse(data: Data(calendar.utf8), sourceName: "updated.ics")
        XCTAssertEqual(bundle.courses.count, 2)
        XCTAssertEqual(bundle.patterns.count, 1)
        XCTAssertEqual(bundle.patterns.first?.weekdays, [.tuesday, .thursday])
        XCTAssertEqual(bundle.oneTimeEvents.count, 1)
        XCTAssertEqual(bundle.oneTimeEvents.first?.date, "2026-09-17")
        XCTAssertEqual(report.normalizedAnchorCount, 1)
    }

    func testICSImportPreservesRecurrenceAdjustmentsAndSourceContext() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:adjusted-math
        DTSTART;TZID=America/Chicago:20260824T113000
        DTEND;TZID=America/Chicago:20260824T122000
        RRULE:FREQ=WEEKLY;UNTIL=20261203T182000Z;BYDAY=MO,WE
        EXDATE;TZID=America/Chicago:20260902T113000
        RDATE;TZID=America/Chicago:20260904T113000
        SUMMARY:MATH-151-531
        LOCATION:Confirmed room text
        DESCRIPTION:Bring laptop\\nWeekly notes
        X-HOWDY-SOURCE:registration
        END:VEVENT
        END:VCALENDAR
        """

        let (bundle, report) = try ICSImportService().parse(data: Data(calendar.utf8), sourceName: "adjusted.ics")
        let pattern = try XCTUnwrap(bundle.patterns.first)
        XCTAssertEqual(pattern.excludedDates, ["2026-09-02"])
        XCTAssertEqual(pattern.additionalDates, ["2026-09-04"])
        XCTAssertEqual(pattern.sourceLocationText, "Confirmed room text")
        XCTAssertEqual(pattern.sourceNotes, "Bring laptop\nWeekly notes")
        XCTAssertEqual(bundle.diagnosticProperties?["adjusted-math"]?["X-HOWDY-SOURCE"], "registration")
        XCTAssertTrue(report.notes.contains { $0.contains("EXDATE/RDATE") })

        let adjustedEngine = ScheduleEngine(
            term: ScheduleSeed.term,
            courses: bundle.courses,
            patterns: bundle.patterns,
            oneTimeEvents: bundle.oneTimeEvents,
            exceptions: ScheduleSeed.exceptions
        )
        XCTAssertTrue(adjustedEngine.occurrences(on: try XCTUnwrap(adjustedEngine.date("2026-09-02"))).isEmpty)
        XCTAssertEqual(adjustedEngine.occurrences(on: try XCTUnwrap(adjustedEngine.date("2026-09-04"))).map(\.course.code), ["MATH 151"])
    }

    func testICSUTCDateTimesConvertToCampusCivilTime() throws {
        let calendar = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:utc-event
        DTSTART:20260918T003000Z
        DTEND:20260918T014500Z
        SUMMARY:MATH-151-531
        END:VEVENT
        END:VCALENDAR
        """

        let (bundle, _) = try ICSImportService().parse(data: Data(calendar.utf8), sourceName: "utc.ics")
        let event = try XCTUnwrap(bundle.oneTimeEvents.first)
        XCTAssertEqual(event.date, "2026-09-17")
        XCTAssertEqual(event.startHour, 19)
        XCTAssertEqual(event.startMinute, 30)
    }
}
