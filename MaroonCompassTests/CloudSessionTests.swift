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
            expiresAt: Date(), user: AuthUser(id: UUID(), isAnonymous: false, provider: "google")
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
            "ProjectURL": "https://abc.supabase.co", "PublishableKey": "sb_publishable_abc"
        ])
        XCTAssertEqual(configuration?.projectURL.host, "abc.supabase.co")
        XCTAssertEqual(configuration?.allowsDevelopmentSessions, false)
        XCTAssertNil(SupabaseConfiguration.from(["ProjectURL": "", "PublishableKey": ""]), "empty build settings mean local mode")
        XCTAssertNil(SupabaseConfiguration.from(["ProjectURL": "https://abc.supabase.co"]))
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        let fake = FakeSupabase()
        let expired = fake.session(for: fake.googleUser, lifetime: 30)
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
        let session = fake.session(for: fake.googleUser, lifetime: 10)
        fake.revokeAllTokens(for: fake.googleUser)
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
        let session = fake.session(for: fake.googleUser, lifetime: 10)
        let (sessions, store) = manager(fake, session: session)
        fake.isOffline = true

        do {
            _ = try await sessions.accessToken()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .offline)
        }
        let user = await sessions.currentUser()
        XCTAssertEqual(user?.id, fake.googleUser)
        XCTAssertEqual(try store.load(), session)

        fake.isOffline = false
        let token = try await sessions.accessToken()
        XCTAssertNotEqual(token, session.accessToken)
    }

    func testRejectedTokenIsRefreshedOnceThenRetried() async throws {
        let fake = FakeSupabase()
        let (sessions, _) = manager(fake, session: fake.session(for: fake.googleUser))
        fake.expireAllAccessTokens()
        let repository = SupabaseScheduleRepository(configuration: CloudFixtures.configuration, transport: fake)

        let list = try await sessions.authorized { try await repository.listSemesters(accessToken: $0) }
        XCTAssertEqual(list, [])
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/list_schedule_semesters"), 2)
        XCTAssertEqual(fake.count("POST /auth/v1/token"), 1)
    }

    func testSignOutClearsTheDeviceEvenWhenOffline() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: fake.session(for: fake.googleUser))
        fake.isOffline = true
        let revoked = await sessions.signOut()
        XCTAssertFalse(revoked)
        XCTAssertNil(try store.load())
        let user = await sessions.currentUser()
        XCTAssertNil(user)
    }

    func testSignOutRevokesTheRefreshToken() async throws {
        let fake = FakeSupabase()
        let session = fake.session(for: fake.googleUser)
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

    func testSHA256AndPKCEMatchPublishedVectors() {
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        let vectors: [(String, String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
            (String(repeating: "a", count: 55), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
            (String(repeating: "a", count: 56), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
            (String(repeating: "a", count: 63), "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
            (String(repeating: "a", count: 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
            (String(repeating: "a", count: 65), "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
            (String(repeating: "a", count: 119), "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
            (String(repeating: "a", count: 120), "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c")
        ]
        for (message, digest) in vectors {
            XCTAssertEqual(hex(PKCE.sha256(Data(message.utf8))), digest, "length \(message.count)")
        }
        // RFC 7636, Appendix B.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifiersAreRandomAndWellFormed() {
        let first = PKCE.makeVerifier()
        let second = PKCE.makeVerifier()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 64)
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(first.unicodeScalars.allSatisfy(unreserved.contains))
    }

    func testGoogleRequestAsksOnlyForIdentity() throws {
        let client = SupabaseAuthClient(configuration: CloudFixtures.configuration, transport: FakeSupabase())
        let request = client.makeGoogleSignInRequest()
        let components = try XCTUnwrap(URLComponents(url: request.authorizeURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "example-project.supabase.co")
        XCTAssertEqual(components.path, "/auth/v1/authorize")
        XCTAssertEqual(query["provider"], "google")
        XCTAssertEqual(query["redirect_to"], "marooncompass://auth/callback")
        XCTAssertEqual(query["scopes"], "openid email profile")
        XCTAssertEqual(query["code_challenge_method"], "s256")
        XCTAssertEqual(query["code_challenge"], PKCE.challenge(for: request.codeVerifier))
        XCTAssertFalse(request.authorizeURL.absoluteString.contains(request.codeVerifier), "the verifier never leaves the app before the exchange")
        XCTAssertFalse(request.authorizeURL.absoluteString.localizedCaseInsensitiveContains("gmail"))
        XCTAssertFalse(request.authorizeURL.absoluteString.localizedCaseInsensitiveContains("calendar"))
    }

    func testCallbackParsing() throws {
        func code(_ text: String) -> Result<String, CloudAuthError> {
            Result { try SupabaseAuthClient.authorizationCode(from: URL(string: text)!) }.mapError { $0 as! CloudAuthError }
        }
        XCTAssertEqual(try code("marooncompass://auth/callback?code=abc-123").get(), "abc-123")
        XCTAssertEqual(code("marooncompass://auth/callback?error=access_denied&error_description=cancel"), .failure(.signInCancelled))
        XCTAssertEqual(code("marooncompass://auth/callback#error=server_error&error_description=x"), .failure(.signInRejected))
        XCTAssertEqual(code("marooncompass://auth/callback"), .failure(.invalidResponse))
        XCTAssertEqual(code("marooncompass://schedule/callback?code=abc"), .failure(.invalidResponse))
        XCTAssertEqual(code("othersapp://auth/callback?code=abc"), .failure(.invalidResponse))
        XCTAssertEqual(code("https://example.com/auth/callback?code=abc"), .failure(.invalidResponse))
    }

    func testGoogleSignInExchangesTheCodeWithItsOwnVerifier() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: nil)
        let request = sessions.makeGoogleSignInRequest()
        let user = try await sessions.completeGoogleSignIn(callbackURL: fake.callbackURL(completing: request.authorizeURL), request: request)
        XCTAssertEqual(user.id, fake.googleUser)
        XCTAssertFalse(user.isAnonymous)
        XCTAssertEqual(try store.load()?.user.id, fake.googleUser)
    }

    func testAnInterceptedCodeCannotBeUsedWithoutTheVerifier() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: nil)
        let victim = sessions.makeGoogleSignInRequest()
        let attacker = sessions.makeGoogleSignInRequest()
        let stolenCallback = fake.callbackURL(completing: victim.authorizeURL)
        do {
            _ = try await sessions.completeGoogleSignIn(callbackURL: stolenCallback, request: attacker)
            XCTFail("a code bound to another challenge must be rejected")
        } catch {
            XCTAssertEqual(error as? CloudAuthError, .signInRejected)
        }
        XCTAssertNil(try store.load())
    }

    func testAccountDeletionClearsTheSession() async throws {
        let fake = FakeSupabase()
        let (sessions, store) = manager(fake, session: fake.session(for: fake.googleUser))
        try await sessions.deleteAccount()
        XCTAssertNil(try store.load())
        XCTAssertEqual(fake.count("POST /functions/v1/delete-account"), 1)
    }
}
