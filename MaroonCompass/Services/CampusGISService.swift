import Foundation

actor CampusGISService {
    private let cacheFileName = "campus-buildings-v2.json"
    private let mapFeatureCacheFileName = "campus-map-features-v1.json"

    func cachedFeatures() -> [CampusFeature] {
        guard
            let url = cacheURL(),
            let data = try? Data(contentsOf: url),
            let features = try? JSONDecoder().decode([CampusFeature].self, from: data)
        else { return [] }
        return features
    }

    func fetchBuildings() async throws -> [CampusFeature] {
        var components = URLComponents(string: "https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer/2/query")
        components?.queryItems = [
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(name: "outFields", value: "OBJECTID,BldgNum,BldgAbbr,BldgName,Address,City,Zip,Longitude,Latitude,AggiemapBuildingLink"),
            URLQueryItem(name: "geometry", value: "-96.39,30.59,-96.30,30.66"),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components?.url else { throw CampusDataError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CampusDataError.badResponse
        }

        let payload = try JSONDecoder().decode(ArcGISResponse.self, from: data)
        let now = Date()
        let features = payload.features.compactMap { item -> CampusFeature? in
            let properties = item.attributes
            guard
                let objectID = properties.objectID,
                let name = properties.buildingName?.trimmedNonempty
            else { return nil }

            let coordinate: CoordinateValue?
            if let latitude = properties.latitude, let longitude = properties.longitude {
                coordinate = CoordinateValue(latitude: latitude, longitude: longitude)
            } else if let rings = item.geometry?.rings {
                coordinate = polygonCenter(rings)
            } else {
                coordinate = nil
            }
            guard
                let coordinate,
                (30.59...30.66).contains(coordinate.latitude),
                (-96.39 ... -96.30).contains(coordinate.longitude)
            else { return nil }

            let addressParts = [properties.address?.trimmedNonempty, properties.city?.trimmedNonempty]
                .compactMap { $0 }

            return CampusFeature(
                id: "tamu-building-\(objectID)",
                name: name,
                abbreviation: properties.buildingAbbreviation?.trimmedNonempty,
                buildingNumber: properties.buildingNumber?.trimmedNonempty,
                address: addressParts.isEmpty ? nil : addressParts.joined(separator: ", "),
                coordinateValue: coordinate,
                category: .academic,
                officialURL: properties.aggieMapLink.flatMap(URL.init(string:)),
                sourceName: "Texas A&M Facilities Analytics & Mapping",
                fetchedAt: now
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if let cacheURL = cacheURL(), let encoded = try? JSONEncoder().encode(features) {
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        return features
    }

    func cachedMapFeatures() -> [CampusFeature] {
        guard
            let url = cacheURL(fileName: mapFeatureCacheFileName),
            let data = try? Data(contentsOf: url),
            let features = try? JSONDecoder().decode([CampusFeature].self, from: data)
        else { return [] }
        return features
    }

    func fetchParkingFeatures() async throws -> [CampusFeature] {
        async let garages = fetchParkingLayer(id: 0, sourceLabel: "Garage Parking")
        async let surfaceLots = fetchParkingLayer(id: 9, sourceLabel: "Surface Parking")
        let features = try await (garages + surfaceLots).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if let cacheURL = cacheURL(fileName: mapFeatureCacheFileName), let encoded = try? JSONEncoder().encode(features) {
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        return features
    }

    private func fetchParkingLayer(id layerID: Int, sourceLabel: String) async throws -> [CampusFeature] {
        var components = URLComponents(string: "https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer/\(layerID)/query")
        components?.queryItems = [
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(name: "outFields", value: "OBJECTID,LotName,Name,LotType"),
            URLQueryItem(name: "geometry", value: "-96.39,30.59,-96.30,30.66"),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components?.url else { throw CampusDataError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CampusDataError.badResponse
        }

        let payload = try JSONDecoder().decode(ArcGISParkingResponse.self, from: data)
        let now = Date()
        return payload.features.compactMap { item in
            guard
                let objectID = item.attributes.objectID,
                let coordinate = polygonCenter(item.geometry.rings),
                (30.59...30.66).contains(coordinate.latitude),
                (-96.39 ... -96.30).contains(coordinate.longitude)
            else { return nil }
            let name = item.attributes.lotName?.trimmedNonempty
                ?? item.attributes.name?.trimmedNonempty
                ?? "Campus parking"
            let abbreviation = item.attributes.name?.trimmedNonempty == name ? nil : item.attributes.name?.trimmedNonempty
            return CampusFeature(
                id: "tamu-parking-\(layerID)-\(objectID)",
                name: name,
                abbreviation: abbreviation,
                buildingNumber: nil,
                address: item.attributes.lotType?.trimmedNonempty,
                coordinateValue: coordinate,
                category: .parking,
                officialURL: URL(string: "https://transport.tamu.edu/Parking/"),
                sourceName: "Texas A&M Facilities Analytics & Mapping · \(sourceLabel)",
                fetchedAt: now
            )
        }
    }

    private func polygonCenter(_ rings: [[[Double]]]) -> CoordinateValue? {
        let points = rings.flatMap { $0 }.filter { $0.count >= 2 }
        guard
            let minimumLongitude = points.map({ $0[0] }).min(),
            let maximumLongitude = points.map({ $0[0] }).max(),
            let minimumLatitude = points.map({ $0[1] }).min(),
            let maximumLatitude = points.map({ $0[1] }).max()
        else { return nil }
        return CoordinateValue(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
    }

    private func cacheURL() -> URL? {
        cacheURL(fileName: cacheFileName)
    }

    private func cacheURL(fileName: String) -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return directory.appendingPathComponent(fileName)
    }
}

private struct ArcGISParkingResponse: Decodable {
    let features: [ArcGISParkingFeature]
}

private struct ArcGISParkingFeature: Decodable {
    let attributes: ArcGISParkingAttributes
    let geometry: ArcGISPolygonGeometry
}

private struct ArcGISPolygonGeometry: Decodable {
    let rings: [[[Double]]]
}

private struct ArcGISParkingAttributes: Decodable {
    let objectID: Int?
    let lotName: String?
    let name: String?
    let lotType: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "OBJECTID"
        case lotName = "LotName"
        case name = "Name"
        case lotType = "LotType"
    }
}

private struct ArcGISResponse: Decodable {
    let features: [ArcGISFeature]
}

private struct ArcGISFeature: Decodable {
    let attributes: ArcGISAttributes
    let geometry: ArcGISPolygonGeometry?
}

private struct ArcGISAttributes: Decodable {
    let objectID: Int?
    let buildingNumber: String?
    let buildingAbbreviation: String?
    let buildingName: String?
    let address: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let aggieMapLink: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "OBJECTID"
        case buildingNumber = "BldgNum"
        case buildingAbbreviation = "BldgAbbr"
        case buildingName = "BldgName"
        case address = "Address"
        case city = "City"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case aggieMapLink = "AggiemapBuildingLink"
    }
}

private enum CampusDataError: LocalizedError {
    case invalidURL
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The campus data address is invalid."
        case .badResponse: "Texas A&M campus data is temporarily unavailable."
        }
    }
}

private extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
