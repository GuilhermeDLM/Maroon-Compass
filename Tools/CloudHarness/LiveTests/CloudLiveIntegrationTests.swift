import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import MaroonCompass

/// Runs the app's real cloud code (URLSession transport, Auth client, session manager,
/// repository, sync coordinator, and account model) against a real Supabase stack.
///
/// Only a local `supabase start` stack or a disposable development project is allowed: the
/// tests create users with an admin key and delete them. Password identities stand in for a returning Google user;
/// every code path after the token grant is the same.
final class CloudLiveIntegrationTests: XCTestCase {
    private struct Live {
        let configuration: SupabaseConfiguration
        let adminKey: String
    }

    @MainActor
    private func live() throws -> Live {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["MC_LIVE_SUPABASE_URL"], let url = URL(string: rawURL),
              let key = environment["MC_LIVE_PUBLISHABLE_KEY"], let admin = environment["MC_LIVE_SECRET_KEY"] else {
            throw XCTSkip("Set MC_LIVE_SUPABASE_URL, MC_LIVE_PUBLISHABLE_KEY, and MC_LIVE_SECRET_KEY to run live tests.")
        }
        // The tests create and delete users with an admin key. Only a local CLI stack, or a
        // hosted project explicitly declared disposable, may be used.
        let isLocal = ["127.0.0.1", "localhost"].contains(url.host ?? "")
        guard isLocal || environment["MC_LIVE_DISPOSABLE_PROJECT"] == "yes" else {
            throw XCTSkip("Live tests run only against a local stack or a disposable project (MC_LIVE_DISPOSABLE_PROJECT=yes).")
        }
        let configuration = try XCTUnwrap(SupabaseConfiguration(
            projectURL: url, publishableKey: key, allowsDevelopmentSessions: true
        ))
        return Live(configuration: configuration, adminKey: admin)
    }

    // MARK: - Test identities (local admin API only)

    private struct Identity {
        let id: UUID
        let email: String
        let password: String
    }

