import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Why a local schedule cannot be stored in the cloud without changing it. Such schedules stay
/// on this device; nothing is silently dropped or rewritten.
enum CloudScheduleLimitation: Equatable, Sendable {
    case noCourses
    case tooManyCourses
    case noMeetings
    case tooManyMeetings
    case tooManyEvents
    case repeatedIdentifier
    case unknownCourseReference
    case invalidMeetingTime
    case invalidDate
    case invalidTerm
    case valueTooLong
    case unsupportedValue

    var explanation: String {
        switch self {
        case .noCourses: "It has no courses."
        case .tooManyCourses: "It has more than 100 courses."
        case .noMeetings: "It has no class meetings."
        case .tooManyMeetings: "It has more than 500 weekly meetings."
        case .tooManyEvents: "It has more than 1,000 one-time events."
        case .repeatedIdentifier: "Its calendar source repeats an event identifier."
        case .unknownCourseReference: "A meeting refers to a course that isn't in the schedule."
        case .invalidMeetingTime: "A meeting has no weekday, ends before it starts, or crosses midnight."
        case .invalidDate: "A date in the schedule isn't a valid calendar date."
        case .invalidTerm: "The semester dates or time zone can't be verified."
        case .valueTooLong: "A course field is longer than cloud backup allows."
        case .unsupportedValue: "A course color, icon, or credit value isn't supported by cloud backup."
        }
    }
}

enum CloudScheduleError: LocalizedError, Equatable, Sendable {
    case unsupportedSchedule(CloudScheduleLimitation)
    case unauthorized
    case versionConflict
    case scheduleExists
    case scheduleMissing
    case invalidSnapshot
    case semesterLimitReached
    case offline
    case rateLimited
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedSchedule(let limitation):
            "This schedule stays on this device. \(limitation.explanation)"
        case .unauthorized: "Your cloud session was not accepted. Sign in again; your local schedule is safe."
        case .versionConflict: "The cloud schedule changed on another device. Review it before replacing either copy."
        case .scheduleExists: "A cloud schedule for this term already exists. Review it before replacing either copy."
        case .scheduleMissing: "The cloud copy of this schedule no longer exists."
        case .invalidSnapshot: "The cloud rejected this schedule as invalid. Your local schedule is unchanged."
        case .semesterLimitReached: "Cloud backup keeps up to 20 semesters. Delete an old one first."
        case .offline: "You're offline. Nothing changed; try again when you're connected."
        case .rateLimited: "Too many requests. Wait a minute and try again."
        case .server: "Cloud backup is unavailable right now. Your local schedule is safe."
        case .invalidResponse: "The cloud returned a schedule this version of the app can't read. Nothing changed."
        }
    }
}

