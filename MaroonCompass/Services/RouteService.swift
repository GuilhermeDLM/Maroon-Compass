import CoreLocation
import MapKit

actor RouteService {
    func calculate(
        from origin: CoordinateValue,
        to destination: CoordinateValue,
        destinationName: String,
        mode: TravelMode
    ) async throws -> RouteEstimate {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = mode == .walking ? .walking : .automobile
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            throw RouteError.noRoute
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: route.polyline.pointCount
        )
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))

        return RouteEstimate(
            id: routeID(origin: origin, destination: destination, mode: mode),
            destinationName: destinationName,
            origin: origin,
            destination: destination,
            travelMode: mode,
            travelTime: route.expectedTravelTime,
            distanceMeters: route.distance,
            path: coordinates.map { CoordinateValue(latitude: $0.latitude, longitude: $0.longitude) },
            calculatedAt: Date()
        )
    }

    nonisolated func routeID(origin: CoordinateValue, destination: CoordinateValue, mode: TravelMode) -> String {
        let values = [origin.latitude, origin.longitude, destination.latitude, destination.longitude]
            .map { String(format: "%.5f", $0) }
            .joined(separator: ":")
        return "\(mode.rawValue):\(values)"
    }
}

enum RouteError: LocalizedError {
    case locationUnavailable
    case noRoute

    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            "Current location is not available. Allow location access or try again after the GPS indicator settles."
        case .noRoute:
            "Apple Maps could not find a route to this destination."
        }
    }
}
