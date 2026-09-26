import Foundation

/// Access to the app's single local schedule. The app implements it over `AppStore`; tests use
/// memory. The cloud layer never writes local data except through `replaceSchedule`/`restore`,
/// and only after an explicit user action.
@MainActor
protocol LocalScheduleAccess: AnyObject {
    /// The schedule the app is using now. `isEmbedded` is true for the verified schedule bundled
    /// with the app (no import has replaced it).
    func currentSchedule() -> (bundle: ImportedScheduleBundle, isEmbedded: Bool)
    func makeBackup() -> LocalScheduleBackup
    func replaceSchedule(with bundle: ImportedScheduleBundle) throws
    func restore(_ backup: LocalScheduleBackup) throws
}

/// The exact local schedule before a cloud restore, kept so the restore can be undone.
enum LocalScheduleBackup: Codable, Equatable, Sendable {
    case embedded
    /// The stored import bytes, byte for byte (including any private `.ics` diagnostics).
    case imported(Data)
}

/// What this device last agreed with the cloud about.
struct CloudSyncLink: Codable, Equatable, Sendable {
    let userID: UUID
    let semesterID: UUID
    var remoteVersion: Int
    /// The schedule content both sides held at `remoteVersion`.
    var syncedSnapshot: CloudScheduleSnapshot
    var syncedAt: Date
}

struct CloudRestoreBackup: Codable, Equatable, Sendable {
    let createdAt: Date
    let semesterName: String
    let previous: LocalScheduleBackup
    /// Undo is offered only while the local schedule is still exactly what was restored, so it
    /// can never discard a newer local change.
    let restoredContent: CloudScheduleSnapshot
}

struct CloudSyncLocalState: Codable, Equatable, Sendable {
    var link: CloudSyncLink?
    /// An upload the user requested that failed for connectivity; retried on the next refresh.
    var pendingUploadUserID: UUID?
    var restoreBackup: CloudRestoreBackup?
}

@MainActor
protocol CloudSyncStateStore: AnyObject {
    var state: CloudSyncLocalState { get set }
}

@MainActor
final class InMemoryCloudSyncStateStore: CloudSyncStateStore {
    var state: CloudSyncLocalState
    init(_ state: CloudSyncLocalState = CloudSyncLocalState()) { self.state = state }
}

@MainActor
final class UserDefaultsCloudSyncStateStore: CloudSyncStateStore {
    private let defaults: UserDefaults
    private let key = "cloudScheduleSync.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var state: CloudSyncLocalState {
        get {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(CloudSyncLocalState.self, from: data) else {
                return CloudSyncLocalState()
            }
            return value
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }
}

enum CloudSyncState: Equatable, Sendable {
    /// No cloud copy of this term exists for the account.
    case noCloudCopy
    /// A cloud copy of this term exists, is not linked to this device, and differs from it.
    case cloudCopyAvailable(CloudSemesterSummary)
    case upToDate(CloudSemesterSummary)
    /// This device changed since the last sync; the cloud did not.
    case localChanges(CloudSemesterSummary)
    /// Another device changed the cloud copy; this device did not change.
    case remoteChanges(CloudSemesterSummary)
    /// Both changed. The user decides which copy to keep.
    case conflict(CloudSemesterSummary)
    /// The linked cloud copy was deleted elsewhere.
    case cloudCopyDeleted

    var summary: CloudSemesterSummary? {
        switch self {
        case .cloudCopyAvailable(let summary), .upToDate(let summary), .localChanges(let summary),
             .remoteChanges(let summary), .conflict(let summary):
            summary
        case .noCloudCopy, .cloudCopyDeleted:
            nil
        }
    }
}

struct CloudSyncOverview: Equatable, Sendable {
    let state: CloudSyncState
    /// Set when the local schedule cannot be uploaded without loss.
    let localLimitation: CloudScheduleLimitation?
    /// Cloud semesters for other terms, which can be restored explicitly.
    let otherSemesters: [CloudSemesterSummary]
    let lastSyncedAt: Date?
}

enum CloudSyncError: LocalizedError, Equatable, Sendable {
    case changedElsewhere
    case nothingToUpload
    case nothingToUndo
    case localSaveFailed

