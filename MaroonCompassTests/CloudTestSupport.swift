import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MaroonCompass

enum CloudFixtures {
    static let configuration = SupabaseConfiguration(
        projectURL: URL(string: "https://example-project.supabase.co")!,
        publishableKey: "sb_publishable_test-key",
        allowsDevelopmentSessions: true,
        signInWithAppleEnabled: true
    )!

    /// The verified schedule bundled with the app, as the sync layer sees it.
    static var embeddedBundle: ImportedScheduleBundle {
        ImportedScheduleBundle(
            sourceName: ScheduleSeed.sourceName,
            importedAt: Date(timeIntervalSince1970: 0),
            term: ScheduleSeed.term,
            courses: ScheduleSeed.courses,
            patterns: ScheduleSeed.patterns,
            oneTimeEvents: ScheduleSeed.oneTimeEvents
        )
    }

    /// Shaped like `ScheduleDraft.confirmedBundle`: UUID identifiers, no Howdy metadata.
    static func reviewedPhotoBundle(title: String = "Engineering Mathematics III", room: String = "169") -> ImportedScheduleBundle {
        let courseID = "6F1C3A55-2B7E-4B0C-9F7A-6A3D1E2C4B5A"
        return ImportedScheduleBundle(
            sourceName: "Reviewed photo import",
            importedAt: Date(timeIntervalSince1970: 1_790_000_000.123_4),
            term: Term(
                institution: "Texas A&M University", campus: "College Station", name: "Fall 2026",
                firstClassDate: "2026-08-24", lastClassDate: "2026-12-03",
                finalsStartDate: nil, finalsEndDate: nil, timeZoneIdentifier: "America/Chicago"
            ),
            courses: [Course(
                id: courseID, code: "MATH 251", section: "502", title: title, credits: 0,
                catalogSummary: "", colorHex: "5E2E42", symbol: "book.closed.fill"
            )],
            patterns: [
                MeetingPattern(
                    id: "0B7D4C1E-9A2F-4E3B-8C6D-5F4A3B2C1D0E", courseID: courseID,
                    weekdays: [.tuesday, .thursday], startHour: 17, startMinute: 30, endHour: 18, endMinute: 45,
                    sourceUntilUTC: "", sourceLocationText: "BLOC · \(room)", meetingKind: .lecture,
                    buildingCode: "BLOC", room: room
                ),
                MeetingPattern(
                    id: "1C8E5D2F-0B3A-4F4C-9D7E-6A5B4C3D2E1F", courseID: courseID,
                    weekdays: [.friday], startHour: 9, startMinute: 10, endHour: 10, endMinute: 0,
                    sourceUntilUTC: "", meetingKind: .recitation
                )
            ],
            oneTimeEvents: []
        )
    }

