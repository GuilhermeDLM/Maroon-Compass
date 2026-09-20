import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedCourse: Course?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                LazyVStack(spacing: 18) {
                    greetingHeader(at: timeline.date)

                    if let exception = store.engine.academicException(on: timeline.date) {
                        AcademicBanner(item: exception)
                    }

                    nextClassCard(at: timeline.date)
                    todayTimeline(at: timeline.date)
                    smartGapCard(at: timeline.date)
                    quickActions
                    supportCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedCourse) { course in
            NavigationStack { CourseDetailView(course: course) }
                .presentationDetents([.medium, .large])
        }
    }

    private func greetingHeader(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CampusFormatters.dayHeading.string(from: date))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(dayMessage(at: date))
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func nextClassCard(at now: Date) -> some View {
        if let next = store.engine.nextOccurrence(after: now) {
            let location = store.location(for: next)
            let sourceLocationText = store.sourceLocationText(for: next)
            SurfaceCard {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Label(next.isSpecial ? "Next special meeting" : "Up next", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                        Spacer()
                        Text(countdown(to: next.start, from: now))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        CourseGlyph(course: next.course, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(next.course.code)
                                .font(.title2.bold())
                            Text(next.isSpecial ? next.title : next.course.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("\(CampusFormatters.compactDay.string(from: next.start)) · \(CampusFormatters.time.string(from: next.start))")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    Divider()

                    Button {
                        selectedCourse = next.course
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: location == nil && sourceLocationText == nil ? "mappin.slash" : "mappin.and.ellipse")
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location?.feature.name ?? sourceLocationText ?? "Location not added")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(location == nil ? "Verified schedule location; campus directions load with map data" : [location?.feature.abbreviation, location?.room].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if let location {
                        Divider()
                        routeGuidance(for: next, location: location)
                    }
                }
            }
            .task(id: routeTaskID(for: location)) {
                guard let location, store.locationService.currentLocation != nil else { return }
                guard store.activeRoute?.destination != location.feature.coordinateValue || store.activeRoute?.travelMode != store.travelMode else { return }
                await store.calculateRoute(to: location.feature.coordinateValue, destinationName: location.feature.name)
            }
        } else {
            SurfaceCard {
                EmptyStateView(
                    symbol: "checkmark.circle.fill",
                    title: "Schedule complete",
                    message: "There are no more class meetings in the loaded Fall 2026 schedule."
                )
            }
        }
    }

    @ViewBuilder
    private func routeGuidance(for occurrence: ScheduleOccurrence, location: CourseLocation) -> some View {
        if let route = store.activeRoute,
           route.destination == location.feature.coordinateValue,
           route.travelMode == store.travelMode {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: store.travelMode.symbol)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(route.wholeMinutes) min \(store.travelMode.title.lowercased()) · \(distance(route.distanceMeters))")
                        .font(.subheadline.weight(.semibold))
                    Text("Leave by \(CampusFormatters.time.string(from: store.leaveBy(for: occurrence, route: route))) to keep a \(store.safetyBufferMinutes)-minute buffer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                    NavigationActions.openDirections(name: location.feature.name, coordinate: location.feature.coordinate, mode: store.travelMode)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .accessibilityLabel("Open directions to \(location.feature.name)")
            }
        } else if store.isLoadingRoute {
            LoadingRow(message: "Calculating route…")
        } else {
            Button {
                store.locationService.requestLocation()
                Task { await store.calculateRoute(to: location.feature.coordinateValue, destinationName: location.feature.name) }
            } label: {
                Label(store.locationService.currentLocation == nil ? "Use my location for leave-by guidance" : "Calculate route and leave time", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private func routeTaskID(for location: CourseLocation?) -> String? {
        guard let location, let current = store.locationService.currentLocation else { return nil }
        return String(format: "%@-%.4f-%.4f-%@", location.feature.id, current.coordinate.latitude, current.coordinate.longitude, store.travelMode.rawValue)
    }

    private func distance(_ meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1_000)
    }

    @ViewBuilder
    private func todayTimeline(at date: Date) -> some View {
        let agenda = store.dailyAgenda(on: date)
        let classCount = store.engine.occurrences(on: date).count
        let personalCount = store.personalOccurrences(on: date).count
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Today’s timeline",
                detail: agenda.isEmpty ? nil : "\(classCount) class\(classCount == 1 ? "" : "es") · \(personalCount) personal"
            )
            SurfaceCard {
                if agenda.isEmpty {
                    EmptyStateView(
                        symbol: "calendar.badge.checkmark",
                        title: "Nothing scheduled today",
                        message: noClassMessage(on: date),
                        actionTitle: "Plan this day",
                        action: { store.selectedDate = date; store.selectedTab = .plan }
                    )
                } else {
                    VStack(spacing: 16) {
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
                            case .personal(let occurrence):
                                Button {
                                    store.selectedDate = date
                                    store.selectedTab = .plan
                                } label: {
                                    PersonalBlockRow(occurrence: occurrence, showsDisclosure: true)
                                }
                                .buttonStyle(.plain)
                            }
                            if index < agenda.count - 1 { Divider().padding(.leading, 90) }
                        }
                    }
                }
            }
        }
    }

    private func smartGapCard(at date: Date) -> some View {
        let meaningfulGaps = store.openPlanWindows(on: date).filter { $0.end > date }
        let missingLocations = store.engine.courses.filter { !store.hasLocation(for: $0) }.count
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Plan the gap")
            SurfaceCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: meaningfulGaps.isEmpty ? "clock.badge.checkmark.fill" : "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        if let gap = meaningfulGaps.first {
                            Text("\(CampusFormatters.duration(gap.duration)) available")
                                .font(.headline)
                            Text("From \(CampusFormatters.time.string(from: gap.start)) to \(CampusFormatters.time.string(from: gap.end)), after classes and personal blocks. Add study time, a meal, or another routine from Personal Plan.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Your day is clear")
                                .font(.headline)
                            Text("Explore campus dining, study spaces, and essentials from the map.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if missingLocations > 0 {
                            Text("\(missingLocations) course locations still need confirmation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.top, 3)
                        }
                        Button("Open Personal Plan", systemImage: "calendar.badge.plus") {
                            store.selectedDate = date
                            store.selectedTab = .plan
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick actions")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickAction(title: "Full schedule", symbol: "calendar", color: AppTheme.accent) { store.selectedTab = .schedule }
                quickAction(title: "Personal plan", symbol: "calendar.badge.plus", color: .indigo) { store.selectedTab = .plan }
                quickAction(title: "Campus map", symbol: "map.fill", color: .blue) { store.selectedTab = .map }
            }
        }
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Campus support")
            SurfaceCard {
                VStack(spacing: 14) {
                    ForEach(ScheduleSeed.resources.filter { ["escort", "uhs", "transport"].contains($0.id) }) { resource in
                        if let destination = resourceDestination(resource) {
                            Link(destination: destination) {
                                HStack(spacing: 12) {
                                    Image(systemName: resource.symbol)
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resource.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(resource.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        if resource.id != "transport" { Divider().padding(.leading, 40) }
                    }
                }
            }
        }
    }

    private func quickAction(title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.compactRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dayMessage(at date: Date) -> String {
        guard let first = store.engine.date(store.engine.term.firstClassDate) else { return "Your day at a glance" }
        if date < first { return "Fall classes are almost here" }
        return store.engine.occurrences(on: date).isEmpty ? "A lighter day in Aggieland" : "Here’s what’s ahead"
    }

    private func countdown(to target: Date, from now: Date) -> String {
        let interval = target.timeIntervalSince(now)
        guard interval > 0 else { return "In progress" }
        let minutes = Int(interval / 60)
        if minutes >= 24 * 60 { return "In \(minutes / (24 * 60)) days" }
        if minutes >= 60 { return "In \(minutes / 60) hr \(minutes % 60) min" }
        return "In \(max(minutes, 1)) min"
    }

    private func noClassMessage(on date: Date) -> String {
        if let exception = store.engine.academicException(on: date) { return exception.detail }
        if let first = store.engine.date(store.engine.term.firstClassDate), date < first {
            return "Fall classes begin Monday, August 24."
        }
        return "There are no class meetings in the loaded schedule for this date."
    }

    private func resourceDestination(_ resource: ResourceContact) -> URL? {
        if let url = resource.url { return url }
        guard let phone = resource.phone else { return nil }
        return URL(string: "tel:\(phone.filter(\.isNumber))")
    }
}