    var errorDescription: String? {
        switch self {
        case .changedElsewhere: "The cloud copy changed while you were deciding. Review the latest version."
        case .nothingToUpload: "There's nothing new to upload."
        case .nothingToUndo: "The restored schedule has already changed, so it can't be undone automatically."
        case .localSaveFailed: "The schedule couldn't be saved on this device. Nothing changed."
        }
    }
}

/// Local-first schedule sync. Nothing runs automatically except a retry of an upload the user
/// already requested, and no path overwrites either copy without an explicit user action.
@MainActor
final class CloudScheduleSync {
    private let sessions: CloudSessionManager
    private let repository: SupabaseScheduleRepository
    private let local: any LocalScheduleAccess
    private let store: any CloudSyncStateStore
    private let fallbackTerm: Term
    private let now: () -> Date
    private let makeSemesterID: () -> UUID

    init(
        sessions: CloudSessionManager,
        repository: SupabaseScheduleRepository,
        local: any LocalScheduleAccess,
        store: any CloudSyncStateStore,
        fallbackTerm: Term = ScheduleSeed.term,
        now: @escaping () -> Date = { Date() },
        makeSemesterID: @escaping () -> UUID = { UUID() }
    ) {
        self.sessions = sessions
        self.repository = repository
        self.local = local
        self.store = store
        self.fallbackTerm = fallbackTerm
        self.now = now
        self.makeSemesterID = makeSemesterID
    }

    var canUndoRestore: Bool {
        guard let backup = store.state.restoreBackup, let current = try? localSnapshot() else { return false }
        return current.hasSameContent(as: backup.restoredContent)
    }

    var restoreBackupSemesterName: String? { store.state.restoreBackup?.semesterName }

    func localSnapshot() throws -> CloudScheduleSnapshot {
        let current = local.currentSchedule()
        return try CloudScheduleSnapshot(bundle: current.bundle, fallbackTerm: fallbackTerm, isEmbedded: current.isEmbedded)
    }

    /// Compares this device, the last agreed state, and the cloud. May link this device to a
    /// cloud copy that already has identical content (no data changes), and retries a pending
    /// upload the user asked for earlier.
    func refresh(for user: AuthUser) async throws -> CloudSyncOverview {
        var overview = try await evaluate(for: user)
        if store.state.pendingUploadUserID == user.id {
            switch overview.state {
            case .noCloudCopy, .localChanges:
                if overview.localLimitation == nil {
                    _ = try? await uploadLocalChanges(for: user)
                    overview = try await evaluate(for: user)
                }
            case .upToDate:
                store.state.pendingUploadUserID = nil
            default:
                // The situation changed (conflict, deletion, remote edit); the user decides.
                store.state.pendingUploadUserID = nil
            }
        }
        return overview
    }

    /// Uploads this device's schedule when that cannot overwrite anyone else's change:
    /// creating the first cloud copy, sending local changes on top of the version this device
    /// last saw, or re-creating a copy that was deleted elsewhere.
    func uploadLocalChanges(for user: AuthUser) async throws -> CloudSyncOverview {
        let snapshot = try localSnapshot()
        let link = applicableLink(for: user, termStart: snapshot.semester.firstClassDate)
        let target: (semesterID: UUID, expected: Int?)
        if let link {
            let summaries = try await withToken { try await $0.listSemesters(accessToken: $1) }
            if let remote = summaries.first(where: { $0.semesterID == link.semesterID }) {
                guard remote.syncVersion == link.remoteVersion else { throw CloudSyncError.changedElsewhere }
                guard !snapshot.hasSameContent(as: link.syncedSnapshot) else { throw CloudSyncError.nothingToUpload }
                target = (link.semesterID, link.remoteVersion)
            } else {
                target = (link.semesterID, nil)
            }
        } else {
            target = (makeSemesterID(), nil)
        }
        return try await write(snapshot, to: target.semesterID, expectedVersion: target.expected, for: user)
    }

    /// Replaces the cloud copy the user reviewed with this device's schedule. Fails with
    /// `changedElsewhere` if the cloud moved past the reviewed version.
    func replaceCloudCopy(_ reviewed: CloudSemesterSummary, for user: AuthUser) async throws -> CloudSyncOverview {
        let snapshot = try localSnapshot()
        return try await write(snapshot, to: reviewed.semesterID, expectedVersion: reviewed.syncVersion, for: user)
    }

