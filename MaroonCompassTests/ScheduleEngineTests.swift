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
        XCTAssertEqual(engine.patterns.count, 8)
        XCTAssertEqual(engine.oneTimeEvents.count, 0)
        XCTAssertEqual(engine.courses.reduce(0) { $0 + $1.credits }, 12)
    }

    func testEmbeddedScheduleIncludesCompleteHowdyDetails() throws {
        let chem = try XCTUnwrap(engine.patterns.first { $0.courseID == "CHEM-107-504" })
        XCTAssertEqual(chem.sourceLocationText, "ILCB · 113")
        XCTAssertEqual(chem.sourceNotes, "Instructor: Han, Sungyub")

        let courses = Dictionary(uniqueKeysWithValues: engine.courses.map { ($0.id, $0) })
        XCTAssertEqual(courses["CHEM-107-504"]?.crn, "10535")
        XCTAssertEqual(courses["CHEM-117-541"]?.crn, "20335")
        XCTAssertEqual(courses["ENGR-102-505"]?.crn, "36091")
        XCTAssertEqual(courses["FYEX-101-563"]?.crn, "43150")
        XCTAssertEqual(courses["MATH-251-502"]?.crn, "11953")
        XCTAssertEqual(courses["POLS-207-510"]?.crn, "45754")
        XCTAssertTrue(engine.courses.allSatisfy {
            $0.status == "Enrolled" &&
            $0.instructionMode == "Traditional Face-to-Face (F2F)" &&
            !($0.instructor ?? "").isEmpty &&
            !$0.subject.isEmpty &&
            !$0.courseNumber.isEmpty
        })

        let math = try XCTUnwrap(engine.patterns.first { $0.courseID == "MATH-251-502" })
        XCTAssertEqual(math.weekdays, [.tuesday, .thursday])
        XCTAssertEqual(math.sourceLocationText, "BLOC · 169")
        XCTAssertEqual(courses["MATH-251-502"]?.instructor, "Yang, Yuxuan")
    }

    func testEverySuppliedMeetingMatchesHowdyRegistration() {
        let actual = Set(engine.patterns.map {
            "\($0.courseID)|\($0.weekdays.map(\.rawValue).joined(separator: ","))|\($0.startHour):\($0.startMinute)|\($0.endHour):\($0.endMinute)|\($0.sourceLocationText ?? "")"
        })
        let expected: Set<String> = [
            "CHEM-107-504|TU,TH|8:0|9:15|ILCB · 113",
            "CHEM-117-541|TU|11:10|14:0|ILSQ · E311",
            "ENGR-102-505|MO|17:10|18:0|ZACH · 353",
            "ENGR-102-505|MO|18:1|19:0|ZACH · 353",
            "ENGR-102-505|WE|17:10|19:0|ZACH · 353",
            "FYEX-101-563|WE|15:0|15:50|HECC · 202",
            "MATH-251-502|TU,TH|17:30|18:45|BLOC · 169",
            "POLS-207-510|TU,TH|14:20|15:35|BLOC · 102"
        ]
        XCTAssertEqual(actual, expected)

        let instructors = Dictionary(uniqueKeysWithValues: engine.courses.compactMap { course in
            course.instructor.map { (course.id, $0) }
        })
        XCTAssertEqual(instructors, [
            "CHEM-107-504": "Han, Sungyub",
            "CHEM-117-541": "Martinez, Zachary Michael",
            "ENGR-102-505": "Spears, Craig Michael",
            "FYEX-101-563": "Soles, Chandris Christina",
            "MATH-251-502": "Yang, Yuxuan",
            "POLS-207-510": "Lim, Phaik"
        ])
    }

    func testLegacyImportedCourseWithoutNewMetadataStillDecodes() throws {
        let data = Data(#"{"id":"TEST-100-001","code":"TEST 100","section":"001","title":"Legacy course","credits":1,"catalogSummary":"Legacy import","colorHex":"2B67B2","symbol":"book.closed.fill"}"#.utf8)
        let course = try JSONDecoder().decode(Course.self, from: data)
        XCTAssertEqual(course.displayCode, "TEST 100-001")
        XCTAssertNil(course.status)
        XCTAssertNil(course.crn)
        XCTAssertNil(course.instructionMode)
        XCTAssertNil(course.instructor)
    }

    func testChemDoesNotAppearOnSemesterAnchorMonday() throws {
        let monday = try XCTUnwrap(engine.date("2026-08-24"))
        let codes = engine.occurrences(on: monday).map(\.course.code)
        XCTAssertFalse(codes.contains("CHEM 107"))
        XCTAssertEqual(codes, ["ENGR 102", "ENGR 102"])
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
        XCTAssertTrue(engine.occurrences(on: redefined).isEmpty)
    }

    func testNoRecurringClassesAfterLastClassDay() throws {
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-12-07"))).isEmpty)
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-12-10"))).isEmpty)
    }

    func testUpdatedScheduleHasNoUnsuppliedSpecialMeetings() throws {
        XCTAssertTrue(engine.oneTimeEvents.isEmpty)
        XCTAssertFalse(engine.courses.contains { $0.code == "MATH 151" })
        XCTAssertTrue(engine.occurrences(on: try XCTUnwrap(engine.date("2026-09-17"))).allSatisfy { !$0.isSpecial })
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
        XCTAssertEqual(next.course.code, "ENGR 102")
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

    func testWeeklyPersonalBlockUsesSelectedDaysAndDateRange() throws {
        let plan = PersonalPlanEngine(calendar: engine.calendar)
        let lunch = PersonalBlock(
            title: "Lunch",
            category: .meal,
            recurrence: .weekly,
            weekdays: [.tuesday, .thursday],
            startDate: "2026-08-24",
            endDate: "2026-09-04",
            startHour: 12,
            startMinute: 0,
            endHour: 13,
            endMinute: 0
        )

        XCTAssertTrue(plan.occurrences(on: try XCTUnwrap(engine.date("2026-08-24")), blocks: [lunch]).isEmpty)
        XCTAssertEqual(plan.occurrences(on: try XCTUnwrap(engine.date("2026-08-25")), blocks: [lunch]).count, 1)
        XCTAssertTrue(plan.occurrences(on: try XCTUnwrap(engine.date("2026-09-08")), blocks: [lunch]).isEmpty)
    }

    func testOneTimePersonalBlockDoesNotRepeat() throws {
        let plan = PersonalPlanEngine(calendar: engine.calendar)
        let appointment = PersonalBlock(
            title: "Advisor meeting",
            category: .personal,
            recurrence: .once,
            weekdays: [],
            startDate: "2026-09-02",
            startHour: 13,
            startMinute: 30,
            endHour: 14,
            endMinute: 15
        )

        XCTAssertEqual(plan.occurrences(on: try XCTUnwrap(engine.date("2026-09-02")), blocks: [appointment]).count, 1)
        XCTAssertTrue(plan.occurrences(on: try XCTUnwrap(engine.date("2026-09-09")), blocks: [appointment]).isEmpty)
    }

    func testOvernightSleepAppearsOnBothSidesOfMidnight() throws {
        let plan = PersonalPlanEngine(calendar: engine.calendar)
        let sleep = PersonalBlock(
            title: "Sleep",
            category: .sleep,
            recurrence: .weekly,
            weekdays: [.monday, .tuesday],
            startDate: "2026-08-24",
            endDate: "2026-08-25",
            startHour: 23,
            startMinute: 0,
            endHour: 7,
            endMinute: 0
        )

        let tuesday = try XCTUnwrap(engine.date("2026-08-25"))
        let occurrences = plan.occurrences(on: tuesday, blocks: [sleep])
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertTrue(occurrences.contains(where: \.continuesFromPreviousDay))
        XCTAssertTrue(occurrences.contains(where: \.continuesIntoNextDay))
        XCTAssertEqual(sleep.durationMinutes, 8 * 60)
    }

    func testPersonalPlanReportsClassAndPersonalConflicts() throws {
        let plan = PersonalPlanEngine(calendar: engine.calendar)
        let monday = try XCTUnwrap(engine.date("2026-08-24"))
        let study = PersonalBlock(
            title: "Study ENGR 102",
            category: .study,
            recurrence: .once,
            weekdays: [],
            startDate: "2026-08-24",
            startHour: 17,
            startMinute: 30,
            endHour: 18,
            endMinute: 30
        )

        let conflicts = plan.conflicts(
            on: monday,
            classOccurrences: engine.occurrences(on: monday),
            blocks: [study]
        )
        XCTAssertTrue(conflicts.contains { conflict in
            Set([conflict.firstTitle, conflict.secondTitle]) == Set(["Study ENGR 102", "ENGR 102"])
        })
    }

    @MainActor
    func testPersonalBlockPersistsAndDeletesLocally() {
        let store = AppStore()
        let block = PersonalBlock(
            title: "Persistence test \(UUID().uuidString)",
            category: .other,
            recurrence: .once,
            weekdays: [],
            startDate: "2026-09-12",
            startHour: 10,
            startMinute: 0,
            endHour: 11,
            endMinute: 0
        )

        store.savePersonalBlock(block)
        XCTAssertTrue(AppStore().personalBlocks.contains(where: { $0.id == block.id }))

        store.deletePersonalBlock(block)
        XCTAssertFalse(AppStore().personalBlocks.contains(where: { $0.id == block.id }))
    }
}