/// A complete, canonical cloud form of one confirmed local schedule. It preserves the app's own
/// identifiers, order, Howdy metadata, EXDATE/RDATE lists, UNTIL text, notes, and one-time
/// events. Photos, OCR text, and `.ics` diagnostic properties are never part of it.
struct CloudScheduleSnapshot: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format: Int
    var semester: Semester
    var courses: [CourseRecord]
    var meetings: [MeetingRecord]
    var events: [EventRecord]

    struct Semester: Codable, Equatable, Sendable {
        var name: String
        var institution: String
        var campus: String
        var firstClassDate: String
        var lastClassDate: String
        var finalsStartDate: String?
        var finalsEndDate: String?
        var timeZone: String
        var sourceName: String
        /// Informational; excluded from change detection.
        var sourceImportedAt: String?

        enum CodingKeys: String, CodingKey {
            case name, institution, campus
            case firstClassDate = "first_class_date"
            case lastClassDate = "last_class_date"
            case finalsStartDate = "finals_start_date"
            case finalsEndDate = "finals_end_date"
            case timeZone = "time_zone"
            case sourceName = "source_name"
            case sourceImportedAt = "source_imported_at"
        }
    }

    struct CourseRecord: Codable, Equatable, Sendable {
        var clientID: String
        var code: String
        var section: String
        var title: String
        var credits: Int
        var catalogSummary: String
        var colorHex: String
        var symbol: String
        var status: String?
        var crn: String?
        var instructionMode: String?
        var instructor: String?

        enum CodingKeys: String, CodingKey {
            case code, section, title, credits, symbol, status, crn, instructor
            case clientID = "client_id"
            case catalogSummary = "catalog_summary"
            case colorHex = "color_hex"
            case instructionMode = "instruction_mode"
        }
    }

    struct MeetingRecord: Codable, Equatable, Sendable {
        var clientID: String
        var courseClientID: String
        var meetingType: String
        /// ISO weekdays, Monday = 1 … Sunday = 7, strictly increasing.
        var weekdays: [Int]
        var startTime: String
        var endTime: String
        var buildingCode: String?
        var room: String?
        var sourceUntilUTC: String
        var excludedDates: [String]
        var additionalDates: [String]
        var sourceLocationText: String?
        var sourceNotes: String?

        enum CodingKeys: String, CodingKey {
            case weekdays, room
            case clientID = "client_id"
            case courseClientID = "course_client_id"
            case meetingType = "meeting_type"
            case startTime = "start_time"
            case endTime = "end_time"
            case buildingCode = "building_code"
            case sourceUntilUTC = "source_until_utc"
            case excludedDates = "excluded_dates"
            case additionalDates = "additional_dates"
            case sourceLocationText = "source_location_text"
            case sourceNotes = "source_notes"
        }
    }

    struct EventRecord: Codable, Equatable, Sendable {
        var clientID: String
        var courseClientID: String
        var eventDate: String
        var startTime: String
        var endTime: String
        var title: String
        var sourceLocationText: String?
        var sourceNotes: String?

        enum CodingKeys: String, CodingKey {
            case title
            case clientID = "client_id"
            case courseClientID = "course_client_id"
            case eventDate = "event_date"
            case startTime = "start_time"
            case endTime = "end_time"
            case sourceLocationText = "source_location_text"
            case sourceNotes = "source_notes"
        }
    }

    /// The content that matters for sync decisions (everything except the import timestamp).
    var syncContent: CloudScheduleSnapshot {
        var copy = self
        copy.semester.sourceImportedAt = nil
        return copy
    }

    func hasSameContent(as other: CloudScheduleSnapshot) -> Bool {
        syncContent == other.syncContent
    }

    init(format: Int, semester: Semester, courses: [CourseRecord], meetings: [MeetingRecord], events: [EventRecord]) {
        self.format = format
        self.semester = semester
        self.courses = courses
        self.meetings = meetings
        self.events = events
    }

    /// Builds the cloud form of a local schedule, or explains why it must stay local.
    /// - Parameters:
    ///   - fallbackTerm: the term the app uses when an import carries none (older `.ics` imports).
    ///   - isEmbedded: the verified schedule bundled with the app, which has no import time.
    init(bundle: ImportedScheduleBundle, fallbackTerm: Term, isEmbedded: Bool = false) throws {
        func reject(_ limitation: CloudScheduleLimitation) -> CloudScheduleError {
            .unsupportedSchedule(limitation)
        }
        func text(_ value: String, max: Int, allowEmpty: Bool = true) throws -> String {
            guard value.count <= max else { throw reject(.valueTooLong) }
            if !allowEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw reject(.valueTooLong) }
            return value
        }
        func optionalText(_ value: String?, max: Int) throws -> String? {
            guard let value else { return nil }
            return try text(value, max: max)
        }
        func canonicalDates(_ values: [String]) throws -> [String] {
            guard values.allSatisfy(CloudFormat.isValidDate) else { throw reject(.invalidDate) }
            // Sorting and de-duplicating an exclusion/addition set does not change its meaning.
            let result = Array(Set(values)).sorted()
            guard result.count <= 366 else { throw reject(.valueTooLong) }
            return result
        }
        func clocks(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) throws -> (String, String) {
            guard let start = CloudFormat.clock(hour: startHour, minute: startMinute),
                  let end = CloudFormat.clock(hour: endHour, minute: endMinute),
                  startHour * 60 + startMinute < endHour * 60 + endMinute else { throw reject(.invalidMeetingTime) }
            return (start, end)
        }

        let term = bundle.term ?? fallbackTerm
        guard CloudFormat.isValidDate(term.firstClassDate), CloudFormat.isValidDate(term.lastClassDate),
              term.firstClassDate <= term.lastClassDate,
              [term.finalsStartDate, term.finalsEndDate].compactMap({ $0 }).allSatisfy(CloudFormat.isValidDate),
              TimeZone(identifier: term.timeZoneIdentifier) != nil,
              !term.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !term.institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !term.campus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw reject(.invalidTerm)
        }
        if let start = term.finalsStartDate, let end = term.finalsEndDate, end < start { throw reject(.invalidTerm) }

        guard !bundle.courses.isEmpty else { throw reject(.noCourses) }
        guard bundle.courses.count <= 100 else { throw reject(.tooManyCourses) }
        guard !bundle.patterns.isEmpty || !bundle.oneTimeEvents.isEmpty else { throw reject(.noMeetings) }
        guard bundle.patterns.count <= 500 else { throw reject(.tooManyMeetings) }
        guard bundle.oneTimeEvents.count <= 1_000 else { throw reject(.tooManyEvents) }

        let courseIDs = bundle.courses.map(\.id)
        guard Set(courseIDs).count == courseIDs.count,
              Set(bundle.patterns.map(\.id)).count == bundle.patterns.count,
              Set(bundle.oneTimeEvents.map(\.id)).count == bundle.oneTimeEvents.count else {
            throw reject(.repeatedIdentifier)
        }
        let knownCourses = Set(courseIDs)
        guard bundle.patterns.allSatisfy({ knownCourses.contains($0.courseID) }),
              bundle.oneTimeEvents.allSatisfy({ knownCourses.contains($0.courseID) }) else {
            throw reject(.unknownCourseReference)
        }

        format = Self.currentFormat
        semester = Semester(
            name: try text(term.name, max: 120),
            institution: try text(term.institution, max: 120),
            campus: try text(term.campus, max: 120),
            firstClassDate: term.firstClassDate,
            lastClassDate: term.lastClassDate,
            finalsStartDate: term.finalsStartDate,
            finalsEndDate: term.finalsEndDate,
            timeZone: try text(term.timeZoneIdentifier, max: 64),
            sourceName: try text(bundle.sourceName, max: 200),
            sourceImportedAt: isEmbedded ? nil : CloudFormat.timestamp(bundle.importedAt)
        )

        courses = try bundle.courses.map { course in
            guard (1...255).contains(course.id.count),
                  (0...30).contains(course.credits),
                  course.colorHex.range(of: #"^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil,
                  course.symbol.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil else {
                throw reject(.unsupportedValue)
            }
            let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...40).contains(code.count), (1...200).contains(title.count) else { throw reject(.valueTooLong) }
            return CourseRecord(
                clientID: course.id,
                code: course.code,
                section: try text(course.section, max: 40),
                title: course.title,
                credits: course.credits,
                catalogSummary: try text(course.catalogSummary, max: 2_000),
                colorHex: course.colorHex,
                symbol: course.symbol,
                status: try optionalText(course.status, max: 80),
                crn: try optionalText(course.crn, max: 20),
                instructionMode: try optionalText(course.instructionMode, max: 120),
                instructor: try optionalText(course.instructor, max: 200)
            )
        }

        meetings = try bundle.patterns.map { pattern in
            guard (1...255).contains(pattern.id.count) else { throw reject(.valueTooLong) }
            let weekdays = Set(pattern.weekdays).map { $0.sortIndex + 1 }.sorted()
            guard !weekdays.isEmpty else { throw reject(.invalidMeetingTime) }
            let (start, end) = try clocks(pattern.startHour, pattern.startMinute, pattern.endHour, pattern.endMinute)
            return MeetingRecord(
                clientID: pattern.id,
                courseClientID: pattern.courseID,
                meetingType: pattern.meetingKind.rawValue,
                weekdays: weekdays,
                startTime: start,
                endTime: end,
                buildingCode: try optionalText(pattern.buildingCode, max: 20),
                room: try optionalText(pattern.room, max: 40),
                sourceUntilUTC: try text(pattern.sourceUntilUTC, max: 64),
                excludedDates: try canonicalDates(pattern.excludedDates),
                additionalDates: try canonicalDates(pattern.additionalDates),
                sourceLocationText: try optionalText(pattern.sourceLocationText, max: 200),
                sourceNotes: try optionalText(pattern.sourceNotes, max: 2_000)
            )
        }

        events = try bundle.oneTimeEvents.map { event in
            guard (1...255).contains(event.id.count) else { throw reject(.valueTooLong) }
            guard CloudFormat.isValidDate(event.date) else { throw reject(.invalidDate) }
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...200).contains(title.count) else { throw reject(.valueTooLong) }
            let (start, end) = try clocks(event.startHour, event.startMinute, event.endHour, event.endMinute)
            return EventRecord(
                clientID: event.id,
                courseClientID: event.courseID,
                eventDate: event.date,
                startTime: start,
                endTime: end,
                title: event.title,
                sourceLocationText: try optionalText(event.sourceLocationText, max: 200),
                sourceNotes: try optionalText(event.sourceNotes, max: 2_000)
            )
        }
    }

    /// Converts a downloaded snapshot back to the app's schedule model. Every field is validated
    /// again; an unreadable snapshot is rejected instead of partially applied.
    func makeBundle(restoredAt: Date) throws -> ImportedScheduleBundle {
        guard format == Self.currentFormat else { throw CloudScheduleError.invalidResponse }
        let knownCourses = Set(courses.map(\.clientID))
        guard knownCourses.count == courses.count, !courses.isEmpty else { throw CloudScheduleError.invalidResponse }

        let appCourses = courses.map { course in
            Course(
                id: course.clientID, code: course.code, section: course.section, title: course.title,
                credits: course.credits, catalogSummary: course.catalogSummary, colorHex: course.colorHex,
                symbol: course.symbol, status: course.status, crn: course.crn,
                instructionMode: course.instructionMode, instructor: course.instructor
            )
        }
        let patterns = try meetings.map { meeting -> MeetingPattern in
            guard knownCourses.contains(meeting.courseClientID),
                  let start = CloudFormat.parseClock(meeting.startTime),
                  let end = CloudFormat.parseClock(meeting.endTime),
                  !meeting.weekdays.isEmpty, Set(meeting.weekdays).count == meeting.weekdays.count,
                  meeting.weekdays.allSatisfy({ (1...7).contains($0) }),
                  let kind = MeetingKind(rawValue: meeting.meetingType) else {
                throw CloudScheduleError.invalidResponse
            }
            return MeetingPattern(
                id: meeting.clientID, courseID: meeting.courseClientID,
                weekdays: meeting.weekdays.sorted().map { Weekday.allCases[$0 - 1] },
                startHour: start.hour, startMinute: start.minute, endHour: end.hour, endMinute: end.minute,
                sourceUntilUTC: meeting.sourceUntilUTC, excludedDates: meeting.excludedDates,
                additionalDates: meeting.additionalDates, sourceLocationText: meeting.sourceLocationText,
                sourceNotes: meeting.sourceNotes, meetingKind: kind,
                buildingCode: meeting.buildingCode, room: meeting.room
            )
        }
        let oneTimeEvents = try events.map { event -> OneTimeEvent in
            guard knownCourses.contains(event.courseClientID),
                  CloudFormat.isValidDate(event.eventDate),
                  let start = CloudFormat.parseClock(event.startTime),
                  let end = CloudFormat.parseClock(event.endTime) else {
                throw CloudScheduleError.invalidResponse
            }
            return OneTimeEvent(
                id: event.clientID, courseID: event.courseClientID, date: event.eventDate,
                startHour: start.hour, startMinute: start.minute, endHour: end.hour, endMinute: end.minute,
                title: event.title, sourceLocationText: event.sourceLocationText, sourceNotes: event.sourceNotes
            )
        }
        let term = Term(
            institution: semester.institution, campus: semester.campus, name: semester.name,
            firstClassDate: semester.firstClassDate, lastClassDate: semester.lastClassDate,
            finalsStartDate: semester.finalsStartDate, finalsEndDate: semester.finalsEndDate,
            timeZoneIdentifier: semester.timeZone
        )
        return ImportedScheduleBundle(
            sourceName: semester.sourceName,
            importedAt: semester.sourceImportedAt.flatMap(CloudFormat.parseTimestamp) ?? restoredAt,
            term: term,
            courses: appCourses,
            patterns: patterns,
            oneTimeEvents: oneTimeEvents
        )
    }
}

