import XCTest
@testable import MaroonCompass

final class CloudSessionTests: XCTestCase {
    private func manager(_ fake: FakeSupabase, session: AuthSession?, configuration: SupabaseConfiguration = CloudFixtures.configuration)
        -> (CloudSessionManager, InMemoryAuthSessionStore) {
        let store = InMemoryAuthSessionStore(session)
        var auth = SupabaseAuthClient(configuration: configuration, transport: fake)
        auth.now = { fake.now }
        return (CloudSessionManager(auth: auth, store: store), store)
    }

    func testSessionTextNeverContainsTokens() {
        let session = AuthSession(
            accessToken: "eyJ.secret-access.token", refreshToken: "secret-refresh-token",
            expiresAt: Date(), user: AuthUser(id: UUID(), isAnonymous: false, provider: "apple")
        )
        var dumped = ""
        dump(session, to: &dumped)
        for text in ["\(session)", String(reflecting: session), dumped, "\(Mirror(reflecting: session).children.map(\.value))"] {
            XCTAssertFalse(text.contains("secret-access"), text)
            XCTAssertFalse(text.contains("secret-refresh"), text)
        }
    }

    func testConfigurationAcceptsOnlyPublishableKeysAndSafeURLs() {
        let https = URL(string: "https://abc.supabase.co")!
        let anonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        let serviceJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
        XCTAssertNotNil(SupabaseConfiguration(projectURL: https, publishableKey: "sb_publishable_abc"))
        XCTAssertNotNil(SupabaseConfiguration(projectURL: https, publishableKey: anonJWT))
        XCTAssertNil(SupabaseConfiguration(projectURL: https, publishableKey: "sb_secret_abc"), "secret keys never ship")
        XCTAssertNil(SupabaseConfiguration(projectURL: https, publishableKey: serviceJWT), "service-role keys never ship")
        XCTAssertNil(SupabaseConfiguration(projectURL: https, publishableKey: ""))
        XCTAssertNil(SupabaseConfiguration(projectURL: URL(string: "http://abc.supabase.co")!, publishableKey: "sb_publishable_abc"))
        XCTAssertNil(SupabaseConfiguration(projectURL: URL(string: "https://abc.supabase.co?x=1")!, publishableKey: "sb_publishable_abc"))
        #if DEBUG
        XCTAssertNotNil(SupabaseConfiguration(projectURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_abc"))
        #else
        XCTAssertNil(SupabaseConfiguration(projectURL: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_abc"))
        #endif
        XCTAssertEqual(CloudFixtures.configuration.endpoint("rest/v1/rpc/x").absoluteString,
                       "https://example-project.supabase.co/rest/v1/rpc/x")
    }

    func testConfigurationReadsPlistValues() {
        let configuration = SupabaseConfiguration.from([
            "ProjectURL": "https://abc.supabase.co", "PublishableKey": "sb_publishable_abc",
            "SignInWithAppleEnabled": true
        ])
        XCTAssertEqual(configuration?.signInWithAppleEnabled, true)
        XCTAssertEqual(configuration?.allowsDevelopmentSessions, false)
        XCTAssertNil(SupabaseConfiguration.from(["ProjectURL": "https://abc.supabase.co"]))
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        let fake = FakeSupabase()
        let expired = fake.session(for: fake.appleUser, lifetime: 30)
        let (sessions, store) = manager(fake, session: expired)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<6 { group.addTask { try await sessions.accessToken() } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        XCTAssertEqual(Set(tokens).count, 1, "every caller received the same refreshed token")
        XCTAssertNotEqual(tokens[0], expired.accessToken)
        XCTAssertEqual(fake.count("POST /auth/v1/token"), 1, "rotation happened exactly once")
        XCTAssertEqual(try store.load()?.accessToken, tokens[0], "the rotated session was persisted")
    }

    func testRevokedRefreshTokenSignsOutWithoutRetrying() async throws {
        let fake = FakeSupabase()
        let session = fake.session(for: fake.appleUser, lifetime: 10)
        fake.revokeAllTokens(for: fake.appleUser)
        let (sessions, store) = manager(fake, session: session)

        do {
            _ = try await sessions.accessToken()
            XCTFail("expected sessionExpired")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .sessionExpired)
        }
        let user = await sessions.currentUser()
        XCTAssertNil(user)
        XCTAssertNil(try store.load(), "an unusable session is removed from the Keychain")
    }

    func testOfflineRefreshKeepsTheSession() async throws {
        let fake = FakeSupabase()
        let session = fake.session(for: fake.appleUser, lifetime: 10)
        let (sessions, store) = manager(fake, session: session)
        fake.isOffline = true

        do {
            _ = try await sessions.accessToken()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .offline)
        }
        let user = await sessions.currentUser()
        XCTAssertEqual(user?.id, fake.appleUser)
        XCTAssertEqual(try store.load(), session)

        fake.isOffline = false
        let token = try await sessions.accessToken()
        XCTAssertNotEqual(token, session.accessToken)
    }

    func testRejectedTokenIsRefreshedOnceThenRetried() async throws {
        let fake = FakeSupabase()
        let (sessions, _) = manager(fake, session: fake.session(for: fake.appleUser))
        fake.expireAllAccessTokens()
        let repository = SupabaseScheduleRepository(configuration: CloudFixtures.configuration, transport: fake)

        let list = try await sessions.authorized { try await repository.listSemesters(accessToken: $0) }
        XCTAssertEqual(list, [])
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/list_schedule_semesters"), 2)
        XCTAssertEqual(fake.count("POST /auth/v1/token"), 1)
    }

    func testSignOutClearsTheDeviceEvenWhenOffline() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: fake.session(for: fake.appleUser))
        fake.isOffline = true
        let revoked = await sessions.signOut()
        XCTAssertFalse(revoked)
        XCTAssertNil(try store.load())
        let user = await sessions.currentUser()
        XCTAssertNil(user)
    }

    func testSignOutRevokesTheRefreshToken() async throws {
        let fake = FakeSupabase()
        let session = fake.session(for: fake.appleUser)
        let (sessions, _) = manager(fake, session: session)
        let revoked = await sessions.signOut()
        XCTAssertTrue(revoked)

        let (other, _) = manager(fake, session: AuthSession(
            accessToken: "stale", refreshToken: session.refreshToken, expiresAt: .distantPast, user: session.user
        ))
        do {
            _ = try await other.accessToken()
            XCTFail("a signed-out refresh token must not work")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .sessionExpired)
        }
    }

