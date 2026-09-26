import Foundation

/// Public project settings only. Never put a service-role key in the app.
struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> Self? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "MCSupabaseURL") as? String,
              let url = URL(string: rawURL), url.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: "MCSupabasePublishableKey") as? String,
              !key.isEmpty else { return nil }
        return Self(projectURL: url, publishableKey: key)
    }
}

enum CloudScheduleError: LocalizedError {
    case unavailable
    case invalidSession
    case unsupportedSchedule
    case conflict
    case missingSchedule
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Cloud schedule backup is not configured. Your local schedule is safe."
        case .invalidSession: "Sign in before syncing your schedule."
        case .unsupportedSchedule: "This schedule includes calendar details that cloud backup cannot preserve yet."
        case .conflict: "The cloud schedule changed on another device. Review it before replacing either copy."
        case .missingSchedule: "No cloud schedule was found for this semester."
        case .server: "Cloud schedule backup is unavailable. Your local schedule is safe."
        }
    }
}

/// An explicit, lossless subset of the local schedule. OCR and image bytes never enter this type.
struct CloudScheduleSnapshot: Encodable, Sendable {
    let semesterID: UUID
    let name: String
    let firstClassDate: String
    let lastClassDate: String
    let courses: [CloudCourse]

    init(semesterID: UUID, bundle: ImportedScheduleBundle) throws {
        guard let term = bundle.term,
              term.timeZoneIdentifier == "America/Chicago",
              term.finalsStartDate == nil, term.finalsEndDate == nil,
              bundle.oneTimeEvents.isEmpty,
              !bundle.courses.isEmpty,
              bundle.patterns.allSatisfy({ $0.excludedDates.isEmpty && $0.additionalDates.isEmpty }) else {
            throw CloudScheduleError.unsupportedSchedule
        }
        self.semesterID = semesterID
        name = term.name
        firstClassDate = term.firstClassDate
        lastClassDate = term.lastClassDate
        courses = try bundle.courses.map { course in
            guard let courseID = UUID(uuidString: course.id),
                  course.status == nil, course.crn == nil,
                  course.instructionMode == nil, course.instructor == nil else {
                throw CloudScheduleError.unsupportedSchedule
            }
            let meetings = try bundle.patterns.filter { $0.courseID == course.id }.map { pattern in
                let location = [pattern.buildingCode, pattern.room].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                guard let meetingID = UUID(uuidString: pattern.id),
                      pattern.sourceNotes == nil,
                      pattern.sourceUntilUTC.isEmpty,
                      pattern.sourceLocationText == nil || pattern.sourceLocationText == location,
                      !pattern.weekdays.isEmpty,
                      pattern.startHour * 60 + pattern.startMinute < pattern.endHour * 60 + pattern.endMinute else {
                    throw CloudScheduleError.unsupportedSchedule
                }
                return CloudMeeting(
                    id: meetingID,
                    meetingType: pattern.meetingKind.rawValue,
                    weekdays: pattern.weekdays.map { $0.sortIndex + 1 }.sorted(),
                    startTime: String(format: "%02d:%02d", pattern.startHour, pattern.startMinute),
                    endTime: String(format: "%02d:%02d", pattern.endHour, pattern.endMinute),
                    buildingCode: pattern.buildingCode,
                    room: pattern.room
                )
            }
            guard !meetings.isEmpty else { throw CloudScheduleError.unsupportedSchedule }
            return CloudCourse(
                id: courseID, code: course.code, title: course.title,
                section: course.section, credits: course.credits,
                colorHex: course.colorHex, meetings: meetings
            )
        }
        guard bundle.patterns.count == courses.reduce(0, { $0 + $1.meetings.count }) else {
            throw CloudScheduleError.unsupportedSchedule
        }
    }
}

struct CloudCourse: Encodable, Sendable {
    let id: UUID
    let code: String
    let title: String
    let section: String
    let credits: Int
    let colorHex: String
    let meetings: [CloudMeeting]

    enum CodingKeys: String, CodingKey {
        case id, code, title, section, credits, meetings
        case colorHex = "color_hex"
    }
}

struct CloudMeeting: Encodable, Sendable {
    let id: UUID
    let meetingType: String
    let weekdays: [Int]
    let startTime: String
    let endTime: String
    let buildingCode: String?
    let room: String?

    enum CodingKeys: String, CodingKey {
        case id, weekdays, room
        case meetingType = "meeting_type"
        case startTime = "start_time"
        case endTime = "end_time"
        case buildingCode = "building_code"
    }
}

/// Network operations are explicit. Import confirmation always saves locally first.
struct SupabaseScheduleRepository {
    let configuration: SupabaseConfiguration

    private struct RemoteSemester: Decodable {
        let name: String
        let firstClassDate: String
        let lastClassDate: String
        let syncVersion: Int

        enum CodingKeys: String, CodingKey {
            case name
            case firstClassDate = "first_class_date"
            case lastClassDate = "last_class_date"
            case syncVersion = "sync_version"
        }
    }

    private struct RemoteCourse: Decodable {
        let id: UUID
        let code: String
        let title: String
        let section: String?
        let credits: Double?
        let colorHex: String?

        enum CodingKeys: String, CodingKey {
            case id, code, title, section, credits
            case colorHex = "color_hex"
        }
    }

    private struct RemoteMeeting: Decodable {
        let id: UUID
        let courseID: UUID
        let meetingType: String
        let weekdays: [Int]
        let startTime: String
        let endTime: String
        let buildingCode: String?
        let room: String?

        enum CodingKeys: String, CodingKey {
            case id, weekdays, room
            case courseID = "course_id"
            case meetingType = "meeting_type"
            case startTime = "start_time"
            case endTime = "end_time"
            case buildingCode = "building_code"
        }
    }

