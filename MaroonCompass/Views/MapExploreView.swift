import CoreLocation
import MapKit
import SwiftUI

private enum MapExploreCategory: String, CaseIterable, Identifiable {
    case campus = "Campus"
    case parking = "Parking"
    case transit = "Transit"
    case restaurants = "Food"
    case coffee = "Coffee"
    case groceries = "Groceries"
    case pharmacy = "Pharmacy"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .campus: "building.2.fill"
        case .parking: "parkingsign.circle.fill"
        case .transit: "bus.fill"
        case .restaurants: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .groceries: "basket.fill"
        case .pharmacy: "cross.case.fill"
        }
    }

    var searchQuery: String {
        switch self {
        case .campus, .parking, .transit: ""
        case .restaurants: "restaurants"
        case .coffee: "coffee"
        case .groceries: "grocery stores"
        case .pharmacy: "pharmacy"
        }
    }

    var usesOfficialGIS: Bool {
        self == .campus || self == .parking || self == .transit
    }
}

private enum CampusMapStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case hybrid = "Hybrid"
    case imagery = "Imagery"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "square.3.layers.3d"
        case .imagery: "globe.americas.fill"
        }
    }
}

private enum PlaceSearchAnchor: String, CaseIterable, Identifiable {
    case current = "My location"
    case campus = "Campus center"
    case nextClass = "Next class"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .current: "location.fill"
        case .campus: "building.2.fill"
        case .nextClass: "graduationcap.fill"
        }
    }
}

