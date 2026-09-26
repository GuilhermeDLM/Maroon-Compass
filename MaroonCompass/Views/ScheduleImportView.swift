import PhotosUI
import SwiftUI

struct ScheduleImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var draft = ScheduleDraft(
        termName: ScheduleSeed.term.name,
        firstClassDate: ScheduleSeed.term.firstClassDate,
        lastClassDate: ScheduleSeed.term.lastClassDate
    )
    @State private var analysisID = UUID()
    @State private var isAnalyzing = false
    @State private var usedAppleIntelligence = false
    @State private var analysisError: String?
    @State private var saveError: String?
    @State private var isConfirmPresented = false

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose schedule screenshot or photo", systemImage: "photo.on.rectangle.angled")
                }
                Button("Add a course manually", systemImage: "plus.circle") {
                    draft.courses.append(ScheduleDraftCourse())
                }
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Selected schedule image")
                }
                if isAnalyzing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading and organizing classes…")
                    }
                } else if previewImage != nil {
                    Label(
                        usedAppleIntelligence ? "On-device Apple Intelligence and Vision analyzed this image" : "On-device Vision analyzed this image",
                        systemImage: "checkmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Text("The image stays on this device and is not saved with your schedule. Nothing changes until you confirm below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Import")
            }

            Section("Semester") {
                TextField("Semester name", text: $draft.termName)
                    .textContentType(.organizationName)
                TextField("First class date (YYYY-MM-DD)", text: $draft.firstClassDate)
                    .textInputAutocapitalization(.never)
                TextField("Last class date (YYYY-MM-DD)", text: $draft.lastClassDate)
                    .textInputAutocapitalization(.never)
                Text("Check these dates. The image analysis does not guess semester boundaries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !draft.notes.isEmpty {
                Section("Import notes") {
                    ForEach(draft.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
            }

            ForEach($draft.courses) { $course in
                Section {
                    TextField("Course code, e.g. MATH 251", text: $course.code)
                        .textInputAutocapitalization(.characters)
                    TextField("Course name", text: $course.title)
                    TextField("Section (if known)", text: $course.section)
                        .textInputAutocapitalization(.characters)

                    ForEach($course.meetings) { $meeting in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Meeting").font(.headline)
                                Spacer()
                                Button("Delete meeting", systemImage: "trash", role: .destructive) {
                                    course.meetings.removeAll { $0.id == meeting.id }
                                }
                                .labelStyle(.iconOnly)
                            }
                            Picker("Type", selection: $meeting.kind) {
                                ForEach(MeetingKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            HStack(spacing: 4) {
                                ForEach(Weekday.allCases) { day in
                                    let selected = meeting.weekdays.contains(day)
                                    Button(day.shortName) {
                                        if selected { meeting.weekdays.remove(day) }
                                        else { meeting.weekdays.insert(day) }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(selected ? AppTheme.accent : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(day.shortName), \(selected ? "selected" : "not selected")")
                                }
                            }
                            HStack {
                                TextField("Start (09:35)", text: $meeting.startTime)
                                    .keyboardType(.numbersAndPunctuation)
                                TextField("End (10:50)", text: $meeting.endTime)
                                    .keyboardType(.numbersAndPunctuation)
                            }
                            HStack {
                                TextField("Building code", text: $meeting.buildingCode)
                                    .textInputAutocapitalization(.characters)
                                TextField("Room", text: $meeting.room)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    Button("Add meeting", systemImage: "plus") {
                        course.meetings.append(ScheduleDraftMeeting())
                    }
                    Button("Delete course", systemImage: "trash", role: .destructive) {
                        draft.courses.removeAll { $0.id == course.id }
                    }
                } header: {
                    Text(course.code.isEmpty ? "New course" : course.code)
                }
            }

            if !draft.issues.isEmpty {
                Section("Needs review") {
                    ForEach(draft.issues) { issue in
                        Label(issue.message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button("Confirm Schedule", systemImage: "checkmark.circle.fill") {
                    isConfirmPresented = true
                }
                .disabled(isAnalyzing || !draft.issues.isEmpty)
            } footer: {
                Text("Confirming saves these edited classes on this device. Calendar export remains optional.")
            }
        }
        .navigationTitle("Import Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if draft.courses.isEmpty {
                draft.termName = store.engine.term.name
                draft.firstClassDate = store.engine.term.firstClassDate
                draft.lastClassDate = store.engine.term.lastClassDate
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            let id = UUID()
            analysisID = id
            Task { await analyze(photo, id: id) }
        }
        .alert("Schedule image", isPresented: Binding(get: { analysisError != nil }, set: { if !$0 { analysisError = nil } })) {
            Button("OK", role: .cancel) { analysisError = nil }
        } message: { Text(analysisError ?? "") }
        .alert("Schedule could not be saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .confirmationDialog("Replace the current schedule with these reviewed classes?", isPresented: $isConfirmPresented, titleVisibility: .visible) {
            Button("Confirm Schedule") { confirm() }
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text("Your current schedule will stay available until this confirmation succeeds.")
        }
    }

    @MainActor
    private func analyze(_ photo: PhotosPickerItem, id: UUID) async {
        isAnalyzing = true
        analysisError = nil
        defer { if analysisID == id { isAnalyzing = false } }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { throw ScheduleImageImportError.invalidImage }
            guard analysisID == id else { return }
            previewImage = image
            let result = try await ScheduleImageImportService().analyze(data, currentTerm: store.engine.term)
            guard analysisID == id else { return }
            draft = result.draft
            usedAppleIntelligence = result.usedAppleIntelligence
        } catch {
            guard analysisID == id else { return }
            analysisError = error.localizedDescription
        }
    }

    private func confirm() {
        do {
            let bundle = try draft.confirmedBundle(sourceName: previewImage == nil ? "Manual schedule" : "Reviewed photo import")
            try store.saveImportedSchedule(bundle)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