struct CloudSemesterSummary: Codable, Equatable, Hashable, Sendable, Identifiable {
    let semesterID: UUID
    let name: String
    let firstClassDate: String
    let lastClassDate: String
    let syncVersion: Int
    let updatedAt: String
    let courseCount: Int

    var id: UUID { semesterID }
    var updatedDate: Date? { CloudFormat.parseTimestamp(updatedAt) }

    enum CodingKeys: String, CodingKey {
        case name
        case semesterID = "semester_id"
        case firstClassDate = "first_class_date"
        case lastClassDate = "last_class_date"
        case syncVersion = "sync_version"
        case updatedAt = "updated_at"
        case courseCount = "course_count"
    }
}

struct CloudScheduleRecord: Equatable, Sendable {
    let semesterID: UUID
    let syncVersion: Int
    let updatedAt: String
    let snapshot: CloudScheduleSnapshot
}

struct CloudWriteResult: Codable, Equatable, Sendable {
    let semesterID: UUID
    let syncVersion: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case semesterID = "semester_id"
        case syncVersion = "sync_version"
        case updatedAt = "updated_at"
    }
}

/// Explicit schedule transport over PostgREST. Every call is scoped by the caller's token and
/// Row Level Security; the server derives ownership from the token, never from request data.
struct SupabaseScheduleRepository: Sendable {
    let configuration: SupabaseConfiguration
    let transport: any HTTPTransport