    @MainActor
    private func request(_ live: Live, _ path: String, method: String, key: String, bearer: String? = nil,
                         query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> (Int, Any?) {
        var request = URLRequest(url: live.configuration.endpoint(path, query: query))
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSessionTransport().send(request)
        return (response.statusCode, data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
    }

    @MainActor
    private func createIdentity(_ live: Live) async throws -> Identity {
        let email = "maroon-live-\(UUID().uuidString.lowercased())@example.invalid"
        let password = "Live-\(UUID().uuidString)-Aa1"
        let (status, body) = try await request(
            live, "auth/v1/admin/users", method: "POST", key: live.adminKey, bearer: live.adminKey,
            body: ["email": email, "password": password, "email_confirm": true]
        )
        XCTAssertEqual(status, 200)
        let id = try XCTUnwrap(((body as? [String: Any])?["id"] as? String).flatMap(UUID.init(uuidString:)))
        return Identity(id: id, email: email, password: password)
    }

    /// A fresh sign-in, as when the same account signs in on another device.
    @MainActor
    private func signIn(_ live: Live, _ identity: Identity) async throws -> AuthSession {
        let (status, body) = try await request(
            live, "auth/v1/token", method: "POST", key: live.configuration.publishableKey,
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: ["email": identity.email, "password": identity.password]
        )
        XCTAssertEqual(status, 200)
        let json = try XCTUnwrap(body as? [String: Any])
        return AuthSession(
            accessToken: try XCTUnwrap(json["access_token"] as? String),
            refreshToken: try XCTUnwrap(json["refresh_token"] as? String),
            expiresAt: Date(timeIntervalSince1970: try XCTUnwrap(json["expires_at"] as? Double)),
            user: AuthUser(id: identity.id, isAnonymous: false, provider: "email")
        )
    }

    /// Rows the account still owns, read with the admin key (bypasses RLS).
    @MainActor
    private func ownedRowCount(_ live: Live, _ user: UUID) async throws -> Int {
        var total = 0
        for table in ["semesters", "courses", "course_meetings", "course_events"] {
            let (status, body) = try await request(
                live, "rest/v1/\(table)", method: "GET", key: live.adminKey, bearer: live.adminKey,
                query: [URLQueryItem(name: "user_id", value: "eq.\(user.uuidString.lowercased())"),
                        URLQueryItem(name: "select", value: "id")]
            )
            XCTAssertEqual(status, 200, table)
            total += (body as? [Any])?.count ?? 0
        }
        return total
    }

    @MainActor
    private func device(_ live: Live, session: AuthSession?, local: ImportedScheduleBundle? = nil,
                        transport: any HTTPTransport = URLSessionTransport()) -> SimulatedDevice {
        SimulatedDevice(server: transport, configuration: live.configuration, local: local, session: session)
    }

    // MARK: - Tests

    @MainActor
    func testRealServerRoundTripsEverySupportedScheduleShapeWithoutLoss() async throws {
        let live = try live()
        let (icsBundle, _) = try ICSImportService().parse(data: Data(CloudFixtures.icsCalendar.utf8), sourceName: "howdy.ics")
        let shapes: [(String, ImportedScheduleBundle, Bool)] = [
            ("embedded Howdy schedule", CloudFixtures.embeddedBundle, true),
            (".ics import", icsBundle, false),
            ("reviewed photo import", CloudFixtures.reviewedPhotoBundle(), false)
        ]
        for (name, bundle, isEmbedded) in shapes {
            let identity = try await createIdentity(live)
            let phone = device(live, session: try await signIn(live, identity), local: isEmbedded ? nil : bundle)
            let user = AuthUser(id: identity.id, isAnonymous: false, provider: nil)
            guard case .upToDate(let summary) = try await phone.sync.uploadLocalChanges(for: user).state else {
                return XCTFail("\(name): upload did not complete")
            }
            let token = try await phone.services.sessions.accessToken()
            let fetched = try await phone.services.repository.fetch(semesterID: summary.semesterID, accessToken: token)
            let record = try XCTUnwrap(fetched)
            let local = try CloudScheduleSnapshot(bundle: bundle, fallbackTerm: ScheduleSeed.term, isEmbedded: isEmbedded)
            XCTAssertEqual(record.snapshot, local, "\(name): the server returned exactly what was uploaded")
            let restored = try record.snapshot.makeBundle(restoredAt: Date())
            XCTAssertEqual(restored.courses, bundle.courses, name)
            XCTAssertEqual(restored.patterns.map(\.id), bundle.patterns.map(\.id), name)
            XCTAssertEqual(restored.patterns.map(\.excludedDates), bundle.patterns.map(\.excludedDates), name)
            XCTAssertEqual(restored.patterns.map(\.additionalDates), bundle.patterns.map(\.additionalDates), name)
            XCTAssertEqual(restored.patterns.map(\.sourceNotes), bundle.patterns.map(\.sourceNotes), name)
            XCTAssertEqual(restored.oneTimeEvents, bundle.oneTimeEvents, name)
            XCTAssertEqual(restored.term, bundle.term ?? ScheduleSeed.term, name)
        }
    }

    @MainActor
    func testReturningAccountSecondDeviceConflictsAndIsolation() async throws {
        let live = try live()
        let alice = try await createIdentity(live)
        let aliceUser = AuthUser(id: alice.id, isAnonymous: false, provider: nil)

        // Phone: first backup of the embedded schedule.
        let phone = device(live, session: try await signIn(live, alice))
        let value1 = try await phone.sync.refresh(for: aliceUser).state
        XCTAssertEqual(value1, .noCloudCopy)
        guard case .upToDate(let v1) = try await phone.sync.uploadLocalChanges(for: aliceUser).state else {
            return XCTFail("first backup failed")
        }
        XCTAssertEqual(v1.syncVersion, 1)

        // iPad: same account signs in again; identical schedule links without a write.
        let ipad = device(live, session: try await signIn(live, alice))
        guard case .upToDate(let linked) = try await ipad.sync.refresh(for: aliceUser).state else {
            return XCTFail("second device did not link")
        }
        XCTAssertEqual(linked.semesterID, v1.semesterID)

        // iPad imports a different schedule and replaces the cloud copy explicitly.
        ipad.local.imported = CloudFixtures.reviewedPhotoBundle()
        guard case .localChanges = try await ipad.sync.refresh(for: aliceUser).state else {
            return XCTFail("iPad change not detected")
        }
        guard case .upToDate(let v2) = try await ipad.sync.uploadLocalChanges(for: aliceUser).state else {
            return XCTFail("iPad upload failed")
        }
        XCTAssertEqual(v2.syncVersion, 2)

        // Phone sees a remote change, restores it, and can undo.
        guard case .remoteChanges(let remote) = try await phone.sync.refresh(for: aliceUser).state else {
            return XCTFail("phone did not see the remote change")
        }
        XCTAssertNil(phone.local.imported, "nothing changes before the user restores")
        _ = try await phone.sync.restore(remote, for: aliceUser)
        XCTAssertEqual(phone.local.imported?.courses, CloudFixtures.reviewedPhotoBundle().courses)
        XCTAssertTrue(phone.sync.canUndoRestore)

        // Both change: conflict, a stale review is rejected, an explicit current replace wins.
        phone.local.imported = CloudFixtures.reviewedPhotoBundle(title: "Phone edit")
        ipad.local.imported = CloudFixtures.reviewedPhotoBundle(room: "IPAD")
        _ = try await ipad.sync.uploadLocalChanges(for: aliceUser)
        guard case .conflict(let conflict) = try await phone.sync.refresh(for: aliceUser).state else {
            return XCTFail("expected a conflict")
        }
        do {
            _ = try await phone.sync.replaceCloudCopy(v2, for: aliceUser)
            XCTFail("a stale reviewed version must not overwrite")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .changedElsewhere)
        }
        guard case .upToDate(let v4) = try await phone.sync.replaceCloudCopy(conflict, for: aliceUser).state else {
            return XCTFail("explicit replace failed")
        }
        XCTAssertEqual(v4.syncVersion, 4)

        // Another account sees and changes nothing of Alice's.
        let bob = try await createIdentity(live)
        let bobDevice = device(live, session: try await signIn(live, bob))
        let bobToken = try await bobDevice.services.sessions.accessToken()
        let repository = bobDevice.services.repository
        let bobList = try await repository.listSemesters(accessToken: bobToken)
        XCTAssertEqual(bobList, [])
        let stolen = try await repository.fetch(semesterID: v4.semesterID, accessToken: bobToken)
        XCTAssertNil(stolen)
        let snapshot = try CloudScheduleSnapshot(bundle: CloudFixtures.embeddedBundle, fallbackTerm: ScheduleSeed.term, isEmbedded: true)
        do {
            _ = try await repository.replace(semesterID: v4.semesterID, expectedVersion: nil, snapshot: snapshot, accessToken: bobToken)
            XCTFail("Bob cannot create a row with Alice's semester ID")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .scheduleExists)
        }
        do {
            _ = try await repository.replace(semesterID: v4.semesterID, expectedVersion: 4, snapshot: snapshot, accessToken: bobToken)
            XCTFail("Bob cannot overwrite Alice's semester")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .scheduleMissing)
        }
        let deleted = try await repository.delete(semesterID: v4.semesterID, expectedVersion: 4, accessToken: bobToken)
        XCTAssertFalse(deleted)
        let aliceToken = try await phone.services.sessions.accessToken()
        let aliceRecord = try await phone.services.repository.fetch(semesterID: v4.semesterID, accessToken: aliceToken)
        XCTAssertEqual(aliceRecord?.syncVersion, 4)
        XCTAssertEqual(aliceRecord?.snapshot.courses.first?.title, "Phone edit")
    }

    @MainActor
    func testTokenExpiryRejectionSignOutAndAccountDeletion() async throws {
        let live = try live()
        let carol = try await createIdentity(live)
        let fresh = try await signIn(live, carol)

        // Locally expired access token: refreshed through the real Auth server before use.
        let expired = AuthSession(accessToken: fresh.accessToken, refreshToken: fresh.refreshToken,
                                  expiresAt: Date(timeIntervalSinceNow: -60), user: fresh.user)
        let phone = device(live, session: expired, local: CloudFixtures.reviewedPhotoBundle())
        let renewed = try await phone.services.sessions.accessToken()
        XCTAssertNotEqual(renewed, fresh.accessToken)
        XCTAssertNotEqual(try phone.sessionStore.load()?.refreshToken, fresh.refreshToken, "rotation persisted")

        // A token the server rejects (bad signature) is refreshed once and the call retried.
        let second = try await signIn(live, carol)
        let tampered = AuthSession(accessToken: second.accessToken + "x", refreshToken: second.refreshToken,
                                   expiresAt: Date(timeIntervalSinceNow: 3_000), user: second.user)
        let ipad = device(live, session: tampered)
        let carolUser = AuthUser(id: carol.id, isAnonymous: false, provider: nil)
        let value2 = try await ipad.sync.refresh(for: carolUser).state
        XCTAssertEqual(value2, .noCloudCopy)

        guard case .upToDate = try await phone.sync.uploadLocalChanges(for: carolUser).state else {
            return XCTFail("upload failed")
        }
        let value3 = try await ownedRowCount(live, carol.id)
        XCTAssertGreaterThan(value3, 0)

        // Sign-out revokes this device's refresh token on the server.
        let phoneSession = try XCTUnwrap(try phone.sessionStore.load())
        let revoked = await phone.services.sessions.signOut()
        XCTAssertTrue(revoked)
        XCTAssertNil(try phone.sessionStore.load())
        let replay = device(live, session: AuthSession(accessToken: phoneSession.accessToken,
                                                        refreshToken: phoneSession.refreshToken,
                                                        expiresAt: .distantPast, user: phoneSession.user))
        do {
            _ = try await replay.services.sessions.accessToken()
            XCTFail("a signed-out refresh token must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .sessionExpired)
        }

        // Account deletion from the iPad removes the Auth user and every schedule row.
        let ipadSession = try XCTUnwrap(try ipad.sessionStore.load())
        let model = ipad.makeModel()
        await model.load()
        await model.deleteAccount()
        XCTAssertEqual(model.account, .signedOut)
        XCTAssertNotEqual(model.notice?.isError, true, model.notice?.message ?? "")
        let value4 = try await ownedRowCount(live, carol.id)
        XCTAssertEqual(value4, 0)
        XCTAssertNil(try ipad.sessionStore.load())

        // The deleted account's still-unexpired access token cannot write, and the app signs out.
        let ghost = device(live, session: ipadSession, local: CloudFixtures.reviewedPhotoBundle())
        do {
            _ = try await ghost.sync.uploadLocalChanges(for: carolUser)
            XCTFail("a deleted account must not write")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .sessionExpired)
        }
        XCTAssertNil(try ghost.sessionStore.load())
        let value5 = try await ownedRowCount(live, carol.id)
        XCTAssertEqual(value5, 0)
    }

    @MainActor
    func testOfflineUploadRetriesAndDevelopmentSessions() async throws {
        let live = try live()
        let transport = SwitchableTransport()
        let dan = try await createIdentity(live)
        let danUser = AuthUser(id: dan.id, isAnonymous: false, provider: nil)
        let phone = device(live, session: try await signIn(live, dan), local: CloudFixtures.reviewedPhotoBundle(), transport: transport)
        let value6 = try await phone.sync.refresh(for: danUser).state
        XCTAssertEqual(value6, .noCloudCopy)

        transport.isOffline = true
        do {
            _ = try await phone.sync.uploadLocalChanges(for: danUser)
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .offline)
        }
        XCTAssertEqual(phone.stateStore.state.pendingUploadUserID, dan.id)
        let signedIn = await phone.services.sessions.currentUser()
        XCTAssertEqual(signedIn?.id, dan.id, "going offline does not sign out")

        transport.isOffline = false
        guard case .upToDate = try await phone.sync.refresh(for: danUser).state else {
            return XCTFail("the pending upload was not retried")
        }
        XCTAssertNil(phone.stateStore.state.pendingUploadUserID)

        // Debug development session: anonymous, labeled, and usable only for development.
        let dev = device(live, session: nil)
        let model = dev.makeModel()
        await model.load()
        XCTAssertEqual(model.account, .signedOut)
        await model.startDevelopmentSession()
        guard case .signedIn(let anonymous) = model.account else { return XCTFail("no development session") }
        XCTAssertTrue(anonymous.isAnonymous)
        XCTAssertEqual(model.overview?.state, .noCloudCopy)
        await model.uploadLocalChanges()
        guard case .upToDate = model.overview?.state else { return XCTFail("development upload failed") }
        await model.deleteAccount()
        let value7 = try await ownedRowCount(live, anonymous.id)
        XCTAssertEqual(value7, 0)
    }
}