struct MapExploreView: View {
    @Environment(AppStore.self) private var store
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.6180, longitude: -96.3386),
        latitudinalMeters: 4_800,
        longitudinalMeters: 4_800
    ))
    @State private var category: MapExploreCategory = .campus
    @State private var mapStyle: CampusMapStyle = .standard
    @State private var query = ""
    @State private var selectedFeature: CampusFeature?
    @State private var selectedPlace: PlaceResult?
    @State private var isSourceSheetPresented = false
    @State private var placeAnchor: PlaceSearchAnchor = .campus
    @State private var walkingLimitMinutes = 0

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-UIMapCategory"), arguments.indices.contains(index + 1) {
            let value = arguments[index + 1].localizedLowercase
            _category = State(initialValue: MapExploreCategory.allCases.first(where: { $0.rawValue.localizedLowercase == value }) ?? .campus)
        }
    }

    private var matchingBuildings: [CampusFeature] {
        guard category == .campus else { return [] }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !clean.isEmpty else { return [] }
        return store.campusFeatures.filter { $0.searchText.contains(clean) }.prefix(100).map { $0 }
    }

    private var matchingParking: [CampusFeature] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !clean.isEmpty else { return store.mapFeatures }
        return store.mapFeatures.filter { $0.searchText.contains(clean) }
    }

    private var displayedParking: [CampusFeature] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return matchingParking }
        return store.mapFeatures.filter {
            let type = $0.address?.localizedLowercase ?? ""
            return type.contains("garage") || type.contains("visitor")
        }
    }

    private var filteredPlaceResults: [PlaceResult] {
        guard walkingLimitMinutes > 0 else { return store.placeResults }
        return store.placeResults.filter {
            guard let walkingTime = $0.walkingTime else { return false }
            return walkingTime <= Double(walkingLimitMinutes * 60)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                searchPanel
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { resultShelf }
            .navigationTitle("Campus Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    mapOptions
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("My location", systemImage: "location.fill") {
                        store.locationService.requestLocation()
                        if let coordinate = store.locationService.currentLocation?.coordinate {
                            withAnimation { position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_600, longitudinalMeters: 1_600)) }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedFeature) { feature in
            NavigationStack { CampusFeatureDetailView(feature: feature) }
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedPlace) { place in
            NavigationStack { PlaceDetailView(place: place) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $isSourceSheetPresented) {
            NavigationStack { MapSourcesView() }
                .presentationDetents([.medium, .large])
        }
        .onChange(of: store.requestedMapSearch) { _, request in
            guard let request else { return }
            category = category(for: request)
            query = request
            Task { await store.searchPlaces(query: request, center: searchCenter) }
            store.requestedMapSearch = nil
        }
    }

    @ViewBuilder
    private var map: some View {
        switch mapStyle {
        case .standard:
            baseMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            baseMap.mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            baseMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var baseMap: some View {
        Map(position: $position) {
            UserAnnotation()

            if let route = store.activeRoute {
                MapPolyline(coordinates: route.path.map(\.coordinate))
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            ForEach(store.dayRoutes) { route in
                MapPolyline(coordinates: route.path.map(\.coordinate))
                    .stroke(AppTheme.accent.opacity(0.82), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            ForEach(store.classMapPins) { pin in
                Annotation(pin.course.code, coordinate: pin.location.feature.coordinate) {
                    Button { selectedFeature = pin.location.feature } label: {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(pin.course.tint, in: Circle())
                                .shadow(radius: 3, y: 2)
                    }
                    .accessibilityLabel("\(pin.course.code), \(pin.location.feature.name)")
                }
            }

            ForEach(matchingBuildings) { feature in
                Annotation(feature.abbreviation ?? feature.name, coordinate: feature.coordinate) {
                    Button { selectedFeature = feature } label: {
                        Image(systemName: "building.2.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                            .padding(7)
                            .background(.background, in: Circle())
                            .shadow(radius: 2, y: 1)
                    }
                    .accessibilityLabel(feature.name)
                }
            }

            if category == .parking {
                ForEach(displayedParking) { feature in
                    Annotation(feature.abbreviation ?? feature.name, coordinate: feature.coordinate) {
                        Button { selectedFeature = feature } label: {
                            Image(systemName: "parkingsign")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.blue, in: Circle())
                                .shadow(radius: 2, y: 1)
                        }
                        .accessibilityLabel(feature.name)
                    }
                }
            }

            ForEach(filteredPlaceResults) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Button { selectedPlace = place } label: {
                        Image(systemName: category.symbol)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.blue, in: Circle())
                            .shadow(radius: 2, y: 1)
                    }
                    .accessibilityLabel(place.name)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var mapOptions: some View {
        Menu {
            Picker("Map style", selection: $mapStyle) {
                ForEach(CampusMapStyle.allCases) { style in
                    Label(style.rawValue, systemImage: style.symbol).tag(style)
                }
            }

            Divider()

            Button("Route between today’s classes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                Task {
                    await store.calculateDayRoute(on: store.selectedDate)
                    frameCurrentRoutes()
                }
            }
            Button("Route to next class", systemImage: "location.north.fill") {
                routeToNextClass()
            }
            .disabled(nextLocatedClass == nil)

            if store.activeRoute != nil || !store.dayRoutes.isEmpty || store.routeError != nil {
                Button("Clear route", systemImage: "xmark", role: .destructive) { store.clearRoutes() }
            }

            Divider()
            Button("Map data and attribution", systemImage: "info.circle") { isSourceSheetPresented = true }
        } label: {
            Image(systemName: "square.3.layers.3d")
        }
        .accessibilityLabel("Map options")
    }

    private var searchPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { submitSearch() }
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        query = ""
                        if !category.usesOfficialGIS { store.placeResults = [] }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MapExploreCategory.allCases) { item in
                        Button {
                            category = item
                            query = ""
                            if item.usesOfficialGIS {
                                store.placeResults = []
                            } else {
                                Task { await store.searchPlaces(query: item.searchQuery, center: searchCenter) }
                            }
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(category == item ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(category == item ? AppTheme.accent : Color(.secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !category.usesOfficialGIS {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(PlaceSearchAnchor.allCases) { anchor in
                            Button {
                                placeAnchor = anchor
                                Task { await store.searchPlaces(query: query.isEmpty ? category.searchQuery : query, center: searchCenter) }
                            } label: {
                                Label(anchor.rawValue, systemImage: anchor.symbol)
                            }
                            .disabled(
                                (anchor == .nextClass && nextLocatedClass == nil) ||
                                (anchor == .current && store.locationService.currentLocation == nil)
                            )
                        }
                    } label: {
                        Label(placeAnchor.rawValue, systemImage: placeAnchor.symbol)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button("Any walking time") { walkingLimitMinutes = 0 }
                        ForEach([10, 20, 30], id: \.self) { minutes in
                            Button("Under \(minutes) minutes") { walkingLimitMinutes = minutes }
                        }
                    } label: {
                        Label(walkingLimitMinutes == 0 ? "Any walk" : "≤ \(walkingLimitMinutes) min", systemImage: "figure.walk")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var resultShelf: some View {
        if store.isLoadingRoute {
            mapStatusCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Calculating route…", detail: "Apple Maps is finding a real \(store.travelMode.title.lowercased()) route.")
        } else if let route = store.activeRoute {
            routeStatusCard(title: "\(route.wholeMinutes) min to \(route.destinationName)", detail: routeDistance(route.distanceMeters))
        } else if !store.dayRoutes.isEmpty {
            routeStatusCard(
                title: "Day route · \(store.dayRoutes.count) segment\(store.dayRoutes.count == 1 ? "" : "s")",
                detail: "\(store.dayRoutes.reduce(0) { $0 + $1.wholeMinutes }) walking minutes between confirmed class buildings"
            )
        } else if let error = store.routeError {
            mapStatusCard(icon: "exclamationmark.triangle.fill", title: "Route unavailable", detail: error)
        } else if category == .campus {
            if query.isEmpty {
                mapStatusCard(
                    icon: "building.2.fill",
                    title: "\(store.campusFeatures.count) official buildings",
                    detail: store.courseLocations.isEmpty ? "Search by name, abbreviation, or building number. Add class locations from each course." : "Your confirmed class buildings are pinned in course colors."
                )
            } else if matchingBuildings.isEmpty {
                mapStatusCard(icon: "magnifyingglass", title: "No building found", detail: "Try a full name, abbreviation, or building number.")
            } else {
                horizontalFeatureShelf(features: matchingBuildings)
            }
        } else if category == .parking {
            if store.isLoadingCampus && store.mapFeatures.isEmpty {
                mapStatusCard(icon: category.symbol, title: "Loading official parking…", detail: "Fetching garages and surface lots from Texas A&M GIS.")
            } else if query.isEmpty {
                mapStatusCard(
                    icon: category.symbol,
                    title: "\(store.mapFeatures.count) official parking areas",
                    detail: store.mapFeatureError ?? "Garages and visitor lots are pinned at campus scale; search any lot by number. Verify eligibility and availability with Transportation Services."
                )
            } else if matchingParking.isEmpty {
                mapStatusCard(icon: "magnifyingglass", title: "No parking found", detail: "Try a lot number, garage name, or parking type.")
            } else {
                horizontalFeatureShelf(features: matchingParking)
            }
        } else if category == .transit {
            transportationFallbackCard
        } else if store.isSearchingPlaces {
            mapStatusCard(icon: "location.magnifyingglass", title: "Looking nearby…", detail: "Searching around the Texas A&M campus.")
        } else if let error = store.placeError {
            mapStatusCard(icon: "wifi.exclamationmark", title: "Places unavailable", detail: error)
        } else if filteredPlaceResults.isEmpty {
            mapStatusCard(icon: category.symbol, title: "No nearby results", detail: "Try another category or a more specific search.")
        } else {
            horizontalPlaceShelf
        }
    }

    private func horizontalFeatureShelf(features: [CampusFeature]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(features.prefix(20)) { feature in
                    Button {
                        selectedFeature = feature
                        withAnimation { position = .region(MKCoordinateRegion(center: feature.coordinate, latitudinalMeters: 900, longitudinalMeters: 900)) }
                    } label: {
                        resultCard(title: feature.name, subtitle: [feature.abbreviation, feature.buildingNumber].compactMap { $0 }.joined(separator: " · "), symbol: "building.2.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var horizontalPlaceShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredPlaceResults.prefix(20)) { place in
                    Button {
                        selectedPlace = place
                        withAnimation { position = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 900, longitudinalMeters: 900)) }
                    } label: {
                        resultCard(title: place.name, subtitle: distanceLabel(place), symbol: category.symbol)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func mapStatusCard(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    private func resultCard(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(AppTheme.accent).frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func submitSearch() {
        guard !category.usesOfficialGIS else { return }
        let request = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await store.searchPlaces(query: request.isEmpty ? category.searchQuery : request, center: searchCenter) }
    }

    private func distanceLabel(_ place: PlaceResult) -> String {
        if let walkingTime = place.walkingTime {
            let minutes = max(1, Int((walkingTime / 60).rounded()))
            guard let distance = place.distanceMeters else { return "\(minutes) min walk" }
            let distanceText = distance < 1_000 ? "\(Int(distance)) m" : String(format: "%.1f km", distance / 1_000)
            return "\(minutes) min walk · \(distanceText)"
        }
        guard let distance = place.distanceMeters else { return place.subtitle ?? place.category }
        if distance < 1_000 { return "\(Int(distance)) m away" }
        return String(format: "%.1f km away", distance / 1_000)
    }

    private var searchCenter: CLLocationCoordinate2D {
        switch placeAnchor {
        case .current:
            return store.locationService.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 30.6180, longitude: -96.3386)
        case .campus:
            return CLLocationCoordinate2D(latitude: 30.6180, longitude: -96.3386)
        case .nextClass:
            return nextLocatedClass?.1.feature.coordinate ?? CLLocationCoordinate2D(latitude: 30.6180, longitude: -96.3386)
        }
    }

    private var searchPrompt: String {
        switch category {
        case .campus: "Search official campus buildings"
        case .parking: "Search lots and garages"
        case .transit: "Use the official transit links below"
        default: "Search nearby \(category.rawValue.lowercased())"
        }
    }

    private func category(for request: String) -> MapExploreCategory {
        let value = request.localizedLowercase
        if value.contains("coffee") || value.contains("cafe") { return .coffee }
        if value.contains("grocery") || value.contains("market") { return .groceries }
        if value.contains("pharmacy") { return .pharmacy }
        return .restaurants
    }

    private var nextLocatedClass: (ScheduleOccurrence, CourseLocation)? {
        guard let next = store.engine.nextOccurrence(after: Date()), let location = store.location(for: next) else { return nil }
        return (next, location)
    }

    private func routeToNextClass() {
        guard let (_, location) = nextLocatedClass else { return }
        store.locationService.requestLocation()
        Task {
            if await store.calculateRoute(to: location.feature.coordinateValue, destinationName: location.feature.name) != nil {
                frameCurrentRoutes()
            }
        }
    }

    private func frameCurrentRoutes() {
        let coordinates = (store.activeRoute.map { [$0] } ?? store.dayRoutes).flatMap(\.path)
        guard
            let minimumLatitude = coordinates.map(\.latitude).min(),
            let maximumLatitude = coordinates.map(\.latitude).max(),
            let minimumLongitude = coordinates.map(\.longitude).min(),
            let maximumLongitude = coordinates.map(\.longitude).max()
        else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.45, 0.004),
                    longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.45, 0.004)
                )
            ))
        }
    }

    private func routeStatusCard(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: store.travelMode.symbol).foregroundStyle(AppTheme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Clear", systemImage: "xmark.circle.fill") { store.clearRoutes() }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    private func routeDistance(_ meters: Double) -> String {
        let distance = meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
        return "\(store.travelMode.title) route · \(distance) · Apple Maps estimate"
    }

    private var transportationFallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "bus.fill").foregroundStyle(AppTheme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Official transit information").font(.subheadline.weight(.semibold))
                    Text("The public transportation GIS service is currently offline, so Maroon Compass does not show stale or invented bus pins.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if let buses = URL(string: "https://transport.tamu.edu/busroutes/") {
                    Link("Bus routes", destination: buses).buttonStyle(.borderedProminent)
                }
                if let parking = URL(string: "https://transport.tamu.edu/Parking/") {
                    Link("Transportation", destination: parking).buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
}

struct CampusFeatureDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let feature: CampusFeature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.accent)
                Text(feature.name).font(.title2.bold())
                Label(feature.category.title, systemImage: feature.category == .parking ? "parkingsign.circle.fill" : "building.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                if let address = feature.address { Label(address, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                if let fetchedAt = feature.fetchedAt {
                    Label("Official campus data · fetched \(fetchedAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.shield.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                routeSummary(destination: feature.coordinateValue)
                HStack {
                    Button("Directions", systemImage: store.travelMode.symbol) {
                        NavigationActions.openDirections(name: feature.name, coordinate: feature.coordinate, mode: store.travelMode)
                    }
                        .buttonStyle(.borderedProminent)
                    Button(store.isFavorite(feature) ? "Saved" : "Save", systemImage: store.isFavorite(feature) ? "bookmark.fill" : "bookmark") {
                        store.toggleFavorite(feature)
                    }
                    .buttonStyle(.bordered)
                }
                HStack {
                    Button("Estimate from my location", systemImage: "location.fill") {
                        store.locationService.requestLocation()
                        Task { await store.calculateRoute(to: feature.coordinateValue, destinationName: feature.name) }
                    }
                    .buttonStyle(.bordered)
                    if let url = NavigationActions.directionsURL(name: feature.name, coordinate: feature.coordinate, mode: store.travelMode) {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                }
                if let url = feature.officialURL {
                    Link(feature.category == .parking ? "Open Transportation Services" : "Open in official Aggie Map", destination: url)
                        .font(.subheadline.weight(.semibold))
                }
                Text("Source: \(feature.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Campus building")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder
    private func routeSummary(destination: CoordinateValue) -> some View {
        if let route = store.activeRoute, route.destination == destination {
            Label("\(route.wholeMinutes) min · \(routeDistance(route.distanceMeters)) by \(route.travelMode.title.lowercased())", systemImage: route.travelMode.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        } else if store.isLoadingRoute {
            ProgressView("Calculating Apple Maps route…")
        } else if let error = store.routeError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func routeDistance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
    }
}

struct PlaceDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let place: PlaceResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text(place.name).font(.title2.bold())
                if let subtitle = place.subtitle { Label(subtitle, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                Text("Place details are supplied by Apple Maps and may change. Verify hours and dietary information before leaving.")
                    .font(.caption).foregroundStyle(.secondary)
                if let route = store.activeRoute, route.destination == place.coordinateValue {
                    Label("\(route.wholeMinutes) min · \(routeDistance(route.distanceMeters)) by \(route.travelMode.title.lowercased())", systemImage: route.travelMode.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                } else if store.isLoadingRoute {
                    ProgressView("Calculating Apple Maps route…")
                }
                HStack {
                    Button("Directions", systemImage: store.travelMode.symbol) {
                        NavigationActions.openDirections(name: place.name, coordinate: place.coordinate, mode: store.travelMode)
                    }
                        .buttonStyle(.borderedProminent)
                    if let phone = place.phoneNumber, let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                        Link(destination: url) { Label("Call", systemImage: "phone.fill") }.buttonStyle(.bordered)
                    }
                    Button(store.isFavorite(place) ? "Saved" : "Save", systemImage: store.isFavorite(place) ? "bookmark.fill" : "bookmark") {
                        store.toggleFavorite(place)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Estimate from my location", systemImage: "location.fill") {
                    store.locationService.requestLocation()
                    Task { await store.calculateRoute(to: place.coordinateValue, destinationName: place.name) }
                }
                .buttonStyle(.bordered)
                if let url = place.url { Link("Visit website", destination: url).font(.subheadline.weight(.semibold)) }
            }
            .padding(20)
        }
        .navigationTitle("Nearby place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func routeDistance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
    }
}

private struct MapSourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Label("Apple Maps provides the basemap, nearby businesses, place details, and route estimates.", systemImage: "map.fill")
                Label("Texas A&M Facilities Analytics & Mapping provides building and parking geometry.", systemImage: "building.2.fill")
            }
            Section("Official sources") {
                if let url = URL(string: "https://aggiemap.tamu.edu/") { Link("Aggie Map", destination: url) }
                if let url = URL(string: "https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer") { Link("Campus ArcGIS service", destination: url) }
                if let url = URL(string: "https://transport.tamu.edu/") { Link("Transportation Services", destination: url) }
                if let url = URL(string: "https://www.tamu.edu/campus-community/dining.html") { Link("Aggie Dining", destination: url) }
            }
            Section("Freshness and fallbacks") {
                Text("Official features are cached on device for offline use and labeled with their fetch date. If a university layer is unavailable, Maroon Compass keeps the map usable and links to the exact official service instead of inventing pins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Map data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
