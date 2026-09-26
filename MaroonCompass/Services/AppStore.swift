import CoreLocation
import Foundation
import Observation

enum AppTab: Hashable {
    case today
    case schedule
    case plan
    case map
    case saved
    case settings
}

@MainActor
@Observable
final class AppStore {
    var engine = ScheduleEngine(
        term: ScheduleSeed.term,
        courses: ScheduleSeed.courses,
        patterns: ScheduleSeed.patterns,
        oneTimeEvents: ScheduleSeed.oneTimeEvents,
        exceptions: ScheduleSeed.exceptions
    )
    let locationService = LocationService()

    var selectedTab: AppTab = .today
    var selectedDate = Date()
    var campusFeatures: [CampusFeature] = []
    var placeResults: [PlaceResult] = []
    var mapFeatures: [CampusFeature] = []
    var courseLocations: [String: CourseLocation] = [:]
    var verifiedMeetingLocations: [String: CourseLocation] = [:]
    var favoriteFeatures: [CampusFeature] = []
    var favoritePlaces: [PlaceResult] = []
    var recentPlaceSearches: [String] = []
    var personalBlocks: [PersonalBlock] = []
    var requestedMapSearch: String?
    var isLoadingCampus = false
    var isSearchingPlaces = false
    var campusError: String?
    var mapFeatureError: String?
    var placeError: String?
    var activeRoute: RouteEstimate?
    var dayRoutes: [RouteEstimate] = []
    var isLoadingRoute = false
    var routeError: String?
    var hasCompletedOnboarding: Bool
    var remindersEnabled: Bool
    var reminderLeadMinutes: Int
    var travelMode: TravelMode
    var safetyBufferMinutes: Int

    private let campusService = CampusGISService()
    private let placesService = PlacesSearchService()
    private let routeService = RouteService()
    private let notificationService = NotificationService()
    private let calendarExportService = CalendarExportService()
    private let importService = ICSImportService()
    private let defaults = UserDefaults.standard
    private static let embeddedScheduleRevisionKey = "embeddedScheduleRevision"

    init() {
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        remindersEnabled = defaults.bool(forKey: "remindersEnabled")
        reminderLeadMinutes = defaults.object(forKey: "reminderLeadMinutes") == nil ? 15 : defaults.integer(forKey: "reminderLeadMinutes")
        travelMode = TravelMode(rawValue: defaults.string(forKey: "travelMode") ?? "walking") ?? .walking
        safetyBufferMinutes = defaults.object(forKey: "safetyBufferMinutes") == nil ? 10 : defaults.integer(forKey: "safetyBufferMinutes")
        courseLocations = Self.decode([String: CourseLocation].self, from: defaults.data(forKey: "courseLocations")) ?? [:]
        favoriteFeatures = Self.decode([CampusFeature].self, from: defaults.data(forKey: "favoriteFeatures")) ?? []
        favoritePlaces = Self.decode([PlaceResult].self, from: defaults.data(forKey: "favoritePlaces")) ?? []
        recentPlaceSearches = defaults.stringArray(forKey: "recentPlaceSearches") ?? []
        personalBlocks = Self.decode([PersonalBlock].self, from: defaults.data(forKey: "personalBlocks")) ?? []

        courseLocations = Self.reconcileEmbeddedScheduleRevision(defaults: defaults, courseLocations: courseLocations)

        if let bundle = Self.decode(ImportedScheduleBundle.self, from: defaults.data(forKey: "importedSchedule")) {
            let term = bundle.term ?? ScheduleSeed.term
            engine = ScheduleEngine(
                term: term,
                courses: bundle.courses,
                patterns: bundle.patterns,
                oneTimeEvents: bundle.oneTimeEvents,
                exceptions: Self.exceptions(for: term)
            )
        }

        let arguments = ProcessInfo.processInfo.arguments
        if let value = Self.argument(named: "-UITab", in: arguments) {
            selectedTab = switch value.localizedLowercase {
            case "schedule": .schedule
            case "plan": .plan
            case "map": .map
            case "saved": .saved
            case "settings": .settings
            default: .today
            }
        }
        if let value = Self.argument(named: "-UISelectedDate", in: arguments), let date = engine.date(value) {
            selectedDate = date
        }
        if arguments.contains("-UISeedPersonalPlan"), personalBlocks.isEmpty {
            personalBlocks = Self.previewPersonalBlocks
        }
    }