    func listSemesters(accessToken: String) async throws -> [CloudSemesterSummary] {
        let data = try await rpc("list_schedule_semesters", body: [String: String](), accessToken: accessToken)
        return try decode([CloudSemesterSummary].self, from: data)
    }

    /// Returns nil when the semester does not exist for this account.
    func fetch(semesterID: UUID, accessToken: String) async throws -> CloudScheduleRecord? {
        let data = try await rpc("get_schedule_snapshot", body: ["p_semester_id": semesterID], accessToken: accessToken)
        guard let envelope = try decode(Envelope?.self, from: data) else { return nil }
        guard envelope.semesterID == semesterID else { throw CloudScheduleError.invalidResponse }
        return CloudScheduleRecord(
            semesterID: envelope.semesterID,
            syncVersion: envelope.syncVersion,
            updatedAt: envelope.updatedAt,
            snapshot: CloudScheduleSnapshot(
                format: envelope.format, semester: envelope.semester, courses: envelope.courses,
                meetings: envelope.meetings, events: envelope.events
            )
        )
    }

    /// Replaces one semester atomically. `expectedVersion` is nil only when creating it.
    func replace(
        semesterID: UUID,
        expectedVersion: Int?,
        snapshot: CloudScheduleSnapshot,
        accessToken: String
    ) async throws -> CloudWriteResult {
        struct Arguments: Encodable {
            let semesterID: UUID
            let expectedVersion: Int?
            let snapshot: CloudScheduleSnapshot

            enum CodingKeys: String, CodingKey {
                case semesterID = "p_semester_id"
                case expectedVersion = "p_expected_version"
                case snapshot = "p_snapshot"
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(semesterID, forKey: .semesterID)
                // Explicit null: PostgREST requires every named argument.
                try container.encode(expectedVersion, forKey: .expectedVersion)
                try container.encode(snapshot, forKey: .snapshot)
            }
        }
        let data = try await rpc(
            "replace_schedule_snapshot",
            body: Arguments(semesterID: semesterID, expectedVersion: expectedVersion, snapshot: snapshot),
            accessToken: accessToken
        )
        let result = try decode(CloudWriteResult.self, from: data)
        guard result.semesterID == semesterID else { throw CloudScheduleError.invalidResponse }
        return result
    }

