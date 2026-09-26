import Foundation
import Observation

/// Everything cloud code needs, created once per process. Absent when the build has no
/// Supabase configuration, in which case the app stays in local mode.
struct CloudServices: Sendable {
    let configuration: SupabaseConfiguration
    let sessions: CloudSessionManager
    let repository: SupabaseScheduleRepository

    init(configuration: SupabaseConfiguration, transport: any HTTPTransport, sessionStore: any AuthSessionStore) {
        self.configuration = configuration
        sessions = CloudSessionManager(
            auth: SupabaseAuthClient(configuration: configuration, transport: transport),
            store: sessionStore
        )
        repository = SupabaseScheduleRepository(configuration: configuration, transport: transport)
    }

    init(configuration: SupabaseConfiguration, sessions: CloudSessionManager, repository: SupabaseScheduleRepository) {
        self.configuration = configuration
        self.sessions = sessions
        self.repository = repository
    }
}

struct CloudNotice: Equatable, Identifiable, Sendable {
    let id = UUID()
    let message: String
    let isError: Bool
}

/// UI state for the account and cloud backup screen. Authentication state lives in
/// `CloudSessionManager`, the schedule lives in `AppStore`, and sync decisions live in
/// `CloudScheduleSync`; this model only reflects them.
@MainActor
@Observable
final class CloudAccountModel {
    enum Account: Equatable {
        case unknown
        case signedOut
        case signedIn(AuthUser)
    }

    private(set) var account: Account = .unknown
    private(set) var overview: CloudSyncOverview?
    private(set) var isWorking = false
    private(set) var canUndoRestore = false
    private(set) var restoreBackupName: String?
    var notice: CloudNotice?

    let isConfigured: Bool
    let allowsDevelopmentSessions: Bool

    @ObservationIgnored private let sessions: CloudSessionManager?
    @ObservationIgnored private let sync: CloudScheduleSync?

    init(services: CloudServices?, local: any LocalScheduleAccess, stateStore: any CloudSyncStateStore) {
        isConfigured = services != nil
        allowsDevelopmentSessions = services?.configuration.allowsDevelopmentSessions ?? false
        sessions = services?.sessions
        sync = services.map {
            CloudScheduleSync(sessions: $0.sessions, repository: $0.repository, local: local, store: stateStore)
        }
        updateUndoState()
    }

    var user: AuthUser? {
        if case .signedIn(let user) = account { return user }
        return nil
    }

    /// Restores the saved session and compares copies. Safe to call on every appearance.
    func load() async {
        guard let sessions else {
            account = .signedOut
            return
        }
        if let user = await sessions.currentUser() {
            account = .signedIn(user)
            await refresh()
        } else {
            account = .signedOut
        }
    }

    func refresh() async {
        await run { sync, user in try await sync.refresh(for: user) }
    }

    /// Google sign-in. `authenticate` presents the system web-authentication session for the
    /// authorize URL and returns the callback URL; it throws `CancellationError` when the person
    /// closes the sheet, which leaves everything unchanged without an error message.
    func signInWithGoogle(authenticate: @MainActor (URL) async throws -> URL) async {
        guard let sessions, !isWorking else { return }
        let request = sessions.makeGoogleSignInRequest()
        let callbackURL: URL
        do {
            callbackURL = try await authenticate(request.authorizeURL)
        } catch is CancellationError {
            return
        } catch {
            notice = CloudNotice(message: CloudAuthError.signInRejected.localizedDescription, isError: true)
            return
        }
        await signIn { try await $0.completeGoogleSignIn(callbackURL: callbackURL, request: request) }
    }

    func startDevelopmentSession() async {
        await signIn { try await $0.startDevelopmentSession() }
    }

    func signOut() async {
        guard let sessions, !isWorking else { return }
        isWorking = true
        let revoked = await sessions.signOut()
        sync?.forgetAccount()
        account = .signedOut
        overview = nil
        isWorking = false
        notice = CloudNotice(
            message: revoked
                ? "Signed out. Your schedule stays on this device."
                : "Signed out on this device. The server session couldn't be revoked while offline; your schedule stays on this device.",
            isError: false
        )
    }

    func deleteAccount() async {
        guard let sessions, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await sessions.deleteAccount()
            sync?.forgetAccount()
            account = .signedOut
            overview = nil
            notice = CloudNotice(
                message: "Your account and its cloud schedules were deleted. The schedule on this device was not changed.",
                isError: false
            )
        } catch {
            handle(error)
        }
    }

    func uploadLocalChanges() async {
        await run(success: "Your schedule is backed up.") { sync, user in try await sync.uploadLocalChanges(for: user) }
    }

    func replaceCloudCopy(_ reviewed: CloudSemesterSummary) async {
        await run(success: "The cloud copy now matches this device.") { sync, user in
            try await sync.replaceCloudCopy(reviewed, for: user)
        }
    }

    func restore(_ summary: CloudSemesterSummary) async {
        await run(success: "Restored \(summary.name) from the cloud. You can undo this.") { sync, user in
            try await sync.restore(summary, for: user)
        }
    }

    func deleteCloudCopy(_ reviewed: CloudSemesterSummary) async {
        await run(success: "The cloud copy was deleted. The schedule on this device was not changed.") { sync, user in
            try await sync.deleteCloudCopy(reviewed, for: user)
        }
    }

    func undoRestore() async {
        guard let sync else { return }
        do {
            try sync.undoRestore()
            notice = CloudNotice(message: "The previous schedule is back on this device.", isError: false)
        } catch {
            notice = CloudNotice(message: error.localizedDescription, isError: true)
        }
        updateUndoState()
        await refresh()
    }

    // MARK: - Internals

    private func signIn(_ operation: @escaping @Sendable (CloudSessionManager) async throws -> AuthUser) async {
        guard let sessions, !isWorking else { return }
        isWorking = true
        do {
            let user = try await operation(sessions)
            account = .signedIn(user)
            notice = nil
            isWorking = false
            await refresh()
        } catch CloudAuthError.signInCancelled {
            isWorking = false
        } catch {
            isWorking = false
            handle(error)
        }
    }

    private func run(
        success: String? = nil,
        _ operation: (CloudScheduleSync, AuthUser) async throws -> CloudSyncOverview
    ) async {
        guard let sync, let user, !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            updateUndoState()
        }
        do {
            overview = try await operation(sync, user)
            if let success { notice = CloudNotice(message: success, isError: false) }
        } catch {
            handle(error)
            // Re-read the situation after a conflict so the screen shows the latest choice.
            let conflicts: [CloudScheduleError] = [.versionConflict, .scheduleExists, .scheduleMissing]
            if (error as? CloudSyncError) == .changedElsewhere || conflicts.contains(where: { $0 == error as? CloudScheduleError }) {
                overview = try? await sync.refresh(for: user)
            }
        }
    }

    private func handle(_ error: any Error) {
        if let authError = error as? CloudAuthError, authError == .sessionExpired || authError == .signedOut {
            account = .signedOut
            overview = nil
        }
        notice = CloudNotice(message: error.localizedDescription, isError: true)
    }

    private func updateUndoState() {
        canUndoRestore = sync?.canUndoRestore ?? false
        restoreBackupName = canUndoRestore ? sync?.restoreBackupSemesterName : nil
    }
}
