import XCTest
@testable import MaroonCompass

final class ScheduleDraftTests: XCTestCase {
    func testMeetingTimeRequiresUnambiguousClock() {
        XCTAssertEqual(MeetingTime.parse("09:35"), MeetingTime(hour: 9, minute: 35))
        XCTAssertEqual(MeetingTime.parse("5:30 PM"), MeetingTime(hour: 17, minute: 30))
        XCTAssertEqual(MeetingTime.parse("12:15 AM"), MeetingTime(hour: 0, minute: 15))
        XCTAssertNil(MeetingTime.parse("9:35"))
        XCTAssertNil(MeetingTime.parse("25:15"))
        XCTAssertNil(MeetingTime.parse("9:70 AM"))
    }

    func testDraftRejectsMissingAndConflictingFields() {
        var draft = ScheduleDraft(
            termName: "Fall 2026",
            firstClassDate: "2026-08-24",
            lastClassDate: "2026-12-03"
        )
        var course = ScheduleDraftCourse()
        course.code = "MATH 251"
        course.title = ""
        course.meetings[0].weekdays = [.tuesday, .thursday]
        course.meetings[0].startTime = "17:30"
        course.meetings[0].endTime = "17:00"
        draft.courses = [course, course]

        let messages = draft.issues.map(\.message)
        XCTAssertTrue(messages.contains("Enter a course name."))
        XCTAssertTrue(messages.contains("The meeting must end after it starts."))
        XCTAssertTrue(messages.contains("This course and section appear more than once."))
        XCTAssertThrowsError(try draft.confirmedBundle(sourceName: "Test"))
    }

    func testValidationKeepsFieldErrorsVisibleWithInvalidDates() {
        var draft = ScheduleDraft(termName: "Fall", firstClassDate: "2026-02-30", lastClassDate: "2026-12-03")
        draft.courses = [ScheduleDraftCourse()]

        let messages = draft.issues.map(\.message)
        XCTAssertTrue(messages.contains("Enter valid first and last class dates within one year (YYYY-MM-DD)."))
        XCTAssertTrue(messages.contains("Enter a course code."))
        XCTAssertTrue(messages.contains("Enter a course name."))
        XCTAssertTrue(messages.contains("Select at least one weekday."))
    }

    func testNormalizedDuplicatesOverlapsAndRoomWithoutBuildingBlockSave() {
        var draft = ScheduleDraft(termName: "Fall 2026", firstClassDate: "2026-08-24", lastClassDate: "2026-12-03")
        var first = ScheduleDraftCourse()
        first.code = "MATH 251"
        first.title = "Calculus III"
        first.section = "502"
        first.meetings = [
            ScheduleDraftMeeting(kind: .lecture, weekdays: [.monday], startTime: "09:30", endTime: "10:45", buildingCode: "", room: "1O9"),
            ScheduleDraftMeeting(kind: .lecture, weekdays: [.monday], startTime: "9:30 AM", endTime: "10:45", buildingCode: "", room: "")
        ]
        var duplicate = ScheduleDraftCourse()
        duplicate.code = "MATH-251"
        duplicate.title = "Calculus III"
        duplicate.section = "502"
        duplicate.meetings = [ScheduleDraftMeeting(kind: .lab, weekdays: [.monday], startTime: "10:30", endTime: "11:20", buildingCode: "BLOC", room: "169")]
        draft.courses = [first, duplicate]

        let messages = draft.issues.map(\.message)
        XCTAssertTrue(messages.contains("This course and section appear more than once."))
        XCTAssertTrue(messages.contains("This meeting appears more than once."))
        XCTAssertTrue(messages.contains("Add a building code for this room, or clear the room."))
        XCTAssertTrue(messages.contains(where: { $0.contains("overlaps") }))
        XCTAssertThrowsError(try draft.confirmedBundle(sourceName: "Test"))
    }