    /// Deletes a semester only if it is still at `expectedVersion`. Returns false when it
    /// changed or no longer exists; its courses, meetings, and events cascade.
    func delete(semesterID: UUID, expectedVersion: Int, accessToken: String) async throws -> Bool {
        var request = try URLRequest.supabase(
            configuration.endpoint("rest/v1/semesters", query: [
                URLQueryItem(name: "id", value: "eq.\(semesterID.uuidString.lowercased())"),
                URLQueryItem(name: "sync_version", value: "eq.\(expectedVersion)"),
                URLQueryItem(name: "select", value: "id")
            ]),
            method: "DELETE", configuration: configuration, accessToken: accessToken
        )
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let data = try await perform(request)
        struct Deleted: Decodable { let id: UUID }
        return try decode([Deleted].self, from: data).contains { $0.id == semesterID }
    }

    private struct Envelope: Decodable {
        let format: Int
        let semesterID: UUID
        let syncVersion: Int
        let updatedAt: String
        let semester: CloudScheduleSnapshot.Semester
        let courses: [CloudScheduleSnapshot.CourseRecord]
        let meetings: [CloudScheduleSnapshot.MeetingRecord]
        let events: [CloudScheduleSnapshot.EventRecord]

        enum CodingKeys: String, CodingKey {
            case format, semester, courses, meetings, events
            case semesterID = "semester_id"
            case syncVersion = "sync_version"
            case updatedAt = "updated_at"
        }
    }

