import Foundation

struct MeetingTime: Equatable, Hashable, Sendable {
    let hour: Int
    let minute: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func parse(_ input: String) -> MeetingTime? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        let suffix: String?
        let clock: String
        if value.hasSuffix("AM") || value.hasSuffix("PM") {
            suffix = String(value.suffix(2))
            clock = String(value.dropLast(2))
        } else {
            suffix = nil
            clock = value
        }

        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let rawHour = Int(parts[0]),
              let minute = Int(parts[1]),
              parts[1].count == 2,
              (0...59).contains(minute) else { return nil }

        if let suffix {
            guard (1...12).contains(rawHour) else { return nil }
            let hour = rawHour % 12 + (suffix == "PM" ? 12 : 0)
            return MeetingTime(hour: hour, minute: minute)
        }

        // Require a two-digit 24-hour clock to avoid silently choosing AM or PM.
        guard parts[0].count == 2, (0...23).contains(rawHour) else { return nil }
        return MeetingTime(hour: rawHour, minute: minute)
    }
}

struct ScheduleDraftMeeting: Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: MeetingKind = .lecture
    var weekdays: Set<Weekday> = []
    var startTime = ""
    var endTime = ""
    var buildingCode = ""
    var room = ""
}

struct ScheduleDraftCourse: Identifiable, Equatable, Sendable {
    var id = UUID()
    var code = ""
    var title = ""
    var section = ""
    var meetings: [ScheduleDraftMeeting] = [ScheduleDraftMeeting()]
}

struct ScheduleDraftIssue: Identifiable, Equatable, Sendable {
    var id: String { "\(courseID?.uuidString ?? "schedule")-\(meetingID?.uuidString ?? "course")-\(message)" }
    let courseID: UUID?
    let meetingID: UUID?
    let message: String
}

enum ScheduleDraftError: LocalizedError {
    case needsReview

    var errorDescription: String? {
        "Review the highlighted schedule fields before saving."
    }
}

struct ScheduleDraft: Equatable, Sendable {
    var termName: String
    var firstClassDate: String
    var lastClassDate: String
    var courses: [ScheduleDraftCourse] = []
    var notes: [String] = []

    var issues: [ScheduleDraftIssue] {
        var result: [ScheduleDraftIssue] = []
        func add(_ message: String, course: ScheduleDraftCourse? = nil, meeting: ScheduleDraftMeeting? = nil) {
            result.append(ScheduleDraftIssue(courseID: course?.id, meetingID: meeting?.id, message: message))
        }

        if termName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add("Enter a semester name.") }
        if let first = Self.campusDate(firstClassDate),
           let last = Self.campusDate(lastClassDate),
           first <= last,
           last.timeIntervalSince(first) <= 370 * 86_400 {
            // The term is valid; continue checking every editable course field.
        } else {
            add("Enter valid first and last class dates within one year (YYYY-MM-DD).")
        }

