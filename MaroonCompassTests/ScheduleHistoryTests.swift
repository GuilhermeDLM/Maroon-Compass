import XCTest
@testable import MaroonCompass

@MainActor
final class ScheduleHistoryTests: XCTestCase {
    func testReplacingAndRestoringSchedulesKeepsEachPreviousVersion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = AppStore(defaults: fixture.defaults, scheduleHistoryStore: fixture.history)

        try store.saveImportedSchedule(bundle(named: "First import"))
        XCTAssertTrue(try store.savedScheduleVersions().isEmpty)

        try store.saveImportedSchedule(bundle(named: "Second import"))
        let firstVersion = try XCTUnwrap(store.savedScheduleVersions().first)
        XCTAssertEqual(firstVersion.bundle.sourceName, "First import")
        XCTAssertEqual(firstVersion.reason, .replacedByImport)

        try store.restoreSavedScheduleVersion(id: firstVersion.id)
        XCTAssertEqual(store.scheduleSourceName, "First import")
        XCTAssertEqual(try store.savedScheduleVersions().first?.bundle.sourceName, "Second import")

        try store.restoreEmbeddedSchedule()
        XCTAssertFalse(store.hasImportedSchedule)
        XCTAssertEqual(store.scheduleSourceName, ScheduleSeed.sourceName)
        XCTAssertEqual(try store.savedScheduleVersions().first?.bundle.sourceName, "First import")
        XCTAssertEqual(try store.savedScheduleVersions().first?.reason, .restoredEmbedded)
    }

    func testUnreadableHistoryBlocksReplacementWithoutLosingCurrentSchedule() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = AppStore(defaults: fixture.defaults, scheduleHistoryStore: fixture.history)
        try store.saveImportedSchedule(bundle(named: "Keep me"))
        let activeBefore = try XCTUnwrap(fixture.defaults.data(forKey: "importedSchedule"))
        let badHistory = Data("not JSON".utf8)
        try badHistory.write(to: fixture.history.fileURL)

        XCTAssertThrowsError(try store.saveImportedSchedule(bundle(named: "Replacement")))
        XCTAssertEqual(fixture.defaults.data(forKey: "importedSchedule"), activeBefore)
        XCTAssertEqual(store.scheduleSourceName, "Keep me")
        XCTAssertEqual(try Data(contentsOf: fixture.history.fileURL), badHistory)
    }

    func testHistoryIsBoundedAndSurvivesStoreRecreation() throws {
        let fixture = try makeFixture(maximumVersions: 2)
        defer { fixture.cleanup() }
        try fixture.history.save(bundle(named: "One"), reason: .replacedByImport)
        try fixture.history.save(bundle(named: "Two"), reason: .replacedByImport)
        try fixture.history.save(bundle(named: "Three"), reason: .restoredEarlierVersion)

        let reopened = ScheduleHistoryStore(fileURL: fixture.history.fileURL, maximumVersions: 2)
        let entries = try reopened.versions()
        XCTAssertEqual(entries.map(\.bundle.sourceName), ["Three", "Two"])
        XCTAssertEqual(entries.first?.reason, .restoredEarlierVersion)
        XCTAssertEqual(entries.first?.bundle.patterns, ScheduleSeed.patterns)
    }

    private func bundle(named name: String) -> ImportedScheduleBundle {
        ImportedScheduleBundle(
            sourceName: name, importedAt: Date(timeIntervalSince1970: 1_000),
            term: ScheduleSeed.term, courses: ScheduleSeed.courses,
            patterns: ScheduleSeed.patterns, oneTimeEvents: ScheduleSeed.oneTimeEvents
        )
    }

    private func makeFixture(maximumVersions: Int = 25) throws -> (
        defaults: UserDefaults,
        history: ScheduleHistoryStore,
        cleanup: () -> Void
    ) {
        let name = "MaroonCompassHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let history = ScheduleHistoryStore(fileURL: directory.appending(path: "history.json"), maximumVersions: maximumVersions)
        return (defaults, history, {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        })
    }
}