    private struct PostgRESTError: Decodable {
        let code: String?
        let message: String?
    }

    private func rpc(_ name: String, body: some Encodable, accessToken: String) async throws -> Data {
        let request = try URLRequest.supabase(
            configuration.endpoint("rest/v1/rpc/\(name)"), method: "POST",
            configuration: configuration, accessToken: accessToken, json: body
        )
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        guard request.value(forHTTPHeaderField: "Authorization")?.count ?? 0 > "Bearer ".count else {
            throw CloudScheduleError.unauthorized
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw error.isConnectivityFailure ? CloudScheduleError.offline : CloudScheduleError.server(0)
        }
        let status = response.statusCode
        if (200...299).contains(status) { return data }
        let message = (try? JSONDecoder().decode(PostgRESTError.self, from: data))?.message
        switch status {
        case 401, 403:
            throw CloudScheduleError.unauthorized
        case 409:
            switch message {
            case "schedule_exists": throw CloudScheduleError.scheduleExists
            case "schedule_missing": throw CloudScheduleError.scheduleMissing
            default: throw CloudScheduleError.versionConflict
            }
        case 400 where message == "semester_limit_reached":
            throw CloudScheduleError.semesterLimitReached
        case 400:
            throw CloudScheduleError.invalidSnapshot
        case 429:
            throw CloudScheduleError.rateLimited
        default:
            throw CloudScheduleError.server(status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CloudScheduleError.invalidResponse
        }
    }
}
