import CoreLocation
import UIKit

@MainActor
enum NavigationActions {
    static func openDirections(name: String, coordinate: CLLocationCoordinate2D, mode: TravelMode = .walking) {
        if let url = directionsURL(name: name, coordinate: coordinate, mode: mode) { UIApplication.shared.open(url) }
    }

    nonisolated static func directionsURL(name: String, coordinate: CLLocationCoordinate2D, mode: TravelMode = .walking) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: mode == .walking ? "w" : "d"),
            URLQueryItem(name: "q", value: name)
        ]
        return components?.url
    }
}
