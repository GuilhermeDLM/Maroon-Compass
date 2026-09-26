import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var isImporterPresented = false
    @State private var isPhotoImportPresented = false
    @State private var importReport: CalendarImportReport?
    @State private var importError: String?
    @State private var scheduleRestoreError: String?
    @State private var isRestoreConfirmationPresented = false

    var body: some View {
        @Bindable var store = store

        List {
            Section("Schedule") {
                LabeledContent("Term", value: store.engine.term.name)
                LabeledContent("Campus", value: store.engine.term.campus)
                LabeledContent("Courses", value: "\(store.engine.courses.count)")
                LabeledContent("Credits", value: "\(store.totalCredits)")
                LabeledContent("Source", value: store.scheduleSourceName)
                Label("CRNs, sections, instructors, buildings, rooms, and meeting times verified from Howdy registration", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Import updated Fall 2026 .ics", systemImage: "square.and.arrow.down") {
                    isImporterPresented = true
                }
                Button("Import from a photo or enter classes", systemImage: "photo.on.rectangle.angled") {
                    isPhotoImportPresented = true
                }
                NavigationLink {
                    ScheduleHistoryView()
                } label: {
                    Label("Previous schedules", systemImage: "clock.arrow.circlepath")
                }
                if store.hasImportedSchedule {
                    Button("Restore embedded schedule", systemImage: "arrow.counterclockwise", role: .destructive) {
                        isRestoreConfirmationPresented = true
                    }
                }
            }

            Section {
                NavigationLink {
                    CloudAccountView()
                } label: {
                    Label("Account & cloud backup", systemImage: "icloud.and.arrow.up")
                }
                Text("Optional. The app works fully on this device without an account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Account")
            }

            Section("Personal Plan") {
                LabeledContent("Personal blocks", value: "\(store.personalBlocks.count)")
                Label("Weekly routines and one-time blocks are stored separately from protected class meetings", systemImage: "calendar.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Toggle("Class reminders", isOn: Binding(
                    get: { store.remindersEnabled },
                    set: { value in Task { await store.setRemindersEnabled(value) } }
                ))
                Stepper(
                    "Class lead time: \(store.reminderLeadMinutes) min",
                    value: Binding(
                        get: { store.reminderLeadMinutes },
                        set: { value in Task { await store.updateReminderLeadMinutes(value) } }
                    ),
                    in: 5...60,
                    step: 5
                )
                .disabled(!store.remindersEnabled)
                Text("When enabled, reminders arrive before classes using your chosen lead time, plus timely academic-calendar notices. Your schedule is processed on device.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Travel planning") {
                Picker("Travel mode", selection: Binding(
                    get: { store.travelMode },
                    set: { store.updateTravelMode($0) }
                )) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Stepper(
                    "Arrival buffer: \(store.safetyBufferMinutes) min",
                    value: Binding(
                        get: { store.safetyBufferMinutes },
                        set: { store.updateSafetyBuffer($0) }
                    ),
                    in: 0...30,
                    step: 5
                )
                Text("Apple Maps supplies routes and estimates. Leave-by guidance adds this buffer and appears only after a confirmed class building is assigned.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Location") {
                LabeledContent("Access", value: authorizationDescription)
                Button("Request location while using app", systemImage: "location.fill") {
                    store.locationService.requestLocation()
                }
                Text("Location is used only while the app is open to anchor nearby searches and walking context. The schedule and full campus map work without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("System integration") {
                Label("Next Class Home Screen and Lock Screen widget", systemImage: "rectangle.stack.badge.plus")
                Label("Shortcuts: What’s Next, Next Class Route, and Today’s Schedule", systemImage: "command")
                Label("Per-course Apple Calendar export is available from each course", systemImage: "calendar.badge.plus")
                Text("The widget uses the verified embedded Fall 2026 schedule. Imported calendar changes and assigned rooms remain private to the main app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Official data sources") {
                ForEach(officialSources, id: \.title) { source in
                    Link(source.title, destination: source.url)
                }
                if let fetched = store.campusFeatures.first?.fetchedAt {
                    LabeledContent("Campus data fetched", value: fetched.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                Button(store.isLoadingCampus ? "Refreshing campus data…" : "Refresh campus data", systemImage: "arrow.clockwise") {
                    Task { await store.loadCampus(forceRefresh: true) }
                }
                .disabled(store.isLoadingCampus)
            }

            Section("Privacy") {
                Label("Personal plan, locations, reminders, and favorites stay on this device", systemImage: "lock.shield.fill")
                Label("Your class schedule leaves this device only if you turn on cloud backup", systemImage: "icloud.slash")
                Label("No analytics, ads, or NetID credentials; an account is optional", systemImage: "hand.raised.fill")
                Label("Commercial places come from Apple Maps", systemImage: "map.fill")
            }

            Section("About") {
                LabeledContent("Maroon Compass", value: appVersion)
                LabeledContent("Timezone", value: "America/Chicago")
                Text("Unofficial student companion. Not affiliated with or endorsed by Texas A&M University.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(item: $importReport) { report in
            NavigationStack { CalendarImportReportView(report: report) }
        }
        .sheet(isPresented: $isPhotoImportPresented) {
            NavigationStack { ScheduleImportView() }
        }
        .alert("Calendar import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "The selected file could not be imported.")
        }
        .alert("Schedule could not be restored", isPresented: Binding(get: { scheduleRestoreError != nil }, set: { if !$0 { scheduleRestoreError = nil } })) {
            Button("OK", role: .cancel) { scheduleRestoreError = nil }
        } message: {
            Text(scheduleRestoreError ?? "Your current schedule was kept.")
        }
        .confirmationDialog("Restore the original embedded schedule?", isPresented: $isRestoreConfirmationPresented, titleVisibility: .visible) {
            Button("Restore embedded schedule", role: .destructive) {
                do { try store.restoreEmbeddedSchedule() }
                catch { scheduleRestoreError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The imported schedule will be saved in Previous schedules first. Saved building assignments and favorites are kept.")
        }
    }

    private var authorizationDescription: String {
        switch store.locationService.authorizationStatus {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways, .authorizedWhenInUse: "While using app"
        @unknown default: "Unknown"
        }
    }

    private var officialSources: [(title: String, url: URL)] {
        [
            ("Texas A&M academic calendar", "https://catalog.tamu.edu/undergraduate/academic-calendar/"),
            ("Aggie Map", "https://aggiemap.tamu.edu/"),
            ("Transportation Services", "https://transport.tamu.edu/"),
            ("Aggie Dining", "https://www.tamu.edu/campus-community/dining.html"),
            ("Campus safety", "https://www.tamu.edu/campus-community/campus-safety.html")
        ].compactMap { title, value in URL(string: value).map { (title, $0) } }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func handleImport(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            importReport = try store.importCalendar(data: data, sourceName: url.lastPathComponent)
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct CalendarImportReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: CalendarImportReport

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Schedule updated").font(.title2.bold())
                    Text(report.sourceName).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            Section("Imported") {
                LabeledContent("Courses", value: "\(report.courseCount)")
                LabeledContent("Recurring meetings", value: "\(report.recurringMeetingCount)")
                LabeledContent("One-time events", value: "\(report.oneTimeEventCount)")
                LabeledContent("Normalized anchors", value: "\(report.normalizedAnchorCount)")
            }
            Section("Import notes") {
                ForEach(report.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Import report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
