import AppIntents
import Foundation

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What’s Next?"
    static let description = IntentDescription("Gets the next Fall 2026 class from Maroon Compass.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = IntentScheduleProvider.engine()
        guard let next = engine.nextOccurrence(after: Date()) else {
            return .result(dialog: "There are no more meetings in the loaded Fall 2026 schedule.")
        }
        let time = CampusFormatters.time.string(from: next.start)
        let day = CampusFormatters.compactDay.string(from: next.start)
        let location = await IntentScheduleProvider.location(for: next, engine: engine)
        let sourceLocation = IntentScheduleProvider.sourceLocationText(for: next, engine: engine)
        let locationText = location.map { " in \($0.feature.name)" }
            ?? sourceLocation.map { " in \($0)" }
            ?? ". Its location has not been added"
        return .result(dialog: "Your next class is \(next.course.code) on \(day) at \(time)\(locationText).")
    }
}

struct NavigateNextClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Navigate to Next Class"
    static let description = IntentDescription("Opens Apple Maps with directions to the next confirmed class building.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let engine = IntentScheduleProvider.engine()
        guard let next = engine.nextOccurrence(after: Date()) else { throw NavigationIntentError.noUpcomingClass }
        guard let location = await IntentScheduleProvider.location(for: next, engine: engine) else {
            throw NavigationIntentError.locationMissing(courseCode: next.course.code)
        }
        let mode = TravelMode(rawValue: UserDefaults.standard.string(forKey: "travelMode") ?? "walking") ?? .walking
        guard let url = NavigationActions.directionsURL(name: location.feature.name, coordinate: location.feature.coordinate, mode: mode) else {
            throw NavigationIntentError.invalidDirections
        }
        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: "Opening directions to \(location.feature.name) for \(next.course.code)."
        )
    }
}

struct ShowTodayScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today’s Schedule"
    static let description = IntentDescription("Opens Maroon Compass to the Today dashboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set("today", forKey: "pendingIntentTab")
        return .result(dialog: "Opening today’s schedule in Maroon Compass.")
    }
}

struct MaroonCompassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: ["What’s next in \(.applicationName)", "My next class in \(.applicationName)"],
            shortTitle: "What’s Next?",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: NavigateNextClassIntent(),
            phrases: ["Navigate to my next class with \(.applicationName)", "Directions to class in \(.applicationName)"],
            shortTitle: "Next Class Route",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: ShowTodayScheduleIntent(),
            phrases: ["Show today’s schedule in \(.applicationName)", "Open today in \(.applicationName)"],
            shortTitle: "Today’s Schedule",
            systemImageName: "calendar"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}

@MainActor
private enum IntentScheduleProvider {
    static func engine() -> ScheduleEngine {
        if
            let data = UserDefaults.standard.data(forKey: "importedSchedule"),
            let bundle = try? JSONDecoder().decode(ImportedScheduleBundle.self, from: data)
        {
            return ScheduleEngine(
                term: ScheduleSeed.term,
                courses: bundle.courses,
                patterns: bundle.patterns,
                oneTimeEvents: bundle.oneTimeEvents,
                exceptions: ScheduleSeed.exceptions
            )
        }
        return ScheduleEngine(
            term: ScheduleSeed.term,
            courses: ScheduleSeed.courses,
            patterns: ScheduleSeed.patterns,
            oneTimeEvents: ScheduleSeed.oneTimeEvents,
            exceptions: ScheduleSeed.exceptions
        )
    }

    static func locations() -> [String: CourseLocation] {
        guard let data = UserDefaults.standard.data(forKey: "courseLocations") else { return [:] }
        return (try? JSONDecoder().decode([String: CourseLocation].self, from: data)) ?? [:]
    }

    static func sourceLocationText(for occurrence: ScheduleOccurrence, engine: ScheduleEngine) -> String? {
        if occurrence.isSpecial {
            return engine.oneTimeEvents.first(where: { $0.id == occurrence.sourceMeetingID })?.sourceLocationText
        }
        return engine.patterns.first(where: { $0.id == occurrence.sourceMeetingID })?.sourceLocationText
    }

    static func location(for occurrence: ScheduleOccurrence, engine: ScheduleEngine) async -> CourseLocation? {
        if let manual = locations()[occurrence.course.id] { return manual }
        guard let sourceText = sourceLocationText(for: occurrence, engine: engine) else { return nil }
        let parts = sourceText
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let abbreviation = parts.first else { return nil }

        let service = CampusGISService()
        var features = await service.cachedFeatures()
        if features.isEmpty { features = (try? await service.fetchBuildings()) ?? [] }
        guard let feature = features.first(where: {
            $0.abbreviation?.localizedCaseInsensitiveCompare(abbreviation) == .orderedSame
        }) else { return nil }
        return CourseLocation(courseID: occurrence.course.id, feature: feature, room: parts.dropFirst().first)
    }
}

private enum NavigationIntentError: LocalizedError {
    case noUpcomingClass
    case locationMissing(courseCode: String)
    case invalidDirections

    var errorDescription: String? {
        switch self {
        case .noUpcomingClass:
            "There is no upcoming class in the loaded Fall 2026 schedule."
        case .locationMissing(let courseCode):
            "Open Maroon Compass once to load official campus data before requesting directions for \(courseCode)."
        case .invalidDirections:
            "Apple Maps directions could not be prepared."
        }
    }
}
