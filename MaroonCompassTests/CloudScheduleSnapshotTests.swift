import XCTest
@testable import MaroonCompass

final class CloudScheduleSnapshotTests: XCTestCase {
    /// Encodes as the app would upload, decodes as the server would return, and rebuilds.
    private func roundTrip(_ bundle: ImportedScheduleBundle, isEmbedded: Bool = false) throws -> (CloudScheduleSnapshot, ImportedScheduleBundle) {
        let snapshot = try CloudScheduleSnapshot(bundle: bundle, fallbackTerm: ScheduleSeed.term, isEmbedded: isEmbedded)
        let wire = try JSONDecoder().decode(CloudScheduleSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(wire, snapshot)
        return (snapshot, try wire.makeBundle(restoredAt: Date(timeIntervalSince1970: 2_000_000_000)))
    }

    private func occurrences(_ bundle: ImportedScheduleBundle) -> [String] {
        let term = bundle.term ?? ScheduleSeed.term
        let engine = ScheduleEngine(
            term: term, courses: bundle.courses, patterns: bundle.patterns,
            oneTimeEvents: bundle.oneTimeEvents, exceptions: ScheduleSeed.exceptions
        )
        guard var day = engine.date(term.firstClassDate), let last = engine.date(term.finalsEndDate ?? term.lastClassDate) else {
            return []
        }
        var result: [String] = []
        while day <= last {
            result += engine.occurrences(on: day).map { "\($0.id)|\($0.course.id)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.title)" }
            day = engine.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    func testEmbeddedHowdyScheduleRoundTripsWithoutLoss() throws {
        let (snapshot, restored) = try roundTrip(CloudFixtures.embeddedBundle, isEmbedded: true)
        XCTAssertNil(snapshot.semester.sourceImportedAt, "the bundled schedule has no import time")
        XCTAssertEqual(restored.term, ScheduleSeed.term)
        XCTAssertEqual(restored.courses, ScheduleSeed.courses, "CRNs, instructors, modes, colors, symbols, and IDs survive")
        XCTAssertEqual(restored.patterns, ScheduleSeed.patterns, "UNTIL text, notes, locations, and Howdy IDs survive")
        XCTAssertEqual(restored.oneTimeEvents, ScheduleSeed.oneTimeEvents)
        XCTAssertEqual(restored.sourceName, ScheduleSeed.sourceName)
        XCTAssertEqual(occurrences(restored), occurrences(CloudFixtures.embeddedBundle))
        XCTAssertFalse(occurrences(restored).isEmpty)
    }

    func testCalendarImportRoundTripKeepsExceptionsAndOneTimeEvents() throws {
        let (imported, _) = try ICSImportService().parse(data: Data(CloudFixtures.icsCalendar.utf8), sourceName: "howdy.ics")
        XCTAssertNotNil(imported.diagnosticProperties, "fixture includes a private diagnostic property")
        XCTAssertEqual(imported.oneTimeEvents.count, 1)
        XCTAssertFalse(imported.patterns[0].excludedDates.isEmpty)
        XCTAssertFalse(imported.patterns[0].additionalDates.isEmpty)

        let (snapshot, restored) = try roundTrip(imported)
        XCTAssertEqual(restored.courses, imported.courses)
        XCTAssertEqual(restored.patterns, imported.patterns, "EXDATE, RDATE, UNTIL, notes, and UIDs survive")
        XCTAssertEqual(restored.oneTimeEvents, imported.oneTimeEvents)
        XCTAssertEqual(restored.term, ScheduleSeed.term, "an import without a term is stored with the term the app used")
        XCTAssertNil(restored.diagnosticProperties, "private .ics diagnostics are never uploaded")
        XCTAssertEqual(CloudFormat.parseTimestamp(snapshot.semester.sourceImportedAt ?? "")?.timeIntervalSince1970 ?? 0,
                       (imported.importedAt.timeIntervalSince1970 * 1_000).rounded(.down) / 1_000, accuracy: 0.000_5)
        XCTAssertEqual(occurrences(restored), occurrences(imported))
    }

    func testReviewedPhotoImportRoundTripsThroughDraftConfirmation() throws {
        var draft = ScheduleDraft(termName: "Spring 2027", firstClassDate: "2027-01-19", lastClassDate: "2027-05-04")
        var course = ScheduleDraftCourse()
        course.code = "ENGR 102"
        course.title = "Engineering Lab I"
        course.section = "505"
        course.meetings = [
            ScheduleDraftMeeting(kind: .lecture, weekdays: [.monday, .wednesday], startTime: "17:10", endTime: "18:00", buildingCode: "zach", room: "353"),
            ScheduleDraftMeeting(kind: .lab, weekdays: [.friday], startTime: "09:10", endTime: "11:00", buildingCode: "", room: "")
        ]
        draft.courses = [course]
        let confirmed = try draft.confirmedBundle(sourceName: "Reviewed photo import")

        let (snapshot, restored) = try roundTrip(confirmed)
        XCTAssertEqual(snapshot.meetings.map(\.meetingType), ["lecture", "lab"])
        XCTAssertEqual(restored.courses, confirmed.courses)
        XCTAssertEqual(restored.patterns, confirmed.patterns)
        XCTAssertEqual(restored.term, confirmed.term)
        XCTAssertEqual(restored.sourceName, "Reviewed photo import")
    }

    func testCanonicalFormsDoNotCountAsChanges() throws {
        var bundle = CloudFixtures.reviewedPhotoBundle()
        let original = bundle.patterns[0]
        bundle = ImportedScheduleBundle(
            sourceName: bundle.sourceName, importedAt: bundle.importedAt, term: bundle.term, courses: bundle.courses,
            patterns: [MeetingPattern(
                id: original.id, courseID: original.courseID, weekdays: [.thursday, .tuesday, .thursday],
                startHour: 17, startMinute: 30, endHour: 18, endMinute: 45, sourceUntilUTC: "",
                excludedDates: ["2026-11-26", "2026-09-08", "2026-11-26"], meetingKind: .lecture
            )] + bundle.patterns.dropFirst(),
            oneTimeEvents: []
        )
        let (snapshot, restored) = try roundTrip(bundle)
        XCTAssertEqual(snapshot.meetings[0].weekdays, [2, 4])
        XCTAssertEqual(snapshot.meetings[0].excludedDates, ["2026-09-08", "2026-11-26"])
        let again = try CloudScheduleSnapshot(bundle: restored, fallbackTerm: ScheduleSeed.term)
        XCTAssertTrue(again.hasSameContent(as: snapshot), "restoring does not create a phantom local change")
        XCTAssertEqual(occurrences(restored), occurrences(bundle))
    }

    func testImportTimeIsNotAContentChange() throws {
        let first = try CloudScheduleSnapshot(bundle: CloudFixtures.reviewedPhotoBundle(), fallbackTerm: ScheduleSeed.term)
        var later = first
        later.semester.sourceImportedAt = CloudFormat.timestamp(Date())
        XCTAssertTrue(first.hasSameContent(as: later))
        later.courses[0].title = "Changed"
        XCTAssertFalse(first.hasSameContent(as: later))
    }

    func testSchedulesTheCloudCannotRepresentStayLocal() {
        func limitation(_ bundle: ImportedScheduleBundle) -> CloudScheduleLimitation? {
            do {
                _ = try CloudScheduleSnapshot(bundle: bundle, fallbackTerm: ScheduleSeed.term)
                return nil
            } catch CloudScheduleError.unsupportedSchedule(let reason) {
                return reason
            } catch {
                return nil
            }
        }
        let base = CloudFixtures.reviewedPhotoBundle()
        func with(patterns: [MeetingPattern]? = nil, events: [OneTimeEvent] = [], courses: [Course]? = nil) -> ImportedScheduleBundle {
            ImportedScheduleBundle(sourceName: base.sourceName, importedAt: base.importedAt, term: base.term,
                                   courses: courses ?? base.courses, patterns: patterns ?? base.patterns, oneTimeEvents: events)
        }
        let pattern = base.patterns[0]
        func meeting(id: String = "m", courseID: String? = nil, weekdays: [Weekday] = [.monday], start: (Int, Int) = (9, 0),
                     end: (Int, Int) = (10, 0), excluded: [String] = []) -> MeetingPattern {
            MeetingPattern(id: id, courseID: courseID ?? pattern.courseID, weekdays: weekdays, startHour: start.0,
                           startMinute: start.1, endHour: end.0, endMinute: end.1, sourceUntilUTC: "", excludedDates: excluded)
        }

        XCTAssertEqual(limitation(with(patterns: [meeting(id: "same"), meeting(id: "same", weekdays: [.friday])])), .repeatedIdentifier)
        XCTAssertEqual(limitation(with(patterns: [meeting(start: (23, 0), end: (1, 0))])), .invalidMeetingTime)
        XCTAssertEqual(limitation(with(patterns: [meeting(weekdays: [])])), .invalidMeetingTime)
        XCTAssertEqual(limitation(with(patterns: [meeting(courseID: "missing")])), .unknownCourseReference)
        XCTAssertEqual(limitation(with(patterns: [meeting(excluded: ["2026-02-30"])])), .invalidDate)
        XCTAssertEqual(limitation(with(patterns: [], events: [])), .noMeetings)
        XCTAssertEqual(limitation(with(courses: [])), .noCourses)
        var longCourse = base.courses[0]
        longCourse = Course(id: longCourse.id, code: longCourse.code, section: String(repeating: "9", count: 41),
                            title: longCourse.title, credits: 3, catalogSummary: "", colorHex: "5E2E42", symbol: "atom")
        XCTAssertEqual(limitation(with(courses: [longCourse])), .valueTooLong)
        XCTAssertNil(limitation(base))
    }

    func testDownloadedSnapshotsAreValidatedBeforeUse() throws {
        let valid = try CloudScheduleSnapshot(bundle: CloudFixtures.reviewedPhotoBundle(), fallbackTerm: ScheduleSeed.term)
        var badWeekday = valid
        badWeekday.meetings[0].weekdays = [8]
        var danglingCourse = valid
        danglingCourse.meetings[0].courseClientID = "missing"
        var badClock = valid
        badClock.meetings[0].startTime = "7:30"
        var futureFormat = valid
        futureFormat.format = 2
        for snapshot in [badWeekday, danglingCourse, badClock, futureFormat] {
            XCTAssertThrowsError(try snapshot.makeBundle(restoredAt: Date())) { error in
                XCTAssertEqual(error as? CloudScheduleError, .invalidResponse)
            }
        }
    }

    func testWireFormatMatchesTheDatabaseContract() throws {
        let snapshot = try CloudScheduleSnapshot(bundle: CloudFixtures.embeddedBundle, fallbackTerm: ScheduleSeed.term, isEmbedded: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(json["format"] as? Int, 1)
        let meeting = try XCTUnwrap((json["meetings"] as? [[String: Any]])?.first)
        for key in ["client_id", "course_client_id", "meeting_type", "weekdays", "start_time", "end_time",
                    "source_until_utc", "excluded_dates", "additional_dates"] {
            XCTAssertNotNil(meeting[key], "missing \(key)")
        }
        XCTAssertEqual(meeting["start_time"] as? String, "08:00")
        let course = try XCTUnwrap((json["courses"] as? [[String: Any]])?.first)
        XCTAssertEqual(course["client_id"] as? String, "CHEM-107-504")
        XCTAssertEqual(course["crn"] as? String, "10535")
    }

    func testTimestampsUseMillisecondUTC() throws {
        let text = "2026-09-01T12:00:00.123Z"
        let date = try XCTUnwrap(CloudFormat.parseTimestamp(text))
        XCTAssertEqual(CloudFormat.timestamp(date), text)
        XCTAssertEqual(CloudFormat.timestamp(Date(timeIntervalSince1970: 1_790_000_000.123_9)), "2026-09-21T14:13:20.123Z")
        XCTAssertNil(CloudFormat.parseTimestamp("2026-09-01T12:00:00Z"))
        XCTAssertTrue(CloudFormat.isValidDate("2028-02-29"))
        XCTAssertFalse(CloudFormat.isValidDate("2027-02-29"))
    }
}
