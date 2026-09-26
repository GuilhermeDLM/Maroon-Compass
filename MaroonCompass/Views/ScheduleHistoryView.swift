import SwiftUI

struct ScheduleHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var versions: [SavedScheduleVersion] = []
    @State private var selectedVersion: SavedScheduleVersion?
    @State private var isRestoreConfirmationPresented = false
    @State private var loadError: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Schedule history unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again", action: loadVersions)
                }
            } else if versions.isEmpty {
                ContentUnavailableView(
                    "No previous schedules",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("When you replace or restore an imported schedule, its previous version will appear here.")
                )
            } else {
                List {
                    Section {
                        ForEach(versions) { version in
                            Button {
                                selectedVersion = version
                                isRestoreConfirmationPresented = true
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(version.bundle.sourceName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(version.bundle.term?.name ?? ScheduleSeed.term.name) · \(version.bundle.courses.count) courses")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(version.reason.description) · \(version.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .accessibilityHint("Restore this saved schedule after confirmation")
                        }
                    } footer: {
                        Text("Restoring a version saves your current imported schedule here first. Only confirmed class details are kept; original screenshots are never stored.")
                    }
                }
            }
        }
        .navigationTitle("Previous Schedules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVersions)
        .confirmationDialog(
            "Restore this saved schedule?",
            isPresented: $isRestoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let selectedVersion {
                Button("Restore schedule") { restore(selectedVersion) }
            }
            Button("Keep current schedule", role: .cancel) { selectedVersion = nil }
        } message: {
            Text("Your current imported schedule will be saved in Previous Schedules before this version is restored.")
        }
        .alert("Schedule history unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Your current schedule was kept.")
        }
    }

    private func loadVersions() {
        do {
            versions = try store.savedScheduleVersions()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func restore(_ version: SavedScheduleVersion) {
        do {
            try store.restoreSavedScheduleVersion(id: version.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            selectedVersion = nil
        }
    }
}
