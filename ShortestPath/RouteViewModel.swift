//
//  RouteViewModel.swift
//  ShortestPath
//
//  Created by Sandesh on 21/02/26.
//

import Combine
import MapKit
import SwiftUI

@MainActor
final class RouteViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var selectedLocations: [Location] = []
    @Published var orderedLocations: [Location] = []
    @Published var routeSegments: [RouteSegment] = []
    @Published var startLocationID: UUID?
    @Published var endLocationID: UUID?
    @Published var isSearching = false
    @Published var isRouting = false
    @Published var errorMessage: String?
    @Published var travelMode: TravelMode = .automobile
    @Published var totalDistance: Measurement<UnitLength>?
    @Published var totalTravelTime: TimeInterval?
    @Published var visibleRegion: MKCoordinateRegion?
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        )
    )

    var displayLocations: [Location] {
        if !orderedLocations.isEmpty {
            return orderedLocations
        }
        return selectedLocations
    }

    var indexedLocations: [IndexedLocation] {
        displayLocations.enumerated().map { IndexedLocation(index: $0.offset, location: $0.element) }
    }

    var startLocation: Location? {
        guard let startLocationID else { return nil }
        return selectedLocations.first { $0.id == startLocationID }
    }

    var endLocation: Location? {
        guard let endLocationID else { return nil }
        return selectedLocations.first { $0.id == endLocationID }
    }

    func updateVisibleRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
    }

    func search() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = visibleRegion ?? cameraRegionFallback()

        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems.map { SearchResult(item: $0) }
            if response.mapItems.isEmpty {
                errorMessage = "No results for \"\(trimmed)\"."
            }
        } catch {
            errorMessage = "Search failed. Try again."
        }
    }

    func addLocation(from item: MKMapItem) {
        let coordinate = item.location.coordinate
        let name = item.name ?? "Unknown place"
        let subtitle = subtitle(for: item) ?? ""
        let location = Location(name: name, subtitle: subtitle, coordinate: coordinate)

        if !selectedLocations.contains(location) {
            selectedLocations.append(location)
            resetRoute()
            Task { await recomputeIfPossible() }
        }
    }

    func removeLocation(_ location: Location) {
        selectedLocations.removeAll { $0 == location }
        if startLocationID == location.id {
            startLocationID = nil
        }
        if endLocationID == location.id {
            endLocationID = nil
        }
        resetRoute()
        Task { await recomputeIfPossible() }
    }

    func clearRoute() {
        routeSegments = []
        orderedLocations = []
        totalDistance = nil
        totalTravelTime = nil
    }

    func setStartLocation(_ location: Location?) {
        startLocationID = location?.id
        if startLocationID == endLocationID {
            endLocationID = nil
        }
        Task { await recomputeIfPossible() }
    }

    func setEndLocation(_ location: Location?) {
        endLocationID = location?.id
        if startLocationID == endLocationID {
            startLocationID = nil
        }
        Task { await recomputeIfPossible() }
    }

    func updateTravelMode(_ mode: TravelMode) {
        travelMode = mode
        Task { await recomputeIfPossible() }
    }

    func computeShortestPath() async {
        await recomputeIfPossible()
    }

    func displayIndex(for location: Location) -> Int? {
        guard let index = displayLocations.firstIndex(of: location) else { return nil }
        return index + 1
    }

    func subtitle(for item: MKMapItem) -> String? {
        item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
    }

    private func resetRoute() {
        routeSegments = []
        orderedLocations = []
    }

    private func recomputeIfPossible() async {
        guard selectedLocations.count >= 2 else {
            clearRoute()
            return
        }
        if selectedLocations.count > 8 {
            errorMessage = "Please limit to 8 locations for now."
            return
        }

        isRouting = true
        errorMessage = nil
        defer { isRouting = false }

        let order = shortestOrder(for: selectedLocations)
        do {
            let result = try await buildRouteSegments(for: order, transportType: travelMode.transportType)
            routeSegments = result.segments
            orderedLocations = order
            totalDistance = Measurement(value: result.totalDistanceMeters, unit: UnitLength.meters)
            totalTravelTime = result.totalTravelTime
        } catch {
            errorMessage = "Route calculation failed."
        }
    }

    private func shortestOrder(for locations: [Location]) -> [Location] {
        guard locations.count > 2 else { return applyFixedEndpoints(to: locations) }

        let startLocation = startLocation
        let endLocation = endLocation

        var middle = locations
        if let startLocation {
            middle.removeAll { $0.id == startLocation.id }
        }
        if let endLocation {
            middle.removeAll { $0.id == endLocation.id }
        }

        var bestOrder: [Location] = []
        var bestDistance = Double.greatestFiniteMagnitude
        let permutations = permutations(of: middle)

        for permutation in permutations {
            var candidate: [Location] = []
            if let startLocation {
                candidate.append(startLocation)
            }
            candidate.append(contentsOf: permutation)
            if let endLocation {
                candidate.append(endLocation)
            }

            if candidate.count != locations.count {
                continue
            }

            let distance = totalDistance(for: candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestOrder = candidate
            }
        }

        return bestOrder.isEmpty ? applyFixedEndpoints(to: locations) : bestOrder
    }

    private func totalDistance(for locations: [Location]) -> Double {
        guard locations.count > 1 else { return 0 }

        var distance: Double = 0
        for index in 0..<(locations.count - 1) {
            let start = CLLocation(latitude: locations[index].coordinate.latitude, longitude: locations[index].coordinate.longitude)
            let end = CLLocation(latitude: locations[index + 1].coordinate.latitude, longitude: locations[index + 1].coordinate.longitude)
            distance += start.distance(from: end)
        }
        return distance
    }

    private func applyFixedEndpoints(to locations: [Location]) -> [Location] {
        var ordered = locations
        if let startLocation {
            ordered.removeAll { $0.id == startLocation.id }
            ordered.insert(startLocation, at: 0)
        }
        if let endLocation {
            ordered.removeAll { $0.id == endLocation.id }
            ordered.append(endLocation)
        }
        return ordered
    }

    private func permutations(of locations: [Location]) -> [[Location]] {
        guard locations.count > 1 else { return [locations] }

        var result: [[Location]] = []
        for index in locations.indices {
            var remaining = locations
            let current = remaining.remove(at: index)
            let subpermutations = permutations(of: remaining)
            for sub in subpermutations {
                result.append([current] + sub)
            }
        }
        return result
    }

    private func buildRouteSegments(for locations: [Location], transportType: MKDirectionsTransportType) async throws -> RouteResult {
        guard locations.count > 1 else {
            return RouteResult(segments: [], totalDistanceMeters: 0, totalTravelTime: 0)
        }

        var segments: [RouteSegment] = []
        var totalDistance: Double = 0
        var totalTravelTime: TimeInterval = 0

        for index in 0..<(locations.count - 1) {
            let sourceLocation = CLLocation(latitude: locations[index].coordinate.latitude, longitude: locations[index].coordinate.longitude)
            let destinationLocation = CLLocation(latitude: locations[index + 1].coordinate.latitude, longitude: locations[index + 1].coordinate.longitude)
            let source = MKMapItem(location: sourceLocation, address: nil)
            let destination = MKMapItem(location: destinationLocation, address: nil)

            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = transportType

            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            if let route = response.routes.first {
                segments.append(RouteSegment(polyline: route.polyline))
                totalDistance += route.distance
                totalTravelTime += route.expectedTravelTime
            }
        }

        return RouteResult(segments: segments, totalDistanceMeters: totalDistance, totalTravelTime: totalTravelTime)
    }

    private func cameraRegionFallback() -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        )
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let item: MKMapItem
}

struct IndexedLocation: Identifiable {
    let id: UUID
    let index: Int
    let location: Location

    init(index: Int, location: Location) {
        self.id = location.id
        self.index = index
        self.location = location
    }
}

struct Location: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Location, rhs: Location) -> Bool {
        lhs.name == rhs.name && lhs.subtitle == rhs.subtitle && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(subtitle)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

struct RouteSegment: Identifiable {
    let id = UUID()
    let polyline: MKPolyline
}

struct RouteResult {
    let segments: [RouteSegment]
    let totalDistanceMeters: Double
    let totalTravelTime: TimeInterval
}

enum TravelMode: String, CaseIterable, Identifiable {
    case automobile = "Driving"
    case walking = "Walking"
    case transit = "Transit"

    var id: String { rawValue }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .automobile:
            return .automobile
        case .walking:
            return .walking
        case .transit:
            return .transit
        }
    }
}
