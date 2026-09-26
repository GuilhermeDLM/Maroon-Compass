import Foundation

/// Connects cloud sync to the app's existing schedule storage without changing it. Reads use
/// the same stored bytes `AppStore` loads at launch; writes go through `AppStore`'s own
/// `saveImportedSchedule` and `restoreEmbeddedSchedule`.
@MainActor
final class AppStoreScheduleAccess: LocalScheduleAccess {
    /// `AppStore`'s persistence key for a user-imported schedule.
    private static let importedScheduleKey = "importedSchedule"

    private let store: AppStore
    private let defaults: UserDefaults

    init(store: AppStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    func currentSchedule() -> (bundle: ImportedScheduleBundle, isEmbedded: Bool) {
        if let data = defaults.data(forKey: Self.importedScheduleKey),
           let bundle = try? JSONDecoder().decode(ImportedScheduleBundle.self, from: data) {
            return (bundle, false)
        }
        // No readable import: the app is showing the embedded schedule.
        let engine = store.engine
        return (
            ImportedScheduleBundle(
                sourceName: ScheduleSeed.sourceName,
                importedAt: Date(timeIntervalSince1970: 0),
                term: engine.term,
                courses: engine.courses,
                patterns: engine.patterns,
                oneTimeEvents: engine.oneTimeEvents
            ),
            true
        )
    }

    func makeBackup() -> LocalScheduleBackup {
        defaults.data(forKey: Self.importedScheduleKey).map(LocalScheduleBackup.imported) ?? .embedded
    }

    func replaceSchedule(with bundle: ImportedScheduleBundle) throws {
        try store.saveImportedSchedule(bundle)
    }

    func restore(_ backup: LocalScheduleBackup) throws {
        switch backup {
        case .embedded:
            try store.restoreEmbeddedSchedule()
        case .imported(let data):
            try store.saveImportedSchedule(JSONDecoder().decode(ImportedScheduleBundle.self, from: data))
        }
    }
}