extension CloudLiveIntegrationTests {
    /// Status and Location of a request without following redirects.
    @MainActor
    private func redirect(_ request: URLRequest) async throws -> (Int, String?) {
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, http.value(forHTTPHeaderField: "Location"))
    }

    /// The app's Google authorize URL, sent to real Supabase Auth, must lead to Google's consent
    /// screen asking only for identity scopes. Google itself is not contacted beyond discovery.
    @MainActor
    func testGoogleAuthorizeURLLeadsToGoogleWithIdentityScopesOnly() async throws {
        let live = try live()
        let client = SupabaseAuthClient(configuration: live.configuration, transport: URLSessionTransport())
        let request = client.makeGoogleSignInRequest()
        let (status, location) = try await redirect(URLRequest(url: request.authorizeURL))
        guard (300...399).contains(status), let location, let google = URLComponents(string: location) else {
            throw XCTSkip("Supabase Auth did not redirect to Google (HTTP \(status)); enable [auth.external.google] and allow Auth to reach accounts.google.com.")
        }
        XCTAssertEqual(google.host, "accounts.google.com")
        let query = Dictionary((google.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        // Form encoding: spaces arrive as "+". Supabase adds its default "email profile" to ours.
        let scopes = Set((query["scope"] ?? "").split(whereSeparator: { $0 == " " || $0 == "+" }).map(String.init))
        XCTAssertEqual(scopes, ["openid", "email", "profile"])
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], live.configuration.endpoint("auth/v1/callback").absoluteString)
        XCTAssertNotNil(query["state"], "Supabase Auth keeps the PKCE flow state server-side")
        XCTAssertFalse(location.contains(request.codeVerifier))
    }

    /// Everything after Google: Supabase Auth redirects to the app's callback with a one-time
    /// code, and the app exchanges it with its PKCE verifier. The magic-link PKCE flow ends in
    /// the same callback and exchange, so it stands in for Google's consent step.
    @MainActor
    func testCallbackCodeExchangeAgainstRealAuth() async throws {
        let live = try live()
        guard let mailpit = ProcessInfo.processInfo.environment["MC_LIVE_MAILPIT_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("Set MC_LIVE_MAILPIT_URL (for example http://127.0.0.1:54324) to test the PKCE callback exchange.")
        }
        let email = "maroon-pkce-\(UUID().uuidString.lowercased())@example.invalid"
        let phone = device(live, session: nil, local: CloudFixtures.reviewedPhotoBundle())
        let signIn = phone.services.sessions.makeGoogleSignInRequest()
        let challenge = PKCE.challenge(for: signIn.codeVerifier)

        let (otpStatus, _) = try await request(
            live, "auth/v1/otp", method: "POST", key: live.configuration.publishableKey,
            query: [URLQueryItem(name: "redirect_to", value: OAuthSignInRequest.redirectURL.absoluteString)],
            body: ["email": email, "create_user": true, "code_challenge": challenge, "code_challenge_method": "s256"]
        )
        XCTAssertEqual(otpStatus, 200)

        var link: URL?
        for _ in 0..<20 where link == nil {
            var search = URLComponents(url: mailpit.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)!
            search.queryItems = [URLQueryItem(name: "query", value: "to:\(email)")]
            let (listData, _) = try await URLSessionTransport().send(URLRequest(url: search.url!))
            if let id = ((try JSONSerialization.jsonObject(with: listData) as? [String: Any])?["messages"] as? [[String: Any]])?.first?["ID"] as? String {
                let (messageData, _) = try await URLSessionTransport().send(URLRequest(url: mailpit.appendingPathComponent("api/v1/message/\(id)")))
                let message = try JSONSerialization.jsonObject(with: messageData) as? [String: Any]
                let text = (message?["Text"] as? String ?? "") + (message?["HTML"] as? String ?? "")
                if let range = text.range(of: #"https?://[^\s"<>]+/auth/v1/verify\?[^\s"<>]+"#, options: .regularExpression) {
                    link = URL(string: String(text[range]).replacingOccurrences(of: "&amp;", with: "&"))
                }
            } else {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let verifyURL = try XCTUnwrap(link, "no magic-link email arrived")
        let (status, location) = try await redirect(URLRequest(url: verifyURL))
        XCTAssertTrue((300...399).contains(status))
        let callback = try XCTUnwrap(location.flatMap(URL.init(string:)))
        XCTAssertEqual(callback.scheme, "marooncompass", "Auth accepted the allow-listed app callback")
        XCTAssertEqual(callback.host, "auth")
        XCTAssertEqual(callback.path, "/callback")

        // An intercepted code is useless without this attempt's verifier.
        let other = phone.services.sessions.makeGoogleSignInRequest()
        do {
            _ = try await phone.services.sessions.completeGoogleSignIn(callbackURL: callback, request: other)
            XCTFail("a different verifier must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .signInRejected)
        }

        let user = try await phone.services.sessions.completeGoogleSignIn(callbackURL: callback, request: signIn)
        XCTAssertFalse(user.isAnonymous)
        XCTAssertNotNil(try phone.sessionStore.load(), "the session is stored after the exchange")
        guard case .upToDate = try await phone.sync.uploadLocalChanges(for: user).state else {
            return XCTFail("the exchanged session cannot back up")
        }

        do {
            _ = try await phone.services.sessions.completeGoogleSignIn(callbackURL: callback, request: signIn)
            XCTFail("a code is single-use")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .signInRejected)
        }

        let model = phone.makeModel()
        await model.load()
        await model.deleteAccount()
        let remaining = try await ownedRowCount(live, user.id)
        XCTAssertEqual(remaining, 0)
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Wraps the real transport with an offline switch.
private final class SwitchableTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    private let base = URLSessionTransport()

    var isOffline: Bool {
        get { lock.withLock { offline } }
        set { lock.withLock { offline = newValue } }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if isOffline { throw URLError(.notConnectedToInternet) }
        return try await base.send(request)
    }
}