    /// A Howdy-style calendar with TZID times, a UTC UNTIL, EXDATE, RDATE, a one-time event,
    /// notes, locations, and an unknown property kept only as a private diagnostic.
    static let icsCalendar = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Maroon Compass Tests//EN
    BEGIN:VEVENT
    UID:howdy-11953-weekly
    SUMMARY:MATH-251-502
    DTSTART;TZID=America/Chicago:20260824T173000
    DTEND;TZID=America/Chicago:20260824T184500
    RRULE:FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=20261211T004500Z
    EXDATE;TZID=America/Chicago:20261126T173000,20260908T173000
    RDATE;TZID=America/Chicago:20261204T173000
    LOCATION:BLOC · 169
    DESCRIPTION:Instructor: Yang\\, Yuxuan
    X-HOWDY-TERM:202631
    END:VEVENT
    BEGIN:VEVENT
    UID:special-chem-review@example.invalid
    SUMMARY:CHEM-107-504
    DTSTART;TZID=America/Chicago:20261119T190000
    DTEND;TZID=America/Chicago:20261119T203000
    LOCATION:ILCB · 111
    END:VEVENT
    END:VCALENDAR
    """
}

/// The app's single local schedule, in memory.
@MainActor
final class InMemoryLocalSchedule: LocalScheduleAccess {
    /// nil means the embedded schedule is active.
    var imported: ImportedScheduleBundle?

    init(_ imported: ImportedScheduleBundle? = nil) { self.imported = imported }

    func currentSchedule() -> (bundle: ImportedScheduleBundle, isEmbedded: Bool) {
        if let imported { return (imported, false) }
        return (CloudFixtures.embeddedBundle, true)
    }

    func makeBackup() -> LocalScheduleBackup {
        guard let imported, let data = try? JSONEncoder().encode(imported) else { return .embedded }
        return .imported(data)
    }

    func replaceSchedule(with bundle: ImportedScheduleBundle) throws { imported = bundle }

    func restore(_ backup: LocalScheduleBackup) throws {
        switch backup {
        case .embedded: imported = nil
        case .imported(let data): imported = try JSONDecoder().decode(ImportedScheduleBundle.self, from: data)
        }
    }
}

/// An in-process stand-in for Supabase Auth, the schedule RPCs, and the delete-account
/// function, following the same ownership and version rules as the SQL migration. Live tests
/// cover the real server; this fake makes failures (offline, lost responses, token expiry)
/// deterministic.
final class FakeSupabase: HTTPTransport, @unchecked Sendable {
    struct Row {
        var userID: UUID
        var version: Int
        var updatedAt: String
        var snapshot: CloudScheduleSnapshot
    }

    private let lock = NSLock()
    private var rows: [UUID: Row] = [:]
    private var accessTokens: [String: (user: UUID, expires: Date)] = [:]
    private var refreshTokens: [String: UUID] = [:]
    private var anonymousUsers: Set<UUID> = []
    private var deletedUsers: Set<UUID> = []
    private var tokenCounter = 0
    private var _now = Date(timeIntervalSince1970: 1_790_000_000)
    private var _offline = false
    private var _dropNextResponse = false
    private var _log: [String] = []

    let appleUser = UUID(uuidString: "A0000000-0000-0000-0000-00000000A001")!

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }
    var isOffline: Bool {
        get { lock.withLock { _offline } }
        set { lock.withLock { _offline = newValue } }
    }
    /// Applies the next schedule write, then fails as if its response was lost in transit.
    var dropNextWriteResponse: Bool {
        get { lock.withLock { _dropNextResponse } }
        set { lock.withLock { _dropNextResponse = newValue } }
    }
    /// "METHOD path" per request; never contains tokens or bodies.
    var log: [String] { lock.withLock { _log } }
    func count(_ entry: String) -> Int { log.filter { $0 == entry }.count }

    var semesterCount: Int { lock.withLock { rows.count } }
    func row(_ id: UUID) -> Row? { lock.withLock { rows[id] } }

    /// A session as if the user had signed in on a device.
    func session(for user: UUID, lifetime: TimeInterval = 3_600) -> AuthSession {
        lock.withLock { issue(for: user, lifetime: lifetime) }
    }

    func expireAllAccessTokens() {
        lock.withLock { accessTokens = accessTokens.mapValues { ($0.user, Date.distantPast) } }
    }

    func revokeAllTokens(for user: UUID) {
        lock.withLock {
            accessTokens = accessTokens.filter { $0.value.user != user }
            refreshTokens = refreshTokens.filter { $0.value != user }
        }
    }

    /// Simulates another device writing directly on the server.
    func serverWrite(_ id: UUID, user: UUID, snapshot: CloudScheduleSnapshot) {
        lock.withLock {
            let version = (rows[id]?.version ?? 0) + 1
            rows[id] = Row(userID: user, version: version, updatedAt: CloudFormat.timestamp(_now), snapshot: snapshot)
        }
    }

    func serverDelete(_ id: UUID) {
        _ = lock.withLock { rows.removeValue(forKey: id) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body, drop) = try lock.withLock { () throws -> (Int, Any, Bool) in
            let path = request.url!.path
            _log.append("\(request.httpMethod ?? "GET") \(path)")
            if _offline { throw URLError(.notConnectedToInternet) }
            let result = handle(request, path: path)
            let drop = _dropNextResponse && path.hasSuffix("/replace_schedule_snapshot")
            if drop { _dropNextResponse = false }
            return (result.0, result.1, drop)
        }
        if drop { throw URLError(.networkConnectionLost) }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }

    // MARK: - Request handling (called with the lock held)

    private func handle(_ request: URLRequest, path: String) -> (Int, Any) {
        let json = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch path {
        case "/auth/v1/token" where queryValue("grant_type") == "id_token":
            return (200, sessionJSON(issue(for: appleUser, lifetime: 3_600), provider: "apple"))
        case "/auth/v1/token" where queryValue("grant_type") == "refresh_token":
            guard let token = json["refresh_token"] as? String, let user = refreshTokens.removeValue(forKey: token),
                  !deletedUsers.contains(user) else {
                return (400, ["error_code": "refresh_token_not_found"])
            }
            return (200, sessionJSON(issue(for: user, lifetime: 3_600), provider: "apple"))
        case "/auth/v1/signup":
            let user = UUID()
            anonymousUsers.insert(user)
            return (200, sessionJSON(issue(for: user, lifetime: 3_600), provider: "anonymous"))
        case "/auth/v1/logout":
            guard let user = authorizedUser(request) else { return (401, [:]) }
            refreshTokens = refreshTokens.filter { $0.value != user }
            return (204, NSNull())
        case "/functions/v1/delete-account":
            guard let user = authorizedUser(request) else { return (401, ["error": "invalid_session"]) }
            guard json["confirmation"] as? String == SupabaseAuthClient.deletionConfirmation else {
                return (400, ["error": "confirmation_required"])
            }
            deletedUsers.insert(user)
            rows = rows.filter { $0.value.userID != user }
            accessTokens = accessTokens.filter { $0.value.user != user }
            refreshTokens = refreshTokens.filter { $0.value != user }
            return (200, ["deleted": true])
        case "/rest/v1/rpc/list_schedule_semesters":
            guard let user = authorizedUser(request) else { return (401, [:]) }
            let list = rows.filter { $0.value.userID == user }
                .sorted { $0.value.snapshot.semester.firstClassDate > $1.value.snapshot.semester.firstClassDate }
                .map { id, row -> [String: Any] in
                    ["semester_id": id.uuidString.lowercased(), "name": row.snapshot.semester.name,
                     "first_class_date": row.snapshot.semester.firstClassDate,
                     "last_class_date": row.snapshot.semester.lastClassDate,
                     "sync_version": row.version, "updated_at": row.updatedAt,
                     "course_count": row.snapshot.courses.count]
                }
            return (200, list)
        case "/rest/v1/rpc/get_schedule_snapshot":
            guard let user = authorizedUser(request) else { return (401, [:]) }
            guard let id = (json["p_semester_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let row = rows[id], row.userID == user else { return (200, NSNull()) }
            var envelope = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(row.snapshot))) as? [String: Any] ?? [:]
            envelope["semester_id"] = id.uuidString.lowercased()
            envelope["sync_version"] = row.version
            envelope["updated_at"] = row.updatedAt
            return (200, envelope)
        case "/rest/v1/rpc/replace_schedule_snapshot":
            guard let user = authorizedUser(request) else { return (401, [:]) }
            guard let id = (json["p_semester_id"] as? String).flatMap(UUID.init(uuidString:)),
                  let raw = json["p_snapshot"],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let snapshot = try? JSONDecoder().decode(CloudScheduleSnapshot.self, from: data) else {
                return (400, ["code": "22023", "message": "invalid_snapshot"])
            }
            let expected = json["p_expected_version"] as? Int
            let version: Int
            if let row = rows[id], row.userID == user {
                guard expected == row.version else { return conflict("schedule_version_conflict") }
                version = row.version + 1
            } else {
                guard expected == nil else { return conflict("schedule_missing") }
                guard rows[id] == nil,
                      !rows.values.contains(where: { $0.userID == user && $0.snapshot.semester.firstClassDate == snapshot.semester.firstClassDate }) else {
                    return conflict("schedule_exists")
                }
                version = 1
            }
            let updatedAt = CloudFormat.timestamp(_now)
            rows[id] = Row(userID: user, version: version, updatedAt: updatedAt, snapshot: snapshot)
            return (200, ["semester_id": id.uuidString.lowercased(), "sync_version": version, "updated_at": updatedAt])
        case "/rest/v1/semesters" where request.httpMethod == "DELETE":
            guard let user = authorizedUser(request) else { return (401, [:]) }
            guard let id = queryValue("id").map({ String($0.dropFirst(3)) }).flatMap(UUID.init(uuidString:)),
                  let version = queryValue("sync_version").map({ String($0.dropFirst(3)) }).flatMap(Int.init),
                  let row = rows[id], row.userID == user, row.version == version else { return (200, [Any]()) }
            rows[id] = nil
            return (200, [["id": id.uuidString.lowercased()]])
        default:
            return (404, [:])
        }
    }

    private func conflict(_ message: String) -> (Int, Any) {
        (409, ["code": "PT409", "message": message])
    }

    private func authorizedUser(_ request: URLRequest) -> UUID? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer "),
              let entry = accessTokens[String(header.dropFirst(7))],
              entry.expires > _now, !deletedUsers.contains(entry.user) else { return nil }
        return entry.user
    }

    private func issue(for user: UUID, lifetime: TimeInterval) -> AuthSession {
        tokenCounter += 1
        let access = "access-\(tokenCounter)"
        let refresh = "refresh-\(tokenCounter)"
        let expires = _now.addingTimeInterval(lifetime)
        accessTokens[access] = (user, expires)
        refreshTokens[refresh] = user
        return AuthSession(
            accessToken: access, refreshToken: refresh, expiresAt: expires,
            user: AuthUser(id: user, isAnonymous: anonymousUsers.contains(user), provider: nil)
        )
    }

    private func sessionJSON(_ session: AuthSession, provider: String) -> [String: Any] {
        [
            "access_token": session.accessToken,
            "refresh_token": session.refreshToken,
            "token_type": "bearer",
            "expires_in": 3_600,
            "expires_at": Int(session.expiresAt.timeIntervalSince1970),
            "user": [
                "id": session.user.id.uuidString.lowercased(),
                "is_anonymous": session.user.isAnonymous,
                "app_metadata": ["provider": session.user.isAnonymous ? "anonymous" : provider]
            ] as [String: Any]
        ]
    }
}

/// One simulated device: its own Keychain, sync metadata, and local schedule, sharing a server.
@MainActor
struct SimulatedDevice {
    let services: CloudServices
    let local: InMemoryLocalSchedule
    let stateStore: InMemoryCloudSyncStateStore
    let sessionStore: InMemoryAuthSessionStore
    let sync: CloudScheduleSync

    init(
        server: any HTTPTransport,
        configuration: SupabaseConfiguration = CloudFixtures.configuration,
        local: ImportedScheduleBundle? = nil,
        session: AuthSession? = nil,
        clock: (@Sendable () -> Date)? = nil
    ) {
        sessionStore = InMemoryAuthSessionStore(session)
        var services = CloudServices(configuration: configuration, transport: server, sessionStore: sessionStore)
        if let clock {
            var auth = SupabaseAuthClient(configuration: configuration, transport: server)
            auth.now = clock
            services = CloudServices(
                configuration: configuration,
                sessions: CloudSessionManager(auth: auth, store: sessionStore),
                repository: SupabaseScheduleRepository(configuration: configuration, transport: server)
            )
        }
        self.services = services
        self.local = InMemoryLocalSchedule(local)
        stateStore = InMemoryCloudSyncStateStore()
        sync = CloudScheduleSync(
            sessions: services.sessions, repository: services.repository,
            local: self.local, store: stateStore
        )
    }

    /// A device whose Auth client shares the fake server's clock, so token expiry is exact.
    init(fake: FakeSupabase, local: ImportedScheduleBundle? = nil, session: AuthSession? = nil,
         configuration: SupabaseConfiguration = CloudFixtures.configuration) {
        self.init(server: fake, configuration: configuration, local: local, session: session, clock: { fake.now })
    }

    func makeModel() -> CloudAccountModel {
        CloudAccountModel(services: services, local: local, stateStore: stateStore)
    }
}
