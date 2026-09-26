// Linux-only stand-in for the two CoreLocation value types used by ScheduleModels.swift.
// It lets the cloud harness compile the app's real model files; it is never part of the app.

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double

public struct CLLocationCoordinate2D: Sendable, Hashable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
