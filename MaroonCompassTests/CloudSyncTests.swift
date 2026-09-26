import XCTest
@testable import MaroonCompass

final class CloudSyncTests: XCTestCase {
    private func user(_ fake: FakeSupabase) -> AuthUser {
        AuthUser(id: fake.appleUser, isAnonymous: false, provider: nil)
    }

    @MainActor
    private func signedInDevice(_ fake: FakeSupabase, local: ImportedScheduleBundle? = nil) -> SimulatedDevice {
        SimulatedDevice(fake: fake, local: local, session: fake.session(for: fake.appleUser))
    }

    @MainActor
    func testFirstBackupCreatesOneCloudCopy() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake)
        let first = try await phone.sync.refresh(for: user(fake))
        XCTAssertEqual(first.state, .noCloudCopy)
        XCTAssertNil(first.localLimitation, "the embedded Howdy schedule can be backed up")

        let backedUp = try await phone.sync.uploadLocalChanges(for: user(fake))
        guard case .upToDate(let summary) = backedUp.state else { return XCTFail("\(backedUp.state)") }
        XCTAssertEqual(summary.syncVersion, 1)
        XCTAssertEqual(summary.courseCount, ScheduleSeed.courses.count)
        XCTAssertEqual(fake.semesterCount, 1)

        do {
            _ = try await phone.sync.uploadLocalChanges(for: user(fake))
            XCTFail("an unchanged schedule is not uploaded again")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .nothingToUpload)
        }
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/replace_schedule_snapshot"), 1)
    }

    @MainActor
    func testSecondDeviceWithTheSameScheduleLinksWithoutWriting() async throws {
        let fake = FakeSupabase()
        _ = try await signedInDevice(fake).sync.uploadLocalChanges(for: user(fake))
        let writes = fake.count("POST /rest/v1/rpc/replace_schedule_snapshot")

        let ipad = signedInDevice(fake)
        let overview = try await ipad.sync.refresh(for: user(fake))
        guard case .upToDate = overview.state else { return XCTFail("\(overview.state)") }
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/replace_schedule_snapshot"), writes)
        XCTAssertNotNil(ipad.stateStore.state.link)
    }

    @MainActor
    func testSecondDeviceWithADifferentScheduleMustChooseAndCanUndo() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake)
        _ = try await phone.sync.uploadLocalChanges(for: user(fake))

        let photo = CloudFixtures.reviewedPhotoBundle()
        let ipad = signedInDevice(fake, local: photo)
        let overview = try await ipad.sync.refresh(for: user(fake))
        guard case .cloudCopyAvailable(let cloud) = overview.state else { return XCTFail("\(overview.state)") }

        do {
            _ = try await ipad.sync.uploadLocalChanges(for: user(fake))
            XCTFail("a plain upload must not create a duplicate of the same term")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .scheduleExists)
        }
        XCTAssertEqual(fake.semesterCount, 1)

        let replaced = try await ipad.sync.replaceCloudCopy(cloud, for: user(fake))
        guard case .upToDate(let updated) = replaced.state else { return XCTFail("\(replaced.state)") }
        XCTAssertEqual(updated.syncVersion, 2)

        let onPhone = try await phone.sync.refresh(for: user(fake))
        guard case .remoteChanges(let remote) = onPhone.state else { return XCTFail("\(onPhone.state)") }
        XCTAssertNil(phone.local.imported, "nothing changes on the phone until the user restores")

        let restored = try await phone.sync.restore(remote, for: user(fake))
        guard case .upToDate = restored.state else { return XCTFail("\(restored.state)") }
        XCTAssertEqual(phone.local.imported?.courses, photo.courses)
        XCTAssertEqual(phone.local.imported?.patterns, photo.patterns)
        XCTAssertTrue(phone.sync.canUndoRestore)

        try phone.sync.undoRestore()
        XCTAssertNil(phone.local.imported, "undo puts the embedded schedule back")
        XCTAssertFalse(phone.sync.canUndoRestore)
        let afterUndo = try await phone.sync.refresh(for: user(fake))
        guard case .localChanges = afterUndo.state else { return XCTFail("\(afterUndo.state)") }
    }

    @MainActor
    func testBothSidesChangedIsAConflictResolvedExplicitly() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        _ = try await phone.sync.uploadLocalChanges(for: user(fake))
        let ipad = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        _ = try await ipad.sync.refresh(for: user(fake))

        ipad.local.imported = CloudFixtures.reviewedPhotoBundle(room: "170")
        _ = try await ipad.sync.uploadLocalChanges(for: user(fake))
        phone.local.imported = CloudFixtures.reviewedPhotoBundle(title: "Calculus III")

        let overview = try await phone.sync.refresh(for: user(fake))
        guard case .conflict(let cloud) = overview.state else { return XCTFail("\(overview.state)") }
        XCTAssertEqual(cloud.syncVersion, 2)
        XCTAssertEqual(phone.local.imported?.courses.first?.title, "Calculus III", "a conflict never changes local data")

        do {
            _ = try await phone.sync.uploadLocalChanges(for: user(fake))
            XCTFail("a plain upload cannot overwrite the other device's change")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .changedElsewhere)
        }
        let resolved = try await phone.sync.replaceCloudCopy(cloud, for: user(fake))
        guard case .upToDate(let summary) = resolved.state else { return XCTFail("\(resolved.state)") }
        XCTAssertEqual(summary.syncVersion, 3)
    }

    @MainActor
    func testAReviewedVersionThatMovedOnIsNotOverwritten() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        _ = try await phone.sync.uploadLocalChanges(for: user(fake))
        let ipad = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle(room: "999"))
        guard case .cloudCopyAvailable(let reviewed) = try await ipad.sync.refresh(for: user(fake)).state else {
            return XCTFail("expected a choice")
        }

        phone.local.imported = CloudFixtures.reviewedPhotoBundle(title: "Changed on phone")
        _ = try await phone.sync.uploadLocalChanges(for: user(fake))

        do {
            _ = try await ipad.sync.replaceCloudCopy(reviewed, for: user(fake))
            XCTFail("the reviewed version is stale")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .changedElsewhere)
        }
        let cloud = try XCTUnwrap(fake.row(reviewed.semesterID))
        XCTAssertEqual(cloud.snapshot.courses.first?.title, "Changed on phone")
    }

    @MainActor
    func testOfflineUploadIsRetriedOnTheNextRefresh() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake)
        _ = try await phone.sync.refresh(for: user(fake))
        fake.isOffline = true
        do {
            _ = try await phone.sync.uploadLocalChanges(for: user(fake))
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .offline)
        }
        XCTAssertEqual(phone.stateStore.state.pendingUploadUserID, fake.appleUser)

        fake.isOffline = false
        let overview = try await phone.sync.refresh(for: user(fake))
        guard case .upToDate = overview.state else { return XCTFail("\(overview.state)") }
        XCTAssertNil(phone.stateStore.state.pendingUploadUserID)
        XCTAssertEqual(fake.semesterCount, 1)
    }

    @MainActor
    func testALostResponseIsRecognizedInsteadOfDuplicated() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        _ = try await phone.sync.refresh(for: user(fake))

        // The create reaches the server but its response is lost.
        fake.dropNextWriteResponse = true
        do {
            _ = try await phone.sync.uploadLocalChanges(for: user(fake))
            XCTFail("expected a connectivity error")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .offline)
        }
        let created = try await phone.sync.refresh(for: user(fake))
        guard case .upToDate(let first) = created.state else { return XCTFail("\(created.state)") }
        XCTAssertEqual(first.syncVersion, 1)
        XCTAssertEqual(fake.semesterCount, 1)

        // An update whose response is lost is recognized the same way.
        phone.local.imported = CloudFixtures.reviewedPhotoBundle(room: "201")
        fake.dropNextWriteResponse = true
        _ = try? await phone.sync.uploadLocalChanges(for: user(fake))
        let updated = try await phone.sync.refresh(for: user(fake))
        guard case .upToDate(let second) = updated.state else { return XCTFail("\(updated.state)") }
        XCTAssertEqual(second.syncVersion, 2)
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/replace_schedule_snapshot"), 2, "no blind re-send")
    }

    @MainActor
    func testRemoteDeletionIsReportedAndCanBeRecreated() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        guard case .upToDate(let summary) = try await phone.sync.uploadLocalChanges(for: user(fake)).state else {
            return XCTFail("expected upload")
        }
        fake.serverDelete(summary.semesterID)

        let overview = try await phone.sync.refresh(for: user(fake))
        XCTAssertEqual(overview.state, .cloudCopyDeleted)
        XCTAssertNotNil(phone.local.imported, "remote deletion never deletes local data")

        let recreated = try await phone.sync.uploadLocalChanges(for: user(fake))
        guard case .upToDate(let again) = recreated.state else { return XCTFail("\(recreated.state)") }
        XCTAssertEqual(again.semesterID, summary.semesterID)
        XCTAssertEqual(again.syncVersion, 1)
    }

    @MainActor
    func testDeletingTheCloudCopyRequiresTheReviewedVersion() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        guard case .upToDate(let v1) = try await phone.sync.uploadLocalChanges(for: user(fake)).state else {
            return XCTFail("expected upload")
        }
        fake.serverWrite(v1.semesterID, user: fake.appleUser,
                         snapshot: try CloudScheduleSnapshot(bundle: CloudFixtures.reviewedPhotoBundle(room: "5"), fallbackTerm: ScheduleSeed.term))
        do {
            _ = try await phone.sync.deleteCloudCopy(v1, for: user(fake))
            XCTFail("stale delete must fail")
        } catch {
            XCTAssertEqual(error as? CloudSyncError, .changedElsewhere)
        }
        XCTAssertEqual(fake.semesterCount, 1)

        guard case .remoteChanges(let v2) = try await phone.sync.refresh(for: user(fake)).state else {
            return XCTFail("expected remote changes")
        }
        let overview = try await phone.sync.deleteCloudCopy(v2, for: user(fake))
        XCTAssertEqual(overview.state, .noCloudCopy)
        XCTAssertEqual(fake.semesterCount, 0)
        XCTAssertNotNil(phone.local.imported)
    }

    @MainActor
    func testUndoIsNotOfferedAfterANewerLocalChange() async throws {
        let fake = FakeSupabase()
        let ipad = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        _ = try await ipad.sync.uploadLocalChanges(for: user(fake))
        let phone = signedInDevice(fake)
        guard case .cloudCopyAvailable(let cloud) = try await phone.sync.refresh(for: user(fake)).state else {
            return XCTFail("expected a choice")
        }
        _ = try await phone.sync.restore(cloud, for: user(fake))
        XCTAssertTrue(phone.sync.canUndoRestore)

        phone.local.imported = CloudFixtures.reviewedPhotoBundle(title: "Edited after restore")
        XCTAssertFalse(phone.sync.canUndoRestore)
        XCTAssertThrowsError(try phone.sync.undoRestore()) { error in
            XCTAssertEqual(error as? CloudSyncError, .nothingToUndo)
        }
        XCTAssertEqual(phone.local.imported?.courses.first?.title, "Edited after restore")
    }

    @MainActor
    func testUnsupportedLocalSchedulesAreExplainedAndNeverUploaded() async throws {
        let fake = FakeSupabase()
        let base = CloudFixtures.reviewedPhotoBundle()
        let repeated = ImportedScheduleBundle(
            sourceName: "calendar.ics", importedAt: base.importedAt, term: base.term, courses: base.courses,
            patterns: [base.patterns[0], base.patterns[0]], oneTimeEvents: []
        )
        let phone = signedInDevice(fake, local: repeated)
        let overview = try await phone.sync.refresh(for: user(fake))
        XCTAssertEqual(overview.localLimitation, .repeatedIdentifier)
        do {
            _ = try await phone.sync.uploadLocalChanges(for: user(fake))
            XCTFail("expected the schedule to stay local")
        } catch {
            XCTAssertEqual(error as? CloudScheduleError, .unsupportedSchedule(.repeatedIdentifier))
        }
        XCTAssertEqual(fake.count("POST /rest/v1/rpc/replace_schedule_snapshot"), 0)
    }

    @MainActor
    func testAnotherAccountNeverUsesThePreviousAccountsLink() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake)
        _ = try await phone.sync.uploadLocalChanges(for: user(fake))
        XCTAssertNotNil(phone.stateStore.state.link)

        let other = AuthUser(id: UUID(), isAnonymous: true, provider: nil)
        _ = try await phone.services.sessions.adopt(fake.session(for: other.id))
        let overview = try await phone.sync.refresh(for: other)
        XCTAssertEqual(overview.state, .noCloudCopy, "the second account sees none of the first account's data")
        XCTAssertNil(phone.stateStore.state.link)
    }

    @MainActor
    func testSignOutKeepsTheLocalScheduleAndForgetsSyncMetadata() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        let model = phone.makeModel()
        await model.load()
        await model.uploadLocalChanges()
        guard case .upToDate = model.overview?.state else { return XCTFail("\(String(describing: model.overview))") }

        await model.signOut()
        XCTAssertEqual(model.account, .signedOut)
        XCTAssertNil(model.overview)
        XCTAssertNil(phone.stateStore.state.link)
        XCTAssertNil(try phone.sessionStore.load())
        XCTAssertEqual(phone.local.imported?.courses, CloudFixtures.reviewedPhotoBundle().courses)
        XCTAssertEqual(fake.semesterCount, 1, "signing out does not delete the cloud copy")
    }

    @MainActor
    func testExpiredSessionDuringSyncSignsOutWithoutTouchingLocalData() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        let model = phone.makeModel()
        await model.load()
        fake.revokeAllTokens(for: fake.appleUser)

        await model.refresh()
        XCTAssertEqual(model.account, .signedOut)
        XCTAssertEqual(model.notice?.isError, true)
        XCTAssertNotNil(phone.local.imported)
    }

    @MainActor
    func testAccountDeletionRemovesCloudDataButNotLocalData() async throws {
        let fake = FakeSupabase()
        let phone = signedInDevice(fake, local: CloudFixtures.reviewedPhotoBundle())
        let model = phone.makeModel()
        await model.load()
        await model.uploadLocalChanges()
        XCTAssertEqual(fake.semesterCount, 1)

        await model.deleteAccount()
        XCTAssertEqual(model.account, .signedOut)
        XCTAssertEqual(fake.semesterCount, 0)
        XCTAssertNil(try phone.sessionStore.load())
        XCTAssertNil(phone.stateStore.state.link)
        XCTAssertEqual(phone.local.imported?.courses, CloudFixtures.reviewedPhotoBundle().courses)
    }

    @MainActor
    func testUnconfiguredBuildStaysInLocalMode() async {
        let model = CloudAccountModel(services: nil, local: InMemoryLocalSchedule(), stateStore: InMemoryCloudSyncStateStore())
        await model.load()
        XCTAssertFalse(model.isConfigured)
        XCTAssertEqual(model.account, .signedOut)
        XCTAssertNil(model.overview)
    }
}
