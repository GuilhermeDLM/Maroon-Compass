import CoreLocation
import Foundation

enum Weekday: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case monday = "MO"
    case tuesday = "TU"
    case wednesday = "WE"
    case thursday = "TH"
    case friday = "FR"
    case saturday = "SA"
    case sunday = "SU"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var narrowName: String { String(shortName.prefix(1)) }

    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}

struct Course: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let code: String
    let section: String
    let title: String
    let credits: Int
    let catalogSummary: String
    let colorHex: String
    let symbol: String

    var displayCode: String { "\(code)-\(section)" }
}

struct MeetingPattern: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let courseID: String
    let weekdays: [Weekday]
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let sourceUntilUTC: String
    let excludedDates: [String]
    let additionalDates: [String]
    let sourceLocationText: String?
    let sourceNotes: String?

    init(
        id: String,
        courseID: String,
        weekdays: [Weekday],
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        sourceUntilUTC: String,
        excludedDates: [String] = [],
        additionalDates: [String] = [],
        sourceLocationText: String? = nil,
        sourceNotes: String? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.weekdays = weekdays
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.sourceUntilUTC = sourceUntilUTC
        self.excludedDates = excludedDates
        self.additionalDates = additionalDates
        self.sourceLocationText = sourceLocationText
        self.sourceNotes = sourceNotes
    }

    private enum CodingKeys: String, CodingKey {
        case id, courseID, weekdays, startHour, startMinute, endHour, endMinute, sourceUntilUTC
        case excludedDates, additionalDates, sourceLocationText, sourceNotes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        courseID = try container.decode(String.self, forKey: .courseID)
        weekdays = try container.decode([Weekday].self, forKey: .weekdays)
        startHour = try container.decode(Int.self, forKey: .startHour)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endHour = try container.decode(Int.self, forKey: .endHour)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        sourceUntilUTC = try container.decode(String.self, forKey: .sourceUntilUTC)
        excludedDates = try container.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
        additionalDates = try container.decodeIfPresent([String].self, forKey: .additionalDates) ?? []
        sourceLocationText = try container.decodeIfPresent(String.self, forKey: .sourceLocationText)
        sourceNotes = try container.decodeIfPresent(String.self, forKey: .sourceNotes)
    }
}

struct OneTimeEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let courseID: String
    let date: String
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let title: String
    let sourceLocationText: String?
    let sourceNotes: String?

    init(
        id: String,
        courseID: String,
        date: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        title: String,
        sourceLocationText: String? = nil,
        sourceNotes: String? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.date = date
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.title = title
        self.sourceLocationText = sourceLocationText
        self.sourceNotes = sourceNotes
    }
}

enum AcademicExceptionKind: String, Codable, Hashable, Sendable {
    case noClass
    case redefinedFriday
    case milestone
    case finals
}

struct AcademicException: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(date)-\(kind.rawValue)" }
    let date: String
    let kind: AcademicExceptionKind
    let title: String
    let detail: String
}

struct Term: Codable, Hashable, Sendable {
    let institution: String
    let campus: String
    let name: String
    let firstClassDate: String
    let lastClassDate: String
    let finalsStartDate: String
    let finalsEndDate: String
    let timeZoneIdentifier: String
}

struct ScheduleOccurrence: Identifiable, Hashable, Sendable {
    let id: String
    let course: Course
    let start: Date
    let end: Date
    let title: String
    let isSpecial: Bool
    let sourceMeetingID: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct TimeGap: Identifiable, Hashable, Sendable {
    let start: Date
    let end: Date
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct CoordinateValue: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum CampusFeatureCategory: String, Codable, Hashable, CaseIterable, Sendable {
    case academic
    case dining
    case transit
    case parking
    case health
    case safety
    case essential
    case landmark

    var title: String { rawValue.capitalized }
}

struct CampusFeature: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let abbreviation: String?
    let buildingNumber: String?
    let address: String?
    let coordinateValue: CoordinateValue
    let category: CampusFeatureCategory
    let officialURL: URL?
    let sourceName: String
    let fetchedAt: Date?

    var coordinate: CLLocationCoordinate2D { coordinateValue.coordinate }

    var searchText: String {
        [name, abbreviation, buildingNumber, address]
            .compactMap { $0 }
            .joined(separator: " ")
            .localizedLowercase
    }
}

struct CourseLocation: Identifiable, Codable, Hashable, Sendable {
    var id: String { courseID }
    let courseID: String
    let feature: CampusFeature
    var room: String?
}

struct ClassMapPin: Identifiable, Hashable, Sendable {
    let id: String
    let course: Course
    let location: CourseLocation
}

struct PlaceResult: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String?
    let coordinateValue: CoordinateValue
    let phoneNumber: String?
    let url: URL?
    let category: String
    let distanceMeters: CLLocationDistance?
    let walkingTime: TimeInterval?

    init(
        id: String,
        name: String,
        subtitle: String?,
        coordinateValue: CoordinateValue,
        phoneNumber: String?,
        url: URL?,
        category: String,
        distanceMeters: CLLocationDistance?,
        walkingTime: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinateValue = coordinateValue
        self.phoneNumber = phoneNumber
        self.url = url
        self.category = category
        self.distanceMeters = distanceMeters
        self.walkingTime = walkingTime
    }

    var coordinate: CLLocationCoordinate2D { coordinateValue.coordinate }
}

enum TravelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case walking
    case driving

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        }
    }
}

struct RouteEstimate: Identifiable, Hashable, Sendable {
    let id: String
    let destinationName: String
    let origin: CoordinateValue
    let destination: CoordinateValue
    let travelMode: TravelMode
    let travelTime: TimeInterval
    let distanceMeters: CLLocationDistance
    let path: [CoordinateValue]
    let calculatedAt: Date

    var wholeMinutes: Int { max(1, Int((travelTime / 60).rounded())) }
}

struct CalendarExportReport: Identifiable, Hashable, Sendable {
    let id = UUID()
    let addedCount: Int
    let existingCount: Int
    let calendarTitle: String
}

struct ResourceContact: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let phone: String?
    let url: URL?
    let symbol: String
    let isEmergency: Bool
    let lastVerified: String

    init(
        id: String,
        name: String,
        subtitle: String,
        phone: String?,
        url: URL?,
        symbol: String,
        isEmergency: Bool,
        lastVerified: String = "2026-08-18"
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.phone = phone
        self.url = url
        self.symbol = symbol
        self.isEmergency = isEmergency
        self.lastVerified = lastVerified
    }
}

struct ImportedScheduleBundle: Codable, Hashable, Sendable {
    let sourceName: String
    let importedAt: Date
    let courses: [Course]
    let patterns: [MeetingPattern]
    let oneTimeEvents: [OneTimeEvent]
    let diagnosticProperties: [String: [String: String]]?

    init(
        sourceName: String,
        importedAt: Date,
        courses: [Course],
        patterns: [MeetingPattern],
        oneTimeEvents: [OneTimeEvent],
        diagnosticProperties: [String: [String: String]]? = nil
    ) {
        self.sourceName = sourceName
        self.importedAt = importedAt
        self.courses = courses
        self.patterns = patterns
        self.oneTimeEvents = oneTimeEvents
        self.diagnosticProperties = diagnosticProperties
    }
}

struct CalendarImportReport: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sourceName: String
    let courseCount: Int
    let recurringMeetingCount: Int
    let oneTimeEventCount: Int
    let normalizedAnchorCount: Int
    let notes: [String]
}
