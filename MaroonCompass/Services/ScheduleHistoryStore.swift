import Foundation

enum ScheduleHistoryError: LocalizedError {
    case versionNotFound

    var errorDescription: String? {
        "That saved schedule is no longer available. Refresh the history and try again."
    }
}

enum ScheduleHistoryReason: String, Codable, Sendable {
    case replacedByImport
    case restoredEmbedded
    case restoredEarlierVersion

    var description: String {
        switch self {
        case .replacedByImport: "Saved before another import"
        case .restoredEmbedded: "Saved before restoring the original schedule"
        case .restoredEarlierVersion: "Saved before restoring an earlier version"
        }
    }
}

struct SavedScheduleVersion: Identifiable, Codable, Sendable {
    let id: UUID
    let savedAt: Date
    let reason: ScheduleHistoryReason
    let bundle: ImportedScheduleBundle
}

/// Keeps recent, confirmed schedules in the app container. No selected image or OCR text is stored.
struct ScheduleHistoryStore {
    let fileURL: URL
    let maximumVersions: Int

    init(fileURL: URL? = nil, maximumVersions: Int = 25) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Maroon Compass", directoryHint: .isDirectory)
        self.fileURL = fileURL ?? directory.appending(path: "schedule-history.json")
        self.maximumVersions = max(1, maximumVersions)
    }

    func versions() throws -> [SavedScheduleVersion] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([SavedScheduleVersion].self, from: Data(contentsOf: fileURL))
    }

    @discardableResult
    func save(_ bundle: ImportedScheduleBundle, reason: ScheduleHistoryReason) throws -> SavedScheduleVersion {
        var entries = try versions()
        let entry = SavedScheduleVersion(id: UUID(), savedAt: Date(), reason: reason, bundle: bundle)
        entries.insert(entry, at: 0)
        if entries.count > maximumVersions { entries.removeLast(entries.count - maximumVersions) }

        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        #endif
        return entry
    }

    func version(id: UUID) throws -> SavedScheduleVersion? {
        try versions().first { $0.id == id }
    }
}
