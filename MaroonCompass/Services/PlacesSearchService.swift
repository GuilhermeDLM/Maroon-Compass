import CoreLocation
import MapKit

@MainActor
final class PlacesSearchService {
    func search(query: String, center: CLLocationCoordinate2D) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 6_500,
            longitudinalMeters: 6_500
        )
        request.resultTypes = .pointOfInterest

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)

        var results: [PlaceResult] = []
        for item in response.mapItems.prefix(40) {
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let subtitle = [item.placemark.subThoroughfare, item.placemark.thoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            let name = item.name ?? "Unnamed place"
            let identifier = name + "-" + String(coordinate.latitude) + "-" + String(coordinate.longitude)
            results.append(PlaceResult(
                id: identifier,
                name: name,
                subtitle: subtitle.isEmpty ? item.placemark.locality : subtitle,
                coordinateValue: CoordinateValue(latitude: coordinate.latitude, longitude: coordinate.longitude),
                phoneNumber: item.phoneNumber,
                url: item.url,
                category: query.capitalized,
                distanceMeters: distance,
                walkingTime: nil
            ))
        }
        results.sort {
            let left = $0.distanceMeters ?? Double.greatestFiniteMagnitude
            let right = $1.distanceMeters ?? Double.greatestFiniteMagnitude
            return left < right
        }

        var enriched = results
        await withTaskGroup(of: (Int, TimeInterval?, CLLocationDistance?).self) { group in
            for (index, result) in results.prefix(16).enumerated() {
                group.addTask {
                    let estimate = await Self.walkingETA(from: center, to: result.coordinate)
                    return (index, estimate?.time, estimate?.distance)
                }
            }
            for await (index, time, routeDistance) in group where enriched.indices.contains(index) {
                let value = enriched[index]
                enriched[index] = PlaceResult(
                    id: value.id,
                    name: value.name,
                    subtitle: value.subtitle,
                    coordinateValue: value.coordinateValue,
                    phoneNumber: value.phoneNumber,
                    url: value.url,
                    category: value.category,
                    distanceMeters: routeDistance ?? value.distanceMeters,
                    walkingTime: time
                )
            }
        }
        enriched.sort {
            let leftTime = $0.walkingTime ?? Double.greatestFiniteMagnitude
            let rightTime = $1.walkingTime ?? Double.greatestFiniteMagnitude
            if leftTime != rightTime { return leftTime < rightTime }
            return ($0.distanceMeters ?? Double.greatestFiniteMagnitude) < ($1.distanceMeters ?? Double.greatestFiniteMagnitude)
        }
        return enriched
    }

    nonisolated private static func walkingETA(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> (time: TimeInterval, distance: CLLocationDistance)? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
        return (response.expectedTravelTime, response.distance)
    }
}