    var totalCredits: Int { engine.courses.reduce(0) { $0 + $1.credits } }
    var hasImportedSchedule: Bool { defaults.data(forKey: "importedSchedule") != nil }
    var scheduleSourceName: String {
        Self.decode(ImportedScheduleBundle.self, from: defaults.data(forKey: "importedSchedule"))?.sourceName ?? ScheduleSeed.sourceName
    }

    var personalPlanEngine: PersonalPlanEngine { PersonalPlanEngine(calendar: engine.calendar) }

    var classMapPins: [ClassMapPin] {
        var result: [ClassMapPin] = []
        for course in engine.courses {
            if let manual = courseLocations[course.id] {
                result.append(ClassMapPin(id: "manual-\(course.id)", course: course, location: manual))
                continue
            }
            var seen: Set<String> = []
            for location in verifiedMeetingLocations.values where location.courseID == course.id {
                let key = "\(course.id)-\(location.feature.id)-\(location.room ?? "")"
                guard seen.insert(key).inserted else { continue }
                result.append(ClassMapPin(id: key, course: course, location: location))
            }
        }
        return result
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: "hasCompletedOnboarding")
    }

    func applyPendingIntentNavigation() {
        guard let destination = defaults.string(forKey: "pendingIntentTab") else { return }
        selectedTab = switch destination {
        case "schedule": .schedule
        case "plan": .plan
        case "map": .map
        case "saved": .saved
        default: .today
        }
        defaults.removeObject(forKey: "pendingIntentTab")
    }

    func loadCampus(forceRefresh: Bool = false) async {
        guard (forceRefresh || campusFeatures.isEmpty), !isLoadingCampus else { return }
        isLoadingCampus = true
        let cached = await campusService.cachedFeatures()
        if !cached.isEmpty {
            campusFeatures = cached
            resolveVerifiedMeetingLocations()
        }
        let cachedMapFeatures = await campusService.cachedMapFeatures()
        if !cachedMapFeatures.isEmpty { mapFeatures = cachedMapFeatures }

        async let buildingRequest = campusService.fetchBuildings()
        async let parkingRequest = campusService.fetchParkingFeatures()
        do {
            campusFeatures = try await buildingRequest
            resolveVerifiedMeetingLocations()
            campusError = nil
        } catch {
            campusError = campusFeatures.isEmpty ? error.localizedDescription : "Showing saved campus data. Live refresh failed."
        }
        do {
            mapFeatures = try await parkingRequest
            mapFeatureError = nil
        } catch {
            mapFeatureError = mapFeatures.isEmpty ? "Official parking layers are temporarily unavailable." : "Showing saved parking data. Live refresh failed."
        }
        isLoadingCampus = false
    }

    func searchPlaces(query: String, center: CLLocationCoordinate2D? = nil) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQuery.isEmpty {
            recentPlaceSearches.removeAll { $0.localizedCaseInsensitiveCompare(cleanQuery) == .orderedSame }
            recentPlaceSearches.insert(cleanQuery, at: 0)
            recentPlaceSearches = Array(recentPlaceSearches.prefix(8))
            defaults.set(recentPlaceSearches, forKey: "recentPlaceSearches")
        }
        isSearchingPlaces = true
        placeError = nil
        let anchor = center ?? locationService.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 30.6180, longitude: -96.3386)
        do {
            placeResults = try await placesService.search(query: query, center: anchor)
        } catch {
            placeResults = []
            placeError = "Nearby places are unavailable right now. Your schedule and campus buildings still work."
        }
        isSearchingPlaces = false
    }

    func clearRecentSearches() {
        recentPlaceSearches = []
        defaults.removeObject(forKey: "recentPlaceSearches")
    }

    @discardableResult
    func calculateRoute(to coordinate: CoordinateValue, destinationName: String) async -> RouteEstimate? {
        guard let location = locationService.currentLocation else {
            locationService.requestLocation()
            routeError = RouteError.locationUnavailable.localizedDescription
            return nil
        }

        isLoadingRoute = true
        routeError = nil
        defer { isLoadingRoute = false }
        do {
            let estimate = try await routeService.calculate(
                from: CoordinateValue(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                to: coordinate,
                destinationName: destinationName,
                mode: travelMode
            )
            activeRoute = estimate
            dayRoutes = []
            if remindersEnabled,
               let occurrence = engine.nextOccurrence(after: Date()),
               self.location(for: occurrence)?.feature.coordinateValue == coordinate {
                await notificationService.scheduleLeaveReminder(
                    occurrence: occurrence,
                    route: estimate,
                    safetyBufferMinutes: safetyBufferMinutes,
                    calendar: engine.calendar
                )
            }
            return estimate
        } catch {
            activeRoute = nil
            routeError = error.localizedDescription
            return nil
        }
    }

    func calculateDayRoute(on date: Date) async {
        let locatedMeetings = engine.occurrences(on: date).compactMap { occurrence -> (ScheduleOccurrence, CourseLocation)? in
            guard let location = location(for: occurrence) else { return nil }
            return (occurrence, location)
        }

        var uniqueStops: [(ScheduleOccurrence, CourseLocation)] = []
        for stop in locatedMeetings where uniqueStops.last?.1.feature.id != stop.1.feature.id {
            uniqueStops.append(stop)
        }
        guard uniqueStops.count >= 2 else {
            routeError = "Assign at least two class buildings on this day to build a campus route."
            dayRoutes = []
            return
        }

        isLoadingRoute = true
        routeError = nil
        activeRoute = nil
        defer { isLoadingRoute = false }
        var routes: [RouteEstimate] = []
        do {
            for index in 0..<(uniqueStops.count - 1) {
                let start = uniqueStops[index].1.feature
                let destination = uniqueStops[index + 1].1.feature
                routes.append(try await routeService.calculate(
                    from: start.coordinateValue,
                    to: destination.coordinateValue,
                    destinationName: destination.name,
                    mode: .walking
                ))
            }
            dayRoutes = routes
        } catch {
            dayRoutes = []
            routeError = error.localizedDescription
        }
    }

    func clearRoutes() {
        activeRoute = nil
        dayRoutes = []
        routeError = nil
    }

    func leaveBy(for occurrence: ScheduleOccurrence, route: RouteEstimate) -> Date {
        occurrence.start.addingTimeInterval(-(route.travelTime + Double(safetyBufferMinutes * 60)))
    }

    func location(for occurrence: ScheduleOccurrence) -> CourseLocation? {
        courseLocations[occurrence.course.id] ?? verifiedMeetingLocations[occurrence.sourceMeetingID]
    }

    func sourceLocationText(for occurrence: ScheduleOccurrence) -> String? {
        if occurrence.isSpecial {
            return engine.oneTimeEvents.first(where: { $0.id == occurrence.sourceMeetingID })?.sourceLocationText
        }
        return engine.patterns.first(where: { $0.id == occurrence.sourceMeetingID })?.sourceLocationText
    }

    func hasLocation(for course: Course) -> Bool {
        courseLocations[course.id] != nil ||
            engine.patterns.contains(where: { $0.courseID == course.id && $0.sourceLocationText != nil }) ||
            engine.oneTimeEvents.contains(where: { $0.courseID == course.id && $0.sourceLocationText != nil })
    }

    func assign(_ feature: CampusFeature, to course: Course, room: String? = nil) {
        courseLocations[course.id] = CourseLocation(courseID: course.id, feature: feature, room: room?.nilIfBlank)
        persistLocations()
        clearRoutes()
        notificationService.clearLeaveReminders()
    }

    func clearLocation(for course: Course) {
        courseLocations.removeValue(forKey: course.id)
        persistLocations()
        clearRoutes()
        notificationService.clearLeaveReminders()
    }

    func toggleFavorite(_ feature: CampusFeature) {
        if let index = favoriteFeatures.firstIndex(where: { $0.id == feature.id }) {
            favoriteFeatures.remove(at: index)
        } else {
            favoriteFeatures.append(feature)
        }
        persistFavorites()
    }

    func isFavorite(_ feature: CampusFeature) -> Bool {
        favoriteFeatures.contains(where: { $0.id == feature.id })
    }

    func toggleFavorite(_ place: PlaceResult) {
        if let index = favoritePlaces.firstIndex(where: { $0.id == place.id }) {
            favoritePlaces.remove(at: index)
        } else {
            favoritePlaces.append(place)
        }
        defaults.set(try? JSONEncoder().encode(favoritePlaces), forKey: "favoritePlaces")
    }

    func isFavorite(_ place: PlaceResult) -> Bool {
        favoritePlaces.contains(where: { $0.id == place.id })
    }

    func setRemindersEnabled(_ value: Bool) async {
        if value {
            let authorized = await notificationService.requestAuthorization()
            remindersEnabled = authorized
            if authorized { await notificationService.reconcile(engine: engine, leadMinutes: reminderLeadMinutes) }
        } else {
            remindersEnabled = false
            notificationService.disable()
        }
        defaults.set(remindersEnabled, forKey: "remindersEnabled")
    }

    func updateReminderLeadMinutes(_ value: Int) async {
        reminderLeadMinutes = value
        defaults.set(value, forKey: "reminderLeadMinutes")
        if remindersEnabled { await notificationService.reconcile(engine: engine, leadMinutes: value) }
    }

    func updateTravelMode(_ value: TravelMode) {
        travelMode = value
        defaults.set(value.rawValue, forKey: "travelMode")
        clearRoutes()
        notificationService.clearLeaveReminders()
    }

    func updateSafetyBuffer(_ value: Int) {
        safetyBufferMinutes = value
        defaults.set(value, forKey: "safetyBufferMinutes")
        notificationService.clearLeaveReminders()
    }

    func importCalendar(data: Data, sourceName: String) throws -> CalendarImportReport {
        let (bundle, report) = try importService.parse(data: data, sourceName: sourceName)
        try saveImportedSchedule(bundle)
        return report
    }

    func saveImportedSchedule(_ bundle: ImportedScheduleBundle) throws {
        let encoded = try JSONEncoder().encode(bundle)
        let term = bundle.term ?? ScheduleSeed.term
        defaults.set(encoded, forKey: "importedSchedule")
        engine = ScheduleEngine(
            term: term,
            courses: bundle.courses,
            patterns: bundle.patterns,
            oneTimeEvents: bundle.oneTimeEvents,
            exceptions: Self.exceptions(for: term)
        )
        resolveVerifiedMeetingLocations()
    }

    func restoreEmbeddedSchedule() {
        engine = ScheduleEngine(
            term: ScheduleSeed.term,
            courses: ScheduleSeed.courses,
            patterns: ScheduleSeed.patterns,
            oneTimeEvents: ScheduleSeed.oneTimeEvents,
            exceptions: ScheduleSeed.exceptions
        )
        resolveVerifiedMeetingLocations()
        defaults.removeObject(forKey: "importedSchedule")
        defaults.set(ScheduleSeed.revision, forKey: Self.embeddedScheduleRevisionKey)
    }

    func personalOccurrences(on date: Date) -> [PersonalBlockOccurrence] {
        personalPlanEngine.occurrences(on: date, blocks: personalBlocks)
    }

    func dailyAgenda(on date: Date) -> [DailyAgendaItem] {
        personalPlanEngine.agenda(
            on: date,
            classOccurrences: engine.occurrences(on: date),
            blocks: personalBlocks
        )
    }

    func personalPlanConflicts(on date: Date) -> [PersonalPlanConflict] {
        personalPlanEngine.conflicts(
            on: date,
            classOccurrences: engine.occurrences(on: date),
            blocks: personalBlocks
        )
    }

    func openPlanWindows(on date: Date) -> [PlanTimeWindow] {
        personalPlanEngine.openWindows(
            on: date,
            classOccurrences: engine.occurrences(on: date),
            blocks: personalBlocks
        )
    }

    func conflicts(for candidate: PersonalBlock) -> [PersonalPlanConflict] {
        guard candidate.isEnabled, let start = personalPlanEngine.date(candidate.startDate) else { return [] }
        let fallbackEnd = engine.date(engine.term.lastClassDate) ?? start
        let end = candidate.recurrence == .once
            ? start
            : candidate.endDate.flatMap(personalPlanEngine.date) ?? fallbackEnd
        let blocks = personalBlocks.filter { $0.id != candidate.id } + [candidate]
        var day = start
        var result: [PersonalPlanConflict] = []
        var seen: Set<String> = []
        var inspectedDays = 0

        while day <= end, inspectedDays < 370 {
            for conflict in personalPlanEngine.conflicts(
                on: day,
                classOccurrences: engine.occurrences(on: day),
                blocks: blocks
            ) where conflict.personalBlockIDs.contains(candidate.id) {
                if seen.insert(conflict.id).inserted { result.append(conflict) }
            }
            guard let nextDay = engine.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
            inspectedDays += 1
        }
        return result
    }

    func savePersonalBlock(_ block: PersonalBlock) {
        if let index = personalBlocks.firstIndex(where: { $0.id == block.id }) {
            personalBlocks[index] = block
        } else {
            personalBlocks.append(block)
        }
        personalBlocks.sort(by: Self.personalBlockSort)
        persistPersonalBlocks()
    }

    func setPersonalBlock(_ block: PersonalBlock, enabled: Bool) {
        var updated = block
        updated.isEnabled = enabled
        savePersonalBlock(updated)
    }

    func deletePersonalBlock(_ block: PersonalBlock) {
        personalBlocks.removeAll { $0.id == block.id }
        persistPersonalBlocks()
    }

    func exportCourseToCalendar(_ course: Course) async throws -> CalendarExportReport {
        try await calendarExportService.export(
            course: course,
            engine: engine,
            locationForOccurrence: { occurrence in self.location(for: occurrence) }
        )
    }

    private func persistLocations() {
        defaults.set(try? JSONEncoder().encode(courseLocations), forKey: "courseLocations")
    }

    private func persistFavorites() {
        defaults.set(try? JSONEncoder().encode(favoriteFeatures), forKey: "favoriteFeatures")
    }

    private func persistPersonalBlocks() {
        defaults.set(try? JSONEncoder().encode(personalBlocks), forKey: "personalBlocks")
    }

    private func resolveVerifiedMeetingLocations() {
        var result: [String: CourseLocation] = [:]
        for pattern in engine.patterns {
            if let location = resolvedLocation(courseID: pattern.courseID, sourceText: pattern.sourceLocationText) {
                result[pattern.id] = location
            }
        }
        for event in engine.oneTimeEvents {
            if let location = resolvedLocation(courseID: event.courseID, sourceText: event.sourceLocationText) {
                result[event.id] = location
            }
        }
        verifiedMeetingLocations = result
    }

    private func resolvedLocation(courseID: String, sourceText: String?) -> CourseLocation? {
        guard let sourceText else { return nil }
        let parts = sourceText
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let abbreviation = parts.first else { return nil }
        guard let feature = campusFeatures.first(where: {
            $0.abbreviation?.localizedCaseInsensitiveCompare(abbreviation) == .orderedSame
        }) else { return nil }
        return CourseLocation(courseID: courseID, feature: feature, room: parts.dropFirst().first)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func exceptions(for term: Term) -> [AcademicException] {
        guard term.firstClassDate == ScheduleSeed.term.firstClassDate,
              term.lastClassDate == ScheduleSeed.term.lastClassDate else { return [] }
        return ScheduleSeed.exceptions
    }

    static func reconcileEmbeddedScheduleRevision(
        defaults: UserDefaults,
        courseLocations: [String: CourseLocation]
    ) -> [String: CourseLocation] {
        guard defaults.string(forKey: embeddedScheduleRevisionKey) != ScheduleSeed.revision else {
            return courseLocations
        }

        // A new embedded seed must never replace a schedule explicitly imported by the user.
        // Retain its stored bytes and location assignments for recovery even if decoding fails.
        guard defaults.data(forKey: "importedSchedule") == nil else {
            defaults.set(ScheduleSeed.revision, forKey: embeddedScheduleRevisionKey)
            return courseLocations
        }

        let embeddedCourseIDs = Set(ScheduleSeed.courses.map(\.id))
        let retained = courseLocations.filter { embeddedCourseIDs.contains($0.key) }
        defaults.set(try? JSONEncoder().encode(retained), forKey: "courseLocations")
        defaults.set(ScheduleSeed.revision, forKey: embeddedScheduleRevisionKey)
        return retained
    }

    private static func argument(named name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func personalBlockSort(_ lhs: PersonalBlock, _ rhs: PersonalBlock) -> Bool {
        if lhs.startHour != rhs.startHour { return lhs.startHour < rhs.startHour }
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static let previewPersonalBlocks: [PersonalBlock] = [
        PersonalBlock(
            title: "Lunch break",
            category: .meal,
            recurrence: .weekly,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            startDate: "2026-08-24",
            endDate: "2026-12-03",
            startHour: 12,
            startMinute: 30,
            endHour: 13,
            endMinute: 15,
            location: "MSC"
        ),
        PersonalBlock(
            title: "Study MATH 251",
            category: .study,
            recurrence: .weekly,
            weekdays: [.monday, .wednesday],
            startDate: "2026-08-24",
            endDate: "2026-12-03",
            startHour: 16,
            startMinute: 0,
            endHour: 17,
            endMinute: 30,
            notes: "Practice problems and review notes"
        ),
        PersonalBlock(
            title: "Sleep",
            category: .sleep,
            recurrence: .weekly,
            weekdays: Weekday.allCases,
            startDate: "2026-08-24",
            endDate: "2026-12-03",
            startHour: 23,
            startMinute: 0,
            endHour: 7,
            endMinute: 0
        )
    ]
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
