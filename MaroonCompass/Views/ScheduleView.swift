import SwiftUI

struct ScheduleView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedCourse: Course?
    @State private var isDatePickerPresented = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            LazyVStack(spacing: 18) {
                weekStrip

                if let exception = store.engine.academicException(on: store.selectedDate) {
                    AcademicBanner(item: exception)
                }

                dayAgenda
                coursesSection
                specialMeetingsSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Choose date", systemImage: "calendar.badge.clock") {
                    isDatePickerPresented = true
                }
            }
        }
        .sheet(item: $selectedCourse) { course in
            NavigationStack { CourseDetailView(course: course) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isDatePickerPresented) {
            NavigationStack {
                DatePicker("Schedule date", selection: $store.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choose a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isDatePickerPresented = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var weekStrip: some View {
        let days = Array(store.engine.week(containing: store.selectedDate).prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CampusFormatters.dayHeading.string(from: store.selectedDate))
                        .font(.title3.bold())
                    Text("Campus time · Central")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.selectedDate = Date()
                } label: {
                    Text("Today").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    let isSelected = store.engine.calendar.isDate(day, inSameDayAs: store.selectedDate)
                    let count = store.engine.occurrences(on: day).count
                    Button {
                        store.selectedDate = day
                    } label: {
                        VStack(spacing: 6) {
                            Text(store.engine.calendar.shortWeekdaySymbols[store.engine.calendar.component(.weekday, from: day) - 1])
                                .font(.caption2.weight(.semibold))
                            Text("\(store.engine.calendar.component(.day, from: day))")
                                .font(.headline.monospacedDigit())
                            Circle()
                                .fill(count > 0 ? (isSelected ? Color.white : AppTheme.accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(CampusFormatters.dayHeading.string(from: day)), \(count) meetings")
                }
            }
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var dayAgenda: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            dayAgendaContent(now: context.date)
        }
    }

    private func dayAgendaContent(now: Date) -> some View {
        let occurrences = store.engine.occurrences(on: store.selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Day agenda", detail: occurrences.isEmpty ? "No meetings" : "\(occurrences.count) meetings")
            SurfaceCard {
                if occurrences.isEmpty {
                    EmptyStateView(
                        symbol: "calendar.badge.checkmark",
                        title: "No scheduled classes",
                        message: store.engine.academicException(on: store.selectedDate)?.detail ?? "Your loaded schedule has no meetings on this date."
                    )
                } else {
                    VStack(spacing: 16) {
                        ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                            VStack(spacing: 8) {
                                Button { selectedCourse = occurrence.course } label: {
                                    OccurrenceRow(
                                        occurrence: occurrence,
                                        location: store.location(for: occurrence),
                                        sourceLocationText: store.sourceLocationText(for: occurrence)
                                    )
                                }
                                .buttonStyle(.plain)
                                if store.engine.calendar.isDate(store.selectedDate, inSameDayAs: now),
                                   occurrence.start <= now,
                                   occurrence.end > now {
                                    Label("In progress now", systemImage: "circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 90)
                                }
                            }
                            if index < occurrences.count - 1 {
                                transitionRow(from: occurrence, to: occurrences[index + 1])
                            }
                        }
                    }
                }
            }
        }
    }

    private func transitionRow(from current: ScheduleOccurrence, to next: ScheduleOccurrence) -> some View {
        let interval = next.start.timeIntervalSince(current.end)
        let currentLocation = store.location(for: current)
        let nextLocation = store.location(for: next)
        let sameBuilding = currentLocation?.feature.id == nextLocation?.feature.id && currentLocation != nil
        return HStack(spacing: 8) {
            Rectangle().fill(Color(.separator)).frame(height: 1)
            if interval < 0 {
                Label("\(CampusFormatters.duration(-interval)) conflict", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label(
                    sameBuilding ? "\(CampusFormatters.duration(interval)) · same building" : "\(CampusFormatters.duration(interval)) between",
                    systemImage: sameBuilding ? "building.2.fill" : "arrow.down"
                )
                .foregroundStyle(.secondary)
            }
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
        .font(.caption.weight(.medium))
        .padding(.leading, 90)
        .accessibilityElement(children: .combine)
    }

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Courses", detail: "\(store.totalCredits) credits")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(store.engine.courses) { course in
                    Button { selectedCourse = course } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                CourseGlyph(course: course, size: 38)
                                Spacer()
                                Text("\(course.credits) cr")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.displayCode).font(.headline).foregroundStyle(.primary)
                                Text(course.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Label(store.hasLocation(for: course) ? "Location verified" : "Location needed", systemImage: store.hasLocation(for: course) ? "checkmark.seal.fill" : "mappin.slash")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(store.hasLocation(for: course) ? .green : .orange)
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var specialMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Special meetings", detail: "Source label preserved")
            SurfaceCard {
                VStack(spacing: 14) {
                    ForEach(Array(store.engine.oneTimeEvents.enumerated()), id: \.element.id) { index, event in
                        if let date = store.engine.date(event.date, hour: event.startHour, minute: event.startMinute),
                           let course = store.engine.courses.first(where: { $0.id == event.courseID }) {
                            Button {
                                store.selectedDate = date
                            } label: {
                                HStack(spacing: 13) {
                                    CourseGlyph(course: course, size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text("\(CampusFormatters.compactDay.string(from: date)) · \(CampusFormatters.time.string(from: date))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            if index < store.engine.oneTimeEvents.count - 1 { Divider().padding(.leading, 49) }
                        }
                    }
                }
            }
        }
    }
}
