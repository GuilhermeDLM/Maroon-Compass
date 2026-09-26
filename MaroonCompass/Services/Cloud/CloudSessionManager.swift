import Foundation

/// Owns authentication state: the one Supabase session, its persistence, and token refresh.
/// It knows nothing about schedules or UI.
actor CloudSessionManager {
    private let auth: SupabaseAuthClient
    private let store: any AuthSessionStore
    private let allowsDevelopmentSessions: Bool
    private var session: AuthSession?
    private var hasLoaded = false
    private var refreshTask: Task<AuthSession, any Error>?

    init(auth: SupabaseAuthClient, store: any AuthSessionStore) {
        self.auth = auth
        self.store = store
        allowsDevelopmentSessions = auth.configuration.allowsDevelopmentSessions
    }

    /// The restored or current user. Development sessions are discarded when not allowed, so a
    /// Debug session left in the Keychain can never appear in a Release build.
    func currentUser() -> AuthUser? {
        loadIfNeeded()
        return session?.user
    }

    func signInWithApple(identityToken: String, rawNonce: String) async throws -> AuthUser {
        guard auth.configuration.signInWithAppleEnabled else { throw CloudAuthError.appleSignInUnavailable }
        return try adopt(await auth.signInWithApple(identityToken: identityToken, rawNonce: rawNonce))
    }

    func startDevelopmentSession() async throws -> AuthUser {
        guard allowsDevelopmentSessions else { throw CloudAuthError.developmentSessionsUnavailable }
        return try adopt(await auth.signInAnonymously())
    }

    /// Replaces the current session. Used by sign-in paths and by integration tests.
    @discardableResult
    func adopt(_ newSession: AuthSession) throws -> AuthUser {
        do {
            try store.save(newSession)
        } catch {
            throw CloudAuthError.storageFailed
        }
        refreshTask?.cancel()
        refreshTask = nil
        session = newSession
        hasLoaded = true
        return newSession.user
    }

    /// A non-expiring access token, refreshing first when needed. Concurrent callers share one
    /// refresh so rotation never races. An invalid refresh token signs the device out.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        loadIfNeeded()
        guard let current = session else { throw CloudAuthError.signedOut }
        if !forceRefresh, !current.needsRefresh(at: auth.now()) { return current.accessToken }
        return try await refreshed(from: current).accessToken
    }

    /// Runs a request with a valid token and retries once with a refreshed token when the
    /// server reports the token as rejected.
    func authorized<T: Sendable>(_ operation: @Sendable (String) async throws -> T) async throws -> T {
        let token = try await accessToken()
        do {
            return try await operation(token)
        } catch CloudScheduleError.unauthorized {
            return try await operation(accessToken(forceRefresh: true))
        }
    }

    /// Always clears this device's session. Returns whether the server also revoked it.
    @discardableResult
    func signOut() async -> Bool {
        loadIfNeeded()
        let current = session
        clearLocalSession()
        guard let current else { return true }
        var token = current.accessToken
        if current.needsRefresh(at: auth.now()),
           let renewed = try? await auth.refreshSession(refreshToken: current.refreshToken) {
            token = renewed.accessToken
        }
        do {
            try await auth.signOut(accessToken: token)
            return true
        } catch {
            return false
        }
    }

    /// Deletes the Auth account (and, by cascade, every cloud schedule row), then signs out
    /// locally. The local schedule is not touched.
    func deleteAccount() async throws {
        do {
            try await auth.deleteAccount(accessToken: accessToken())
        } catch CloudAuthError.sessionExpired {
            try await auth.deleteAccount(accessToken: accessToken(forceRefresh: true))
        }
        clearLocalSession()
    }

    private func refreshed(from current: AuthSession) async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        let auth = self.auth
        let task = Task { try await auth.refreshSession(refreshToken: current.refreshToken) }
        refreshTask = task
        let result = await task.result
        if refreshTask == task { refreshTask = nil }

        // A sign-out or new sign-in while the refresh was in flight wins.
        guard session?.refreshToken == current.refreshToken else { throw CloudAuthError.signedOut }
        switch result {
        case .success(let renewed):
            // The server has already rotated the refresh token, so keep the new session in
            // memory even if the Keychain write fails; the worst case is signing in again
            // after the next launch.
            session = renewed
            try? store.save(renewed)
            return renewed
        case .failure(CloudAuthError.sessionExpired):
            clearLocalSession()
            throw CloudAuthError.sessionExpired
        case .failure(let error):
            throw error
        }
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let stored = try? store.load() else { return }
        if stored.user.isAnonymous && !allowsDevelopmentSessions {
            try? store.clear()
            return
        }
        session = stored
    }

    private func clearLocalSession() {
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        hasLoaded = true
        try? store.clear()
    }
}