    func testDevelopmentSessionsNeverSurviveWhereTheyAreNotAllowed() async throws {
        let fake = FakeSupabase()
        let (debugSessions, debugStore) = manager(fake, session: nil)
        let anonymous = try await debugSessions.startDevelopmentSession()
        XCTAssertTrue(anonymous.isAnonymous)

        let releaseLike = SupabaseConfiguration(projectURL: CloudFixtures.configuration.projectURL, publishableKey: "sb_publishable_x")!
        let (releaseSessions, releaseStore) = manager(fake, session: try debugStore.load(), configuration: releaseLike)
        let restored = await releaseSessions.currentUser()
        XCTAssertNil(restored, "an anonymous session left in the Keychain is discarded")
        XCTAssertNil(try releaseStore.load())
        do {
            _ = try await releaseSessions.startDevelopmentSession()
            XCTFail("development sessions must be refused")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .developmentSessionsUnavailable)
        }
    }

    func testAppleSignInRequiresTheCapabilityFlag() async throws {
        let fake = FakeSupabase()
        let disabled = SupabaseConfiguration(projectURL: CloudFixtures.configuration.projectURL, publishableKey: "sb_publishable_x")!
        let (sessions, _) = manager(fake, session: nil, configuration: disabled)
        do {
            _ = try await sessions.signInWithApple(identityToken: "token", rawNonce: "nonce")
            XCTFail("expected appleSignInUnavailable")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .appleSignInUnavailable)
        }
        XCTAssertTrue(fake.log.isEmpty, "no request is sent")

        let (enabled, store) = manager(fake, session: nil)
        let user = try await enabled.signInWithApple(identityToken: "token", rawNonce: "nonce")
        XCTAssertEqual(user.id, fake.appleUser)
        XCTAssertEqual(try store.load()?.user.id, fake.appleUser)
    }

    func testAccountDeletionClearsTheSession() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: fake.session(for: fake.appleUser))
        try await sessions.deleteAccount()
        XCTAssertNil(try store.load())
        XCTAssertEqual(fake.count("POST /functions/v1/delete-account"), 1)
    }
}
