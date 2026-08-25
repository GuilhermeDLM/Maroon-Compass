import SwiftUI

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedFeature: CampusFeature?
    @State private var selectedPlace: PlaceResult?
    @State private var pendingEmergency: ResourceContact?
    @State private var resourceQuery = ""

    var body: some View {
        List {
            Section("Class locations") {
                if store.classMapPins.isEmpty {
                    EmptyStateView(
                        symbol: "mappin.slash",
                        title: "No class locations yet",
                        message: "Verified schedule locations will appear after official campus data loads.",
                        actionTitle: "Open schedule",
                        action: { store.selectedTab = .schedule }
                    )
                } else {
                    ForEach(store.classMapPins) { pin in
                            Button { selectedFeature = pin.location.feature } label: {
                                HStack(spacing: 12) {
                                    CourseGlyph(course: pin.course, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pin.course.code).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text([pin.location.feature.abbreviation ?? pin.location.feature.name, pin.location.room].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                    }
                }
            }

            Section("Favorite buildings") {
                if store.favoriteFeatures.isEmpty {
                    Text("Save useful buildings or parking areas from the campus map for quick access here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(store.favoriteFeatures) { feature in
                        Button { selectedFeature = feature } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.name).foregroundStyle(.primary)
                                    Text(feature.address ?? feature.sourceName).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "bookmark.fill").foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) { store.toggleFavorite(store.favoriteFeatures[index]) }
                    }
                }
            }

            Section("Favorite nearby places") {
                if store.favoritePlaces.isEmpty {
                    Text("Save restaurants, coffee shops, groceries, and pharmacies from the map.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(store.favoritePlaces) { place in
                        Button { selectedPlace = place } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).foregroundStyle(.primary)
                                    Text(place.subtitle ?? place.category).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(.blue)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) { store.toggleFavorite(store.favoritePlaces[index]) }
                    }
                }
            }

            if !store.recentPlaceSearches.isEmpty {
                Section {
                    ForEach(store.recentPlaceSearches, id: \.self) { search in
                        Button {
                            store.requestedMapSearch = search
                            store.selectedTab = .map
                        } label: {
                            Label(search.capitalized, systemImage: "clock.arrow.circlepath")
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent map searches")
                        Spacer()
                        Button("Clear") { store.clearRecentSearches() }
                            .font(.caption)
                    }
                }
            }

            Section {
                if filteredResources.isEmpty {
                    Text("No matching campus resource.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredResources) { resource in
                        HStack(spacing: 8) {
                            Button {
                                if resource.isEmergency {
                                    pendingEmergency = resource
                                } else {
                                    openResource(resource)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: resource.symbol)
                                        .foregroundStyle(resource.isEmergency ? .red : AppTheme.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(resource.name).foregroundStyle(.primary)
                                        Text(resource.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if resource.phone != nil { Image(systemName: "phone.fill").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            .buttonStyle(.plain)
                            if let url = resource.url, resource.phone != nil {
                                Link(destination: url) { Image(systemName: "safari.fill") }
                                    .accessibilityLabel("Open official page for \(resource.name)")
                            }
                        }
                    }
                }
            } header: {
                Text("Help and safety")
            } footer: {
                Text("Contacts and official links verified August 18, 2026. Maroon Compass is not an emergency service. In immediate danger, call 911.")
            }
        }
        .navigationTitle("Saved")
        .searchable(text: $resourceQuery, prompt: "Search help, health, food, transit…")
        .sheet(item: $selectedFeature) { feature in
            NavigationStack { CampusFeatureDetailView(feature: feature) }
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedPlace) { place in
            NavigationStack { PlaceDetailView(place: place) }
                .presentationDetents([.medium])
        }
        .alert("Call 911?", isPresented: Binding(get: { pendingEmergency != nil }, set: { if !$0 { pendingEmergency = nil } })) {
            Button("Cancel", role: .cancel) { pendingEmergency = nil }
            Button("Call 911", role: .destructive) {
                if let resource = pendingEmergency { openResource(resource) }
                pendingEmergency = nil
            }
        } message: {
            Text("Call only for a police, fire, or medical emergency.")
        }
    }

    private var filteredResources: [ResourceContact] {
        let clean = resourceQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !clean.isEmpty else { return ScheduleSeed.resources }
        return ScheduleSeed.resources.filter {
            "\($0.name) \($0.subtitle)".localizedLowercase.contains(clean)
        }
    }

    private func openResource(_ resource: ResourceContact) {
        if let phone = resource.phone, let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
            UIApplication.shared.open(url)
        } else if let url = resource.url {
            UIApplication.shared.open(url)
        }
    }
}
