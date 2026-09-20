import SwiftUI

struct CourseDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let course: Course
    @State private var isPickingBuilding = false
    @State private var room = ""
    @State private var isExporting = false
    @State private var exportReport: CalendarExportReport?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                courseInformationCard
                locationCard
                meetingsCard
                specialMeetingsCard
                calendarCard
                descriptionCard
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(course.code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $isPickingBuilding) {
            NavigationStack { BuildingPickerView(course: course) }
        }
        .alert("Calendar export complete", isPresented: Binding(
            get: { exportReport != nil },
            set: { if !$0 { exportReport = nil } }
        )) {
            Button("OK", role: .cancel) { exportReport = nil }
        } message: {
            if let report = exportReport {
                Text("Added \(report.addedCount) meeting\(report.addedCount == 1 ? "" : "s") to \(report.calendarTitle). \(report.existingCount) already-exported meeting\(report.existingCount == 1 ? " was" : "s were") left unchanged.")
            }
        }
        .alert("Couldn’t export course", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Calendar export is unavailable.")
        }
        .onAppear { room = store.courseLocations[course.id]?.room ?? "" }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 15) {
            CourseGlyph(course: course, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(course.displayCode).font(.title2.bold())
                Text(course.title).font(.subheadline).foregroundStyle(.secondary)
                Text(course.credits == 0 ? "Satisfactory / Unsatisfactory" : "\(course.credits) semester credits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var courseInformationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Course information", detail: course.crn.map { "CRN \($0)" })
            SurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(courseInformation.enumerated()), id: \.offset) { index, item in
                        LabeledContent(item.label) {
                            Text(item.value)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 9)
                        if index < courseInformation.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var courseInformation: [(label: String, value: String)] {
        [
            ("Status", course.status ?? "Not supplied"),
            ("CRN", course.crn ?? "Not supplied"),
            ("Subject", course.subject),
            ("Course number", course.courseNumber.isEmpty ? "Not supplied" : course.courseNumber),
            ("Section", course.section.isEmpty ? "Not supplied" : course.section),
            ("Credits", "\(course.credits)"),
            ("Instruction mode", course.instructionMode ?? "Not supplied"),
            ("Instructor", course.instructor ?? "Not supplied")
        ]
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Class locations")
            SurfaceCard {
                if let location = store.courseLocations[course.id] {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "building.2.fill").font(.title2).foregroundStyle(AppTheme.accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(location.feature.name).font(.headline)
                                Text([location.feature.abbreviation, location.feature.buildingNumber].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let address = location.feature.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        TextField("Room (optional)", text: $room)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { store.assign(location.feature, to: course, room: room) }
                        HStack {
                            Button("Change building") { isPickingBuilding = true }
                                .buttonStyle(.bordered)
                            Button("Save room") { store.assign(location.feature, to: course, room: room) }
                                .buttonStyle(.borderedProminent)
                            Spacer()
                            Button(role: .destructive) { store.clearLocation(for: course) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Clear class location")
                        }
                    }
                } else if sourceLocationHint != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Verified from your Howdy schedule", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Meeting-specific buildings and rooms are listed below and used for the Today view, routes, map pins, and calendar export.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Set a manual override", systemImage: "building.2.crop.circle") { isPickingBuilding = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Location not available", systemImage: "mappin.slash")
                            .font(.headline)
                        Text("Choose the confirmed building from Texas A&M’s official campus directory. Maroon Compass will never guess a classroom.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Choose building", systemImage: "building.2.crop.circle") { isPickingBuilding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var meetingsCard: some View {
        let patterns = store.engine.patterns.filter { $0.courseID == course.id }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Weekly meetings")
            SurfaceCard {
                VStack(spacing: 13) {
                    ForEach(Array(patterns.enumerated()), id: \.element.id) { index, pattern in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(pattern.weekdays.map(\.shortName).joined(separator: ", "))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(timeRange(pattern))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !pattern.excludedDates.isEmpty || !pattern.additionalDates.isEmpty {
                                Text("\(pattern.excludedDates.count) excluded · \(pattern.additionalDates.count) added date\(pattern.additionalDates.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let location = pattern.sourceLocationText {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            if let notes = pattern.sourceNotes {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        if index < patterns.count - 1 { Divider() }
                    }
                    if patterns.isEmpty {
                        Text("No recurring weekly pattern.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var specialMeetingsCard: some View {
        let events = store.engine.oneTimeEvents.filter { $0.courseID == course.id }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Special meetings", detail: "\(events.count)")
                SurfaceCard {
                    VStack(spacing: 13) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(formattedDate(event.date)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(eventTimeRange(event)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                if let location = event.sourceLocationText {
                                    Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                                }
                                if let notes = event.sourceNotes {
                                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                            if index < events.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Calendar")
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Export this course", systemImage: "calendar.badge.plus")
                        .font(.headline)
                    Text("Adds the actual Fall 2026 meetings after university holidays and schedule exceptions. Repeating the export will not duplicate meetings created by Maroon Compass.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(isExporting ? "Exporting…" : "Add to Apple Calendar", systemImage: "square.and.arrow.up") {
                        Task {
                            isExporting = true
                            defer { isExporting = false }
                            do {
                                exportReport = try await store.exportCourseToCalendar(course)
                            } catch {
                                exportError = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About this course")
            SurfaceCard {
                Text(course.catalogSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let url = catalogURL {
                    Link("View official catalog", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 10)
                }
            }
        }
    }

    private var catalogURL: URL? {
        let subject = course.code.split(separator: " ").first?.lowercased() ?? ""
        return URL(string: "https://catalog.tamu.edu/undergraduate/course-descriptions/\(subject)/")
    }

    private var sourceLocationHint: String? {
        store.engine.patterns.first(where: { $0.courseID == course.id })?.sourceLocationText
            ?? store.engine.oneTimeEvents.first(where: { $0.courseID == course.id })?.sourceLocationText
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = store.engine.date(value) else { return value }
        return CampusFormatters.compactDay.string(from: date)
    }

    private func eventTimeRange(_ event: OneTimeEvent) -> String {
        guard
            let start = store.engine.date(event.date, hour: event.startHour, minute: event.startMinute),
            let end = store.engine.date(event.date, hour: event.endHour, minute: event.endMinute)
        else { return "" }
        return "\(CampusFormatters.time.string(from: start))–\(CampusFormatters.time.string(from: end))"
    }

    private func timeRange(_ pattern: MeetingPattern) -> String {
        guard
            let day = store.engine.date("2026-08-24", hour: pattern.startHour, minute: pattern.startMinute),
            let end = store.engine.date("2026-08-24", hour: pattern.endHour, minute: pattern.endMinute)
        else { return "" }
        return "\(CampusFormatters.time.string(from: day))–\(CampusFormatters.time.string(from: end))"
    }
}

struct BuildingPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let course: Course
    @State private var query = ""

    private var results: [CampusFeature] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(store.campusFeatures.prefix(80))
        }
        let needle = query.localizedLowercase
        return store.campusFeatures.filter { $0.searchText.contains(needle) }.prefix(100).map { $0 }
    }

    var body: some View {
        List {
            Section {
                Label("Official Texas A&M building data", systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if store.isLoadingCampus && store.campusFeatures.isEmpty {
                LoadingRow(message: "Loading campus buildings…")
            } else if results.isEmpty {
                EmptyStateView(symbol: "building.2.crop.circle", title: "No matching building", message: "Try the full name, abbreviation, or building number.")
            } else {
                Section("Buildings") {
                    ForEach(results) { feature in
                        Button {
                            store.assign(feature, to: course)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.name).foregroundStyle(.primary)
                                    Text([feature.abbreviation, feature.buildingNumber, feature.address].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(AppTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Name, abbreviation, or number")
        .navigationTitle("Choose building")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task { await store.loadCampus() }
    }
}
