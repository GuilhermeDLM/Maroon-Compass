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

    private func request(path: String, method: String, body: Data?, accessToken: String) async throws -> Data {
        guard !accessToken.isEmpty else { throw CloudScheduleError.invalidSession }
        let url = configuration.projectURL.appending(path: path)
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