    func testAdjacentMeetingsDoNotConflict() {
        var draft = ScheduleDraft(termName: "Fall 2026", firstClassDate: "2026-08-24", lastClassDate: "2026-12-03")
        var course = ScheduleDraftCourse()
        course.code = "ENGR 102"
        course.title = "Engineering Lab I"
        course.meetings = [
            ScheduleDraftMeeting(kind: .lab, weekdays: [.monday], startTime: "17:10", endTime: "18:00"),
            ScheduleDraftMeeting(kind: .lab, weekdays: [.monday], startTime: "18:01", endTime: "19:00")
        ]
        draft.courses = [course]
        XCTAssertFalse(draft.issues.contains(where: { $0.message.contains("overlaps") }))
        XCTAssertNoThrow(try draft.confirmedBundle(sourceName: "Test"))
    }

    func testConfirmedDraftPreservesSeparateMeetingsAndUnknowns() throws {
        var draft = ScheduleDraft(
            termName: "Fall 2026",
            firstClassDate: "2026-08-24",
            lastClassDate: "2026-12-03"
        )
        var course = ScheduleDraftCourse()
        course.code = "ENGR 102"
        course.title = "Engineering Lab"
        course.section = "505"
        course.meetings = [
            ScheduleDraftMeeting(kind: .lecture, weekdays: [.monday], startTime: "17:10", endTime: "18:00", buildingCode: "ZACH", room: "353"),
            ScheduleDraftMeeting(kind: .lab, weekdays: [.wednesday], startTime: "17:10", endTime: "19:00", buildingCode: "", room: "")
        ]
        draft.courses = [course]

        let bundle = try draft.confirmedBundle(sourceName: "Reviewed photo")
        XCTAssertEqual(bundle.courses.count, 1)
        XCTAssertEqual(bundle.courses[0].credits, 0)
        XCTAssertEqual(bundle.patterns.count, 2)
        XCTAssertEqual(bundle.patterns[0].meetingKind, .lecture)
        XCTAssertEqual(bundle.patterns[1].meetingKind, .lab)
        XCTAssertEqual(bundle.patterns[0].sourceLocationText, "ZACH · 353")
        XCTAssertNil(bundle.patterns[1].sourceLocationText)
        XCTAssertNil(bundle.term?.finalsStartDate)
        XCTAssertNil(bundle.term?.finalsEndDate)
    }

    func testOCRFallbackTranscribesVisibleBuildingWithoutInferringOtherFields() {
        let draft = ScheduleImageImportService.draftFromRecognizedLines(
            ["MATH 251-502 Calculus III", "Tue Thu 5:30 PM - 6:45 PM BLOC 169"],
            currentTerm: ScheduleSeed.term
        )
        XCTAssertEqual(draft.courses.count, 1)
        XCTAssertEqual(draft.courses[0].code, "MATH 251")
        XCTAssertEqual(draft.courses[0].section, "502")
        XCTAssertEqual(draft.courses[0].meetings.count, 1)
        XCTAssertEqual(draft.courses[0].meetings[0].weekdays, [.tuesday, .thursday])
        XCTAssertEqual(draft.courses[0].meetings[0].startTime, "5:30 PM")
        XCTAssertEqual(draft.courses[0].meetings[0].buildingCode, "BLOC")
        XCTAssertEqual(draft.courses[0].meetings[0].room, "169")
    }

    func testSyntheticOCRTranscriptPreservesNumbersRoomsAndRepeatedCourseMeetings() {
        let draft = ScheduleImageImportService.draftFromRecognizedLines(
            [
                "MATH 251-502 Calculus 3 Tue Thu 5:30 PM - 6:45 PM BLOC 1O9",
                "CHEM 117-541 General Chemistry Laboratory",
                "Tue LAB 11:10 AM - 2:00 PM HELD 302",
                "MATH 251-502 Calculus 3",
                "Wed RECITATION 09:10 - 10:00 BLOC 169",
                "Dining hours 9:00 AM - 5:00 PM"
            ], currentTerm: ScheduleSeed.term
        )
        XCTAssertEqual(draft.courses.count, 2)
        XCTAssertEqual(draft.courses[0].title, "Calculus 3")
        XCTAssertEqual(draft.courses[0].meetings.count, 2)
        XCTAssertEqual(draft.courses[0].meetings[0].weekdays, [.tuesday, .thursday])
        XCTAssertEqual(draft.courses[0].meetings[0].buildingCode, "BLOC")
        XCTAssertEqual(draft.courses[0].meetings[0].room, "1O9")
        XCTAssertEqual(draft.courses[0].meetings[1].kind, .recitation)
        XCTAssertEqual(draft.courses[1].meetings.count, 1)
        XCTAssertEqual(draft.courses[1].meetings[0].kind, .lab)
        XCTAssertEqual(draft.courses[1].meetings[0].room, "302")
    }