    /// Replaces this device's schedule with the latest cloud copy after saving a backup that
    /// `undoRestore` can apply.
    func restore(_ summary: CloudSemesterSummary, for user: AuthUser) async throws -> CloudSyncOverview {
        let record = try await withToken { try await $0.fetch(semesterID: summary.semesterID, accessToken: $1) }
        guard let record else { throw CloudScheduleError.scheduleMissing }
        let bundle = try record.snapshot.makeBundle(restoredAt: now())
        let previous = local.makeBackup()
        do {
            try local.replaceSchedule(with: bundle)
        } catch {
            throw CloudSyncError.localSaveFailed
        }
        let restored = (try? localSnapshot()) ?? record.snapshot
        store.state.restoreBackup = CloudRestoreBackup(
            createdAt: now(), semesterName: record.snapshot.semester.name,
            previous: previous, restoredContent: restored
        )
        store.state.link = CloudSyncLink(
            userID: user.id, semesterID: record.semesterID, remoteVersion: record.syncVersion,
            syncedSnapshot: restored, syncedAt: now()
        )
        store.state.pendingUploadUserID = nil
        return try await evaluate(for: user)
    }

    /// Puts back the schedule that the last restore replaced.
    func undoRestore() throws {
        guard let backup = store.state.restoreBackup, canUndoRestore else { throw CloudSyncError.nothingToUndo }
        do {
            try local.restore(backup.previous)
        } catch {
            throw CloudSyncError.localSaveFailed
        }
        store.state.restoreBackup = nil
    }

    /// Deletes the reviewed cloud copy only if it is still at the reviewed version. The local
    /// schedule is not changed.
    func deleteCloudCopy(_ reviewed: CloudSemesterSummary, for user: AuthUser) async throws -> CloudSyncOverview {
        let deleted = try await withToken {
            try await $0.delete(semesterID: reviewed.semesterID, expectedVersion: reviewed.syncVersion, accessToken: $1)
        }
        guard deleted else { throw CloudSyncError.changedElsewhere }
        if store.state.link?.semesterID == reviewed.semesterID { store.state.link = nil }
        store.state.pendingUploadUserID = nil
        return try await evaluate(for: user)
    }

    /// Forgets sync metadata (sign-out, account deletion, or switching accounts). The local
    /// schedule and any restore backup stay on the device.
    func forgetAccount() {
        store.state.link = nil
        store.state.pendingUploadUserID = nil
    }

    // MARK: - Internals

    /// Runs a repository call with a valid token, refreshing and retrying once if rejected.
    private func withToken<T: Sendable>(
        _ operation: @Sendable (SupabaseScheduleRepository, String) async throws -> T
    ) async throws -> T {
        let repository = self.repository
        return try await sessions.authorized { try await operation(repository, $0) }
    }

    private func currentLink(for user: AuthUser) -> CloudSyncLink? {
        guard let link = store.state.link else { return nil }
        guard link.userID == user.id else {
            // Another account's metadata never applies to this one.
            forgetAccount()
            return nil
        }
        return link
    }

    /// The link, if it belongs to this account and to the term the device now holds. A device
    /// that switched to a different term gets that term's own cloud copy; the previous term's
    /// copy is left untouched and listed with the other semesters.
    private func applicableLink(for user: AuthUser, termStart: String) -> CloudSyncLink? {
        guard let link = currentLink(for: user) else { return nil }
        guard link.syncedSnapshot.semester.firstClassDate == termStart else {
            store.state.link = nil
            store.state.pendingUploadUserID = nil
            return nil
        }
        return link
    }

