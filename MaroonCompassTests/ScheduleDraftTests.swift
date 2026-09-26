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

    func testOCRFallbackCreatesReviewableDraftWithoutInventingBuilding() {
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
        XCTAssertTrue(draft.courses[0].meetings[0].buildingCode.isEmpty)
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