    func replace(_ snapshot: CloudScheduleSnapshot, expectedVersion: Int?, accessToken: String) async throws -> Int {
        struct Arguments: Encodable {
            let p_semester_id: UUID
            let p_expected_version: Int?
            let p_name: String
            let p_first_class_date: String
            let p_last_class_date: String
            let p_courses: [CloudCourse]
        }
        let body = Arguments(
            p_semester_id: snapshot.semesterID,
            p_expected_version: expectedVersion,
            p_name: snapshot.name,
            p_first_class_date: snapshot.firstClassDate,
            p_last_class_date: snapshot.lastClassDate,
            p_courses: snapshot.courses
        )
        let data = try await request(
            path: "rest/v1/rpc/replace_schedule_snapshot", method: "POST",
            body: try JSONEncoder().encode(body), accessToken: accessToken
        )
        return try JSONDecoder().decode(Int.self, from: data)
    }

    func load(semesterID: UUID, accessToken: String) async throws -> (ImportedScheduleBundle, Int) {
        let decoder = JSONDecoder()
        let semesters = try decoder.decode([RemoteSemester].self, from: await get(
            "semesters", query: ["id": "eq.\(semesterID.uuidString)", "select": "name,first_class_date,last_class_date,sync_version"],
            accessToken: accessToken
        ))
        guard let semester = semesters.first else { throw CloudScheduleError.missingSchedule }
        let remoteCourses = try decoder.decode([RemoteCourse].self, from: await get(
            "courses", query: ["semester_id": "eq.\(semesterID.uuidString)", "select": "id,code,title,section,credits,color_hex"],
            accessToken: accessToken
        ))
        guard !remoteCourses.isEmpty else { throw CloudScheduleError.unsupportedSchedule }
        let courseIDs = remoteCourses.map { $0.id.uuidString }.joined(separator: ",")
        let remoteMeetings = try decoder.decode([RemoteMeeting].self, from: await get(
            "course_meetings", query: ["course_id": "in.(\(courseIDs))", "select": "id,course_id,meeting_type,weekdays,start_time,end_time,building_code,room"],
            accessToken: accessToken
        ))

        var courses: [Course] = []
        var patterns: [MeetingPattern] = []
        for remoteCourse in remoteCourses {
            let credits = remoteCourse.credits ?? 0
            guard credits.isFinite, credits >= 0, credits.rounded() == credits,
                  credits <= Double(Int.max) else { throw CloudScheduleError.unsupportedSchedule }
            courses.append(Course(
                id: remoteCourse.id.uuidString, code: remoteCourse.code,
                section: remoteCourse.section ?? "", title: remoteCourse.title,
                credits: Int(credits), catalogSummary: "",
                colorHex: remoteCourse.colorHex ?? "5E2E42", symbol: "book.closed.fill"
            ))
            let meetings = remoteMeetings.filter { $0.courseID == remoteCourse.id }
            guard !meetings.isEmpty else { throw CloudScheduleError.unsupportedSchedule }
            for meeting in meetings {
                guard let start = MeetingTime.parse(String(meeting.startTime.prefix(5))),
                      let end = MeetingTime.parse(String(meeting.endTime.prefix(5))),
                      start.minutesSinceMidnight < end.minutesSinceMidnight,
                      meeting.weekdays.count == Set(meeting.weekdays).count,
                      !meeting.weekdays.isEmpty,
                      meeting.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                    throw CloudScheduleError.unsupportedSchedule
                }
                let days = meeting.weekdays.sorted().map { Weekday.allCases[$0 - 1] }
                let location = [meeting.buildingCode, meeting.room].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                patterns.append(MeetingPattern(
                    id: meeting.id.uuidString, courseID: remoteCourse.id.uuidString,
                    weekdays: days, startHour: start.hour, startMinute: start.minute,
                    endHour: end.hour, endMinute: end.minute, sourceUntilUTC: "",
                    sourceLocationText: location.isEmpty ? nil : location,
                    meetingKind: MeetingKind(rawValue: meeting.meetingType) ?? .other,
                    buildingCode: meeting.buildingCode, room: meeting.room
                ))
            }
        }
        guard remoteMeetings.count == patterns.count else { throw CloudScheduleError.unsupportedSchedule }
        let term = Term(
            institution: "Texas A&M University", campus: "College Station",
            name: semester.name, firstClassDate: semester.firstClassDate,
            lastClassDate: semester.lastClassDate, finalsStartDate: nil,
            finalsEndDate: nil, timeZoneIdentifier: "America/Chicago"
        )
        return (ImportedScheduleBundle(
            sourceName: "Cloud schedule", importedAt: Date(), term: term,
            courses: courses, patterns: patterns, oneTimeEvents: []
        ), semester.syncVersion)
    }

    private func get(_ table: String, query: [String: String], accessToken: String) async throws -> Data {
        var components = URLComponents(url: configuration.projectURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw CloudScheduleError.unavailable }
        return try await request(url: url, method: "GET", body: nil, accessToken: accessToken)
    }

    private func request(path: String, method: String, body: Data?, accessToken: String) async throws -> Data {
        guard !accessToken.isEmpty else { throw CloudScheduleError.invalidSession }
        let url = configuration.projectURL.appending(path: path)
        return try await request(url: url, method: method, body: body, accessToken: accessToken)
    }

    private func request(url: URL, method: String, body: Data?, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudScheduleError.unavailable }
        if response.statusCode == 409 { throw CloudScheduleError.conflict }
        guard (200...299).contains(response.statusCode) else { throw CloudScheduleError.server(response.statusCode) }
        return data
    }
}