        if courses.isEmpty { add("Add at least one course.") }
        var courseKeys: Set<String> = []
        var validMeetings: [(course: ScheduleDraftCourse, meeting: ScheduleDraftMeeting, start: Int, end: Int)] = []
        for course in courses {
            let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty { add("Enter a course code.", course: course) }
            if title.isEmpty { add("Enter a course name.", course: course) }
            let normalizedCode = code.uppercased().replacingOccurrences(of: #"[\s-]+"#, with: "", options: .regularExpression)
            let key = "\(normalizedCode)|\(course.section.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
            if !code.isEmpty && !courseKeys.insert(key).inserted {
                add("This course and section appear more than once.", course: course)
            }
            if course.meetings.isEmpty { add("Add at least one meeting.", course: course) }
            var meetingKeys: Set<String> = []
            for meeting in course.meetings {
                if meeting.weekdays.isEmpty { add("Select at least one weekday.", course: course, meeting: meeting) }
                let start = MeetingTime.parse(meeting.startTime)
                let end = MeetingTime.parse(meeting.endTime)
                if start == nil || end == nil {
                    add("Enter clear start and end times, such as 09:35 and 10:50.", course: course, meeting: meeting)
                } else if start!.minutesSinceMidnight >= end!.minutesSinceMidnight {
                    add("The meeting must end after it starts.", course: course, meeting: meeting)
                } else {
                    validMeetings.append((course, meeting, start!.minutesSinceMidnight, end!.minutesSinceMidnight))
                }
                if meeting.buildingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !meeting.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add("Add a building code for this room, or clear the room.", course: course, meeting: meeting)
                }
                if let start, let end {
                    let days = meeting.weekdays.sorted { $0.sortIndex < $1.sortIndex }.map(\.rawValue).joined(separator: ",")
                    let meetingKey = "\(days)|\(start.minutesSinceMidnight)|\(end.minutesSinceMidnight)|\(meeting.kind.rawValue)"
                    if !meetingKeys.insert(meetingKey).inserted {
                        add("This meeting appears more than once.", course: course, meeting: meeting)
                    }
                }
            }
        }
        for index in validMeetings.indices {
            let current = validMeetings[index]
            for other in validMeetings[..<index] {
                guard !current.meeting.weekdays.isDisjoint(with: other.meeting.weekdays),
                      current.start < other.end, other.start < current.end else { continue }
                add("This meeting overlaps \(other.course.code.isEmpty ? "another course" : other.course.code).", course: current.course, meeting: current.meeting)
                add("This meeting overlaps \(current.course.code.isEmpty ? "another course" : current.course.code).", course: other.course, meeting: other.meeting)
            }
        }
        return result
    }

    func confirmedBundle(sourceName: String) throws -> ImportedScheduleBundle {
        guard issues.isEmpty else { throw ScheduleDraftError.needsReview }
        let term = Term(
            institution: "Texas A&M University",
            campus: "College Station",
            name: termName.trimmingCharacters(in: .whitespacesAndNewlines),
            firstClassDate: firstClassDate,
            lastClassDate: lastClassDate,
            finalsStartDate: nil,
            finalsEndDate: nil,
            timeZoneIdentifier: "America/Chicago"
        )
        var confirmedCourses: [Course] = []
        var patterns: [MeetingPattern] = []
        for course in courses {
            let courseID = course.id.uuidString
            confirmedCourses.append(Course(
                id: courseID,
                code: course.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                section: course.section.trimmingCharacters(in: .whitespacesAndNewlines),
                title: course.title.trimmingCharacters(in: .whitespacesAndNewlines),
                credits: 0,
                catalogSummary: "",
                colorHex: "5E2E42",
                symbol: "book.closed.fill"
            ))
            for meeting in course.meetings {
                let start = MeetingTime.parse(meeting.startTime)!
                let end = MeetingTime.parse(meeting.endTime)!
                let building = meeting.buildingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let room = meeting.room.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = building.isEmpty ? nil : [building, room].filter { !$0.isEmpty }.joined(separator: " · ")
                patterns.append(MeetingPattern(
                    id: meeting.id.uuidString,
                    courseID: courseID,
                    weekdays: meeting.weekdays.sorted { $0.sortIndex < $1.sortIndex },
                    startHour: start.hour,
                    startMinute: start.minute,
                    endHour: end.hour,
                    endMinute: end.minute,
                    sourceUntilUTC: "",
                    sourceLocationText: location,
                    meetingKind: meeting.kind,
                    buildingCode: building.isEmpty ? nil : building,
                    room: room.isEmpty ? nil : room
                ))
            }
        }
        return ImportedScheduleBundle(
            sourceName: sourceName,
            importedAt: Date(),
            term: term,
            courses: confirmedCourses,
            patterns: patterns,
            oneTimeEvents: []
        )
    }

    private static func campusDate(_ text: String) -> Date? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: text)
    }
}