    private func write(
        _ snapshot: CloudScheduleSnapshot,
        to semesterID: UUID,
        expectedVersion: Int?,
        for user: AuthUser
    ) async throws -> CloudSyncOverview {
        do {
            let result = try await withToken {
                try await $0.replace(
                    semesterID: semesterID, expectedVersion: expectedVersion, snapshot: snapshot, accessToken: $1
                )
            }
            store.state.link = CloudSyncLink(
                userID: user.id, semesterID: semesterID, remoteVersion: result.syncVersion,
                syncedSnapshot: snapshot, syncedAt: now()
            )
            store.state.pendingUploadUserID = nil
        } catch CloudScheduleError.offline {
            store.state.pendingUploadUserID = user.id
            throw CloudScheduleError.offline
        } catch let error as CloudScheduleError
                    where error == .versionConflict || error == .scheduleExists || error == .scheduleMissing {
            // A retried request whose first response was lost already succeeded; recognize it
            // instead of reporting a conflict against our own write.
            let record = try? await withToken { try await $0.fetch(semesterID: semesterID, accessToken: $1) }
            guard let record, record.snapshot.hasSameContent(as: snapshot) else {
                store.state.pendingUploadUserID = nil
                if error == .versionConflict { throw CloudSyncError.changedElsewhere }
                throw error
            }
            store.state.link = CloudSyncLink(
                userID: user.id, semesterID: semesterID, remoteVersion: record.syncVersion,
                syncedSnapshot: snapshot, syncedAt: now()
            )
            store.state.pendingUploadUserID = nil
        }
        return try await evaluate(for: user)
    }

    private func evaluate(for user: AuthUser) async throws -> CloudSyncOverview {
        let current = local.currentSchedule()
        let termStart = (current.bundle.term ?? fallbackTerm).firstClassDate
        var limitation: CloudScheduleLimitation?
        var snapshot: CloudScheduleSnapshot?
        do {
            snapshot = try CloudScheduleSnapshot(bundle: current.bundle, fallbackTerm: fallbackTerm, isEmbedded: current.isEmbedded)
        } catch CloudScheduleError.unsupportedSchedule(let reason) {
            limitation = reason
        }

        let summaries = try await withToken { try await $0.listSemesters(accessToken: $1) }
        let link = applicableLink(for: user, termStart: termStart)
        let state: CloudSyncState

        if let link {
            if let remote = summaries.first(where: { $0.semesterID == link.semesterID }) {
                let localChanged = snapshot.map { !$0.hasSameContent(as: link.syncedSnapshot) } ?? true
                let remoteChanged = remote.syncVersion != link.remoteVersion
                switch (localChanged, remoteChanged) {
                case (false, false):
                    state = .upToDate(remote)
                case (true, false):
                    state = .localChanges(remote)
                case (false, true):
                    state = .remoteChanges(remote)
                case (true, true):
                    state = try await adoptIfIdentical(remote, local: snapshot, user: user) ?? .conflict(remote)
                }
            } else {
                state = .cloudCopyDeleted
            }
        } else if let candidate = summaries.first(where: { $0.firstClassDate == termStart }) {
            state = try await adoptIfIdentical(candidate, local: snapshot, user: user) ?? .cloudCopyAvailable(candidate)
        } else {
            state = .noCloudCopy
        }

        let linkedID = store.state.link?.semesterID ?? state.summary?.semesterID
        return CloudSyncOverview(
            state: state,
            localLimitation: limitation,
            otherSemesters: summaries.filter { $0.semesterID != linkedID && $0.firstClassDate != termStart },
            lastSyncedAt: store.state.link?.syncedAt
        )
    }

    /// Links to a cloud copy whose content already equals this device's schedule.
    private func adoptIfIdentical(
        _ summary: CloudSemesterSummary,
        local snapshot: CloudScheduleSnapshot?,
        user: AuthUser
    ) async throws -> CloudSyncState? {
        guard let snapshot else { return nil }
        let record = try await withToken { try await $0.fetch(semesterID: summary.semesterID, accessToken: $1) }
        guard let record, record.snapshot.hasSameContent(as: snapshot) else { return nil }
        store.state.link = CloudSyncLink(
            userID: user.id, semesterID: record.semesterID, remoteVersion: record.syncVersion,
            syncedSnapshot: snapshot, syncedAt: now()
        )
        let current = CloudSemesterSummary(
            semesterID: record.semesterID, name: record.snapshot.semester.name,
            firstClassDate: record.snapshot.semester.firstClassDate,
            lastClassDate: record.snapshot.semester.lastClassDate,
            syncVersion: record.syncVersion, updatedAt: record.updatedAt,
            courseCount: record.snapshot.courses.count
        )
        return .upToDate(current)
    }
}