    func testMissingWeekdayColumnDoesNotAttachUnrelatedTime() {
        let draft = ScheduleImageImportService.draftFromRecognizedLines(
            ["POLS 207-502 State and Local Government", "09:10 - 10:00", "Store hours 9:00 AM - 5:00 PM"],
            currentTerm: ScheduleSeed.term
        )
        XCTAssertEqual(draft.courses.count, 1)
        XCTAssertEqual(draft.courses[0].meetings.count, 1)
        XCTAssertTrue(draft.courses[0].meetings[0].weekdays.isEmpty)
        XCTAssertTrue(draft.courses[0].meetings[0].startTime.isEmpty)
        XCTAssertFalse(draft.issues.isEmpty)
    }

    func testOldImportedBundleDecodesWithoutNewTermOrMeetingFields() throws {
        let old = ImportedScheduleBundle(
            sourceName: "Older import",
            importedAt: Date(timeIntervalSince1970: 0),
            courses: ScheduleSeed.courses,
            patterns: ScheduleSeed.patterns,
            oneTimeEvents: []
        )
        let data = try JSONEncoder().encode(old)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "term")
        var patterns = try XCTUnwrap(json["patterns"] as? [[String: Any]])
        for index in patterns.indices {
            patterns[index].removeValue(forKey: "meetingKind")
            patterns[index].removeValue(forKey: "buildingCode")
            patterns[index].removeValue(forKey: "room")
        }
        json["patterns"] = patterns
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ImportedScheduleBundle.self, from: legacyData)
        XCTAssertNil(decoded.term)
        XCTAssertEqual(decoded.patterns.first?.meetingKind, .lecture)
    }

    func testCloudSnapshotAcceptsReviewedPhotoButRejectsLossyCalendarImport() throws {
        var draft = ScheduleDraft(
            termName: "Fall 2027", firstClassDate: "2027-08-30", lastClassDate: "2027-12-10"
        )
        var course = ScheduleDraftCourse()
        course.code = "MATH 251"
        course.title = "Calculus III"
        var meeting = ScheduleDraftMeeting()
        meeting.weekdays = [.tuesday, .thursday]
        meeting.startTime = "5:30 PM"
        meeting.endTime = "6:45 PM"
        course.meetings = [meeting]
        draft.courses = [course]
        let bundle = try draft.confirmedBundle(sourceName: "Reviewed photo")
        let snapshot = try CloudScheduleSnapshot(semesterID: UUID(), bundle: bundle)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let courses = try XCTUnwrap(json["courses"] as? [[String: Any]])
        let meetings = try XCTUnwrap(courses[0]["meetings"] as? [[String: Any]])
        XCTAssertEqual(meetings[0]["weekdays"] as? [Int], [2, 4])
        XCTAssertEqual(meetings[0]["start_time"] as? String, "17:30")
        XCTAssertNil(meetings[0]["building_code"])

        let oldCalendar = ImportedScheduleBundle(
            sourceName: "Calendar", importedAt: Date(), term: bundle.term,
            courses: bundle.courses, patterns: bundle.patterns,
            oneTimeEvents: [OneTimeEvent(
                id: UUID().uuidString, courseID: bundle.courses[0].id,
                date: "2027-11-01", startHour: 9, startMinute: 0,
                endHour: 10, endMinute: 0, title: "Exam"
            )]
        )
        XCTAssertThrowsError(try CloudScheduleSnapshot(semesterID: UUID(), bundle: oldCalendar))
    }
}
