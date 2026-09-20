import SwiftUI

struct PersonalPlanView: View {
    @Environment(AppStore.self) private var store
    @State private var editorContext: PersonalBlockEditorContext?
    @State private var selectedCourse: Course?
    @State private var blockPendingDeletion: PersonalBlock?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                planIntroduction
                weekStrip
                daySummary
                conflictSection
                agendaSection
                openTimeSection
                templatesSection
                routinesSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add block", systemImage: "plus") {
                    editorContext = .new(on: store.selectedDate)
                }
            }
        }
        .sheet(item: $editorContext) { context in
            PersonalBlockEditorView(context: context) { block in
                store.savePersonalBlock(block)
            }
            .environment(store)
        }
        .sheet(item: $selectedCourse) { course in
            NavigationStack { CourseDetailView(course: course) }
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete \(blockPendingDeletion?.title ?? "this block")?",
            isPresented: Binding(
                get: { blockPendingDeletion != nil },
                set: { if !$0 { blockPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete block", role: .destructive) {
                if let blockPendingDeletion { store.deletePersonalBlock(blockPendingDeletion) }
                blockPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { blockPendingDeletion = nil }
        } message: {
            Text("Your classes are never affected. This only removes the personal block from this device.")
        }
    }

    private var planIntroduction: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Build around your classes")
                        .font(.headline)
                    Text("Add meals, study time, sleep, work, workouts, or anything else. Imported class meetings stay protected and read-only.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var weekStrip: some View {
        let days = store.engine.week(containing: store.selectedDate)
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(CampusFormatters.dayHeading.string(from: store.selectedDate))
                    .font(.title3.bold())
                Spacer()
                Button("Today") { store.selectedDate = Date() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let selected = store.engine.calendar.isDate(day, inSameDayAs: store.selectedDate)
                    let hasPlan = !store.personalOccurrences(on: day).isEmpty
                    Button {
                        store.selectedDate = day
                    } label: {
                        VStack(spacing: 5) {
                            Text(store.engine.calendar.shortWeekdaySymbols[store.engine.calendar.component(.weekday, from: day) - 1])
                                .font(.caption2.weight(.semibold))
                            Text("\(store.engine.calendar.component(.day, from: day))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Circle()
                                .fill(hasPlan ? (selected ? Color.white : AppTheme.accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(CampusFormatters.compactDay.string(from: day)), \(hasPlan ? "has personal blocks" : "no personal blocks")")
                }
            }
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var daySummary: some View {
        let classes = store.engine.occurrences(on: store.selectedDate).count
        let personal = store.personalOccurrences(on: store.selectedDate).count
        let conflicts = store.personalPlanConflicts(on: store.selectedDate).count
        return HStack(spacing: 10) {
            PlanMetric(value: classes, label: classes == 1 ? "Class" : "Classes", symbol: "graduationcap.fill", tint: AppTheme.accent)
            PlanMetric(value: personal, label: personal == 1 ? "Block" : "Blocks", symbol: "rectangle.stack.fill", tint: .indigo)
            PlanMetric(value: conflicts, label: conflicts == 1 ? "Conflict" : "Conflicts", symbol: conflicts == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", tint: conflicts == 0 ? .green : .orange)
        }
    }

    @ViewBuilder
    private var conflictSection: some View {
        let conflicts = store.personalPlanConflicts(on: store.selectedDate)
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Needs attention", detail: "Personal blocks remain editable")
                SurfaceCard {
                    VStack(spacing: 12) {
                        ForEach(Array(conflicts.prefix(3))) { conflict in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(conflict.firstTitle) overlaps \(conflict.secondTitle)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(CampusFormatters.time.string(from: conflict.start))–\(CampusFormatters.time.string(from: conflict.end)) · \(CampusFormatters.duration(conflict.duration))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if conflict.id != conflicts.prefix(3).last?.id { Divider().padding(.leading, 35) }
                        }
                        if conflicts.count > 3 {
                            Text("\(conflicts.count - 3) more conflicts on this day")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var agendaSection: some View {
        let agenda = store.dailyAgenda(on: store.selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Full day", detail: agenda.isEmpty ? "Open day" : "Classes + personal plan")
            SurfaceCard {
                if agenda.isEmpty {
                    EmptyStateView(
                        symbol: "calendar.badge.plus",
                        title: "Nothing planned yet",
                        message: "Add a one-time block or a weekly routine without changing your class schedule.",
                        actionTitle: "Add a block",
                        action: { editorContext = .new(on: store.selectedDate) }
                    )
                } else {
                    VStack(spacing: 15) {
                        ForEach(Array(agenda.enumerated()), id: \.element.id) { index, item in
                            switch item {
                            case .classMeeting(let occurrence):
                                Button { selectedCourse = occurrence.course } label: {
                                    OccurrenceRow(
                                        occurrence: occurrence,
                                        location: store.location(for: occurrence),
                                        sourceLocationText: store.sourceLocationText(for: occurrence)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Class meeting. Opens course details; class time cannot be changed here.")
                            case .personal(let occurrence):
                                Button {
                                    editorContext = .edit(occurrence.block, on: store.selectedDate)
                                } label: {
                                    PersonalBlockRow(occurrence: occurrence, showsDisclosure: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this personal block for editing.")
                            }
                            if index < agenda.count - 1 { Divider().padding(.leading, 90) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var openTimeSection: some View {
        let windows = store.openPlanWindows(on: store.selectedDate)
        if !windows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Open time", detail: "7 AM–11 PM")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(windows.prefix(6)) { window in
                            Button {
                                editorContext = .openWindow(window, on: store.selectedDate)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Label(CampusFormatters.duration(window.duration), systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                    Text("\(CampusFormatters.time.string(from: window.start))–\(CampusFormatters.time.string(from: window.end))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(minWidth: 145, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Creates a personal block in this open window")
                        }
                    }
                }
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick starts", detail: "Review before saving")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PersonalPlanTemplate.defaults) { template in
                        Button {
                            editorContext = .template(template, on: store.selectedDate)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                PersonalBlockGlyph(category: template.category, size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(template.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .padding(14)
                            .frame(width: 160, height: 126, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your blocks", detail: store.personalBlocks.isEmpty ? nil : "\(store.personalBlocks.count) total")
            if store.personalBlocks.isEmpty {
                SurfaceCard {
                    EmptyStateView(
                        symbol: "rectangle.stack.badge.plus",
                        title: "No personal blocks",
                        message: "Choose a quick start or create your own schedule block. Nothing is added until you save it."
                    )
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(store.personalBlocks) { block in
                        routineCard(block)
                    }
                }
            }
        }
    }

    private func routineCard(_ block: PersonalBlock) -> some View {
        HStack(spacing: 13) {
            PersonalBlockGlyph(category: block.category, size: 42)
            Button {
                editorContext = .edit(block, on: store.selectedDate)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Text(blockScheduleDescription(block))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: Binding(
                get: { block.isEnabled },
                set: { store.setPersonalBlock(block, enabled: $0) }
            ))
            .labelsHidden()
            .accessibilityLabel("\(block.title) enabled")

            Menu("Block actions", systemImage: "ellipsis") {
                Button("Edit", systemImage: "pencil") { editorContext = .edit(block, on: store.selectedDate) }
                Button("Delete", systemImage: "trash", role: .destructive) { blockPendingDeletion = block }
            }
            .labelStyle(.iconOnly)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(block.isEnabled ? 1 : 0.6)
    }

    private func blockScheduleDescription(_ block: PersonalBlock) -> String {
        let time = "\(clockTime(hour: block.startHour, minute: block.startMinute))–\(clockTime(hour: block.endHour, minute: block.endMinute))"
        if block.recurrence == .once {
            let date = store.personalPlanEngine.date(block.startDate).map(CampusFormatters.compactDay.string) ?? block.startDate
            return "\(date) · \(time)"
        }
        let days: String
        if Set(block.weekdays) == Set(Weekday.allCases) {
            days = "Daily"
        } else if Set(block.weekdays) == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            days = "Weekdays"
        } else {
            days = block.weekdays.sorted { $0.sortIndex < $1.sortIndex }.map(\.shortName).joined(separator: ", ")
        }
        return "\(days) · \(time)\(block.crossesMidnight ? " next day" : "")"
    }

    private func clockTime(hour: Int, minute: Int) -> String {
        guard let date = store.engine.occurrenceDate(on: store.selectedDate, hour: hour, minute: minute) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return CampusFormatters.time.string(from: date)
    }
}

private struct PlanMetric: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct PersonalPlanTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let category: PersonalBlockCategory
    let recurrence: PersonalBlockRecurrence
    let weekdays: [Weekday]
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    static let defaults: [PersonalPlanTemplate] = [
        PersonalPlanTemplate(
            id: "lunch",
            title: "Lunch break",
            detail: "Weekdays · 12–1 PM",
            category: .meal,
            recurrence: .weekly,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            startHour: 12,
            startMinute: 0,
            endHour: 13,
            endMinute: 0
        ),
        PersonalPlanTemplate(
            id: "study",
            title: "Study session",
            detail: "Selected weekday · 90 min",
            category: .study,
            recurrence: .weekly,
            weekdays: [],
            startHour: 16,
            startMinute: 0,
            endHour: 17,
            endMinute: 30
        ),
        PersonalPlanTemplate(
            id: "sleep",
            title: "Sleep",
            detail: "Daily · 11 PM–7 AM",
            category: .sleep,
            recurrence: .weekly,
            weekdays: Weekday.allCases,
            startHour: 23,
            startMinute: 0,
            endHour: 7,
            endMinute: 0
        ),
        PersonalPlanTemplate(
            id: "workout",
            title: "Workout",
            detail: "Mon, Wed, Fri · 1 hour",
            category: .fitness,
            recurrence: .weekly,
            weekdays: [.monday, .wednesday, .friday],
            startHour: 18,
            startMinute: 0,
            endHour: 19,
            endMinute: 0
        )
    ]
}

struct PersonalBlockEditorContext: Identifiable {
    let id = UUID()
    let existingBlock: PersonalBlock?
    let template: PersonalPlanTemplate?
    let selectedDate: Date
    let suggestedWindow: PlanTimeWindow?

    static func new(on date: Date) -> PersonalBlockEditorContext {
        PersonalBlockEditorContext(existingBlock: nil, template: nil, selectedDate: date, suggestedWindow: nil)
    }

    static func edit(_ block: PersonalBlock, on date: Date) -> PersonalBlockEditorContext {
        PersonalBlockEditorContext(existingBlock: block, template: nil, selectedDate: date, suggestedWindow: nil)
    }

    static func template(_ template: PersonalPlanTemplate, on date: Date) -> PersonalBlockEditorContext {
        PersonalBlockEditorContext(existingBlock: nil, template: template, selectedDate: date, suggestedWindow: nil)
    }

    static func openWindow(_ window: PlanTimeWindow, on date: Date) -> PersonalBlockEditorContext {
        PersonalBlockEditorContext(existingBlock: nil, template: nil, selectedDate: date, suggestedWindow: window)
    }
}

private struct PersonalBlockEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let context: PersonalBlockEditorContext
    private let onSave: (PersonalBlock) -> Void
    private let blockID: UUID

    @State private var title: String
    @State private var category: PersonalBlockCategory
    @State private var recurrence: PersonalBlockRecurrence
    @State private var weekdays: Set<Weekday>
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String
    @State private var isEnabled: Bool

    init(context: PersonalBlockEditorContext, onSave: @escaping (PersonalBlock) -> Void) {
        self.context = context
        self.onSave = onSave

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let existing = context.existingBlock
        let template = context.template
        let selectedWeekday = Weekday(calendarWeekday: calendar.component(.weekday, from: context.selectedDate)) ?? .monday
        let defaultEndDate = calendar.date(byAdding: .day, value: 101, to: context.selectedDate) ?? context.selectedDate

        blockID = existing?.id ?? UUID()
        _title = State(initialValue: existing?.title ?? template?.title ?? "")
        _category = State(initialValue: existing?.category ?? template?.category ?? .study)
        _recurrence = State(initialValue: existing?.recurrence ?? template?.recurrence ?? (context.suggestedWindow == nil ? .weekly : .once))
        _weekdays = State(initialValue: Set(existing?.weekdays ?? (template?.weekdays.isEmpty == false ? template?.weekdays ?? [] : [selectedWeekday])))

        let parsedStartDate = existing.flatMap { Self.date($0.startDate, calendar: calendar) } ?? context.selectedDate
        let parsedEndDate = existing?.endDate.flatMap { Self.date($0, calendar: calendar) } ?? defaultEndDate
        _startDate = State(initialValue: parsedStartDate)
        _endDate = State(initialValue: max(parsedStartDate, parsedEndDate))

        let startHour = existing?.startHour ?? template?.startHour ?? context.suggestedWindow.map { calendar.component(.hour, from: $0.start) } ?? 12
        let startMinute = existing?.startMinute ?? template?.startMinute ?? context.suggestedWindow.map { calendar.component(.minute, from: $0.start) } ?? 0
        let endHour = existing?.endHour ?? template?.endHour ?? context.suggestedWindow.map { calendar.component(.hour, from: $0.end) } ?? 13
        let endMinute = existing?.endMinute ?? template?.endMinute ?? context.suggestedWindow.map { calendar.component(.minute, from: $0.end) } ?? 0
        _startTime = State(initialValue: calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: context.selectedDate) ?? context.selectedDate)
        _endTime = State(initialValue: calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: context.selectedDate) ?? context.selectedDate)
        _location = State(initialValue: existing?.location ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    TextField("Name", text: $title, prompt: Text("Study MATH 251"))
                    Picker("Category", selection: $category) {
                        ForEach(PersonalBlockCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    Toggle("Active", isOn: $isEnabled)
                }

                Section("Repeats") {
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(PersonalBlockRecurrence.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if recurrence == .once {
                        DatePicker("Date", selection: $startDate, displayedComponents: .date)
                    } else {
                        weekdayPicker
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                Section("Time") {
                    DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    if candidateBlock.crossesMidnight {
                        Label("Ends the following day", systemImage: "moon.stars.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Optional details") {
                    TextField("Location", text: $location, prompt: Text("Library, dining hall, dorm…"))
                    TextField("Notes", text: $notes, prompt: Text("What do you want to accomplish?"), axis: .vertical)
                        .lineLimit(2...5)
                }

                scheduleCheck

                Section {
                    Label("Class meetings are shown for conflict checking but cannot be edited from Personal Plan.", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(context.existingBlock == nil ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(candidateBlock)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: startDate) { _, value in
                if endDate < value { endDate = value }
                if recurrence == .weekly, weekdays.isEmpty,
                   let weekday = Weekday(calendarWeekday: store.engine.calendar.component(.weekday, from: value)) {
                    weekdays = [weekday]
                }
            }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days").font(.subheadline)
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let selected = weekdays.contains(day)
                    Button {
                        if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                    } label: {
                        Text(day.narrowName)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(selected ? AppTheme.accent : Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.shortName)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var scheduleCheck: some View {
        if isValid {
            let conflicts = store.conflicts(for: candidateBlock)
            Section("Schedule check") {
                if conflicts.isEmpty {
                    Label("No conflicts with classes or your other active blocks", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") found. You can still save and adjust later.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    ForEach(Array(conflicts.prefix(3))) { conflict in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(conflict.firstTitle) overlaps \(conflict.secondTitle)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(CampusFormatters.compactDay.string(from: conflict.start)) · \(CampusFormatters.time.string(from: conflict.start))–\(CampusFormatters.time.string(from: conflict.end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var candidateBlock: PersonalBlock {
        let calendar = store.engine.calendar
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        return PersonalBlock(
            id: blockID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            recurrence: recurrence,
            weekdays: recurrence == .once ? [] : weekdays.sorted { $0.sortIndex < $1.sortIndex },
            startDate: store.engine.dateString(for: startDate),
            endDate: recurrence == .weekly ? store.engine.dateString(for: endDate) : nil,
            startHour: startComponents.hour ?? 0,
            startMinute: startComponents.minute ?? 0,
            endHour: endComponents.hour ?? 0,
            endMinute: endComponents.minute ?? 0,
            location: location.trimmedOrNil,
            notes: notes.trimmedOrNil,
            isEnabled: isEnabled
        )
    }

    private var isValid: Bool {
        let start = candidateBlock.startHour * 60 + candidateBlock.startMinute
        let end = candidateBlock.endHour * 60 + candidateBlock.endMinute
        return !candidateBlock.title.isEmpty &&
            (recurrence == .once || !weekdays.isEmpty) &&
            end != start &&
            (recurrence == .once || endDate >= startDate)
    }

    private static func date(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
