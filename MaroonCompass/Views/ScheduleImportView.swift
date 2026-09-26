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
    @State private var isReplaceDraftPresented = false
    @State private var pendingImport: (draft: ScheduleDraft, image: UIImage, usedAppleIntelligence: Bool)?
    @State private var lastAppliedDraft: ScheduleDraft?
    @State private var analysisTask: Task<Void, Never>?

    private var issues: [ScheduleDraftIssue] { draft.issues }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose schedule screenshot or photo", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityHint("Only the selected image is read on this device. You will review every class before saving.")
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
                TextField("First class date (YYYY-MM-DD)", text: $draft.firstClassDate)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Last class date (YYYY-MM-DD)", text: $draft.lastClassDate)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                Text("Check these dates. The image analysis does not guess semester boundaries.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                issueMessages(for: nil, meetingID: nil)
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
                    issueMessages(for: course.id, meetingID: nil)

                    ForEach($course.meetings) { $meeting in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Meeting \((course.meetings.firstIndex(where: { $0.id == meeting.id }) ?? 0) + 1)")
                                    .font(.headline)
                                Spacer()
                                Button("Delete meeting", systemImage: "trash", role: .destructive) {
                                    course.meetings.removeAll { $0.id == meeting.id }
                                }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            Picker("Meeting type", selection: $meeting.kind) {
                                ForEach(MeetingKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            Text("Days").font(.subheadline.weight(.semibold))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                                ForEach(Weekday.allCases) { day in
                                    let selected = meeting.weekdays.contains(day)
                                    Button(day.shortName) {
                                        if selected { meeting.weekdays.remove(day) }
                                        else { meeting.weekdays.insert(day) }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 44)
                                    .background(selected ? AppTheme.accent : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(weekdayName(day))
                                    .accessibilityValue(selected ? "Selected" : "Not selected")
                                }
                            }
                            TextField("Start time (09:35 or 9:35 AM)", text: $meeting.startTime)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("End time (10:50 or 10:50 AM)", text: $meeting.endTime)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("Building code (if known)", text: $meeting.buildingCode)
                                .textInputAutocapitalization(.characters)
                            TextField("Room (if known)", text: $meeting.room)
                            issueMessages(for: course.id, meetingID: meeting.id)
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

            Section {
                Button(
                    isAnalyzing ? "Reading image…" :
                        (issues.isEmpty ? "Save reviewed schedule" : "Fix issues to save"),
                    systemImage: issues.isEmpty && !isAnalyzing ? "checkmark.circle.fill" : "exclamationmark.circle"
                ) {
                    isConfirmPresented = true
                }
                .disabled(isAnalyzing || !issues.isEmpty)
                .foregroundStyle(isAnalyzing || !issues.isEmpty ? Color.secondary : AppTheme.accent)
            } footer: {
                Text(issues.isEmpty
                     ? "Ready to review the replacement. Your schedule stays on this device."
                     : "Fix the \(issues.count) highlighted \(issues.count == 1 ? "issue" : "issues") before saving.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Import Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if lastAppliedDraft == nil {
                draft.termName = store.engine.term.name
                draft.firstClassDate = store.engine.term.firstClassDate
                draft.lastClassDate = store.engine.term.lastClassDate
                lastAppliedDraft = draft
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            analysisTask?.cancel()
            let id = UUID()
            analysisID = id
            analysisTask = Task { await analyze(photo, id: id) }
        }
        .onDisappear {
            analysisTask?.cancel()
            analysisID = UUID()
        }
        .alert("Schedule image", isPresented: Binding(get: { analysisError != nil }, set: { if !$0 { analysisError = nil } })) {
            Button("OK", role: .cancel) { analysisError = nil }
        } message: { Text(analysisError ?? "") }
        .alert("Schedule could not be saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .confirmationDialog("Use the new image draft?", isPresented: $isReplaceDraftPresented, titleVisibility: .visible) {
            Button("Replace my edits", role: .destructive) { applyPendingImport() }
            Button("Keep my edits", role: .cancel) { pendingImport = nil }
        } message: {
            Text("The new image analysis would replace the course details you have edited on this screen.")
        }
        .confirmationDialog("Replace the current schedule with these reviewed classes?", isPresented: $isConfirmPresented, titleVisibility: .visible) {
            Button("Replace Schedule", role: .destructive) { confirm() }
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
            let result = try await ScheduleImageImportService().analyze(data, currentTerm: store.engine.term)
            guard analysisID == id else { return }
            pendingImport = (result.draft, image, result.usedAppleIntelligence)
            if let lastAppliedDraft, draft != lastAppliedDraft {
                isReplaceDraftPresented = true
            } else {
                applyPendingImport()
            }
        } catch {
            guard analysisID == id else { return }
            if !Task.isCancelled { analysisError = error.localizedDescription }
        }
        selectedPhoto = nil
    }

    private func applyPendingImport() {
        guard let pendingImport else { return }
        draft = pendingImport.draft
        previewImage = pendingImport.image
        usedAppleIntelligence = pendingImport.usedAppleIntelligence
        lastAppliedDraft = draft
        self.pendingImport = nil
    }

    @ViewBuilder
    private func issueMessages(for courseID: UUID?, meetingID: UUID?) -> some View {
        ForEach(issues.filter { $0.courseID == courseID && $0.meetingID == meetingID }) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Needs review: \(issue.message)")
        }
    }

    private func weekdayName(_ day: Weekday) -> String {
        switch day {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
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
