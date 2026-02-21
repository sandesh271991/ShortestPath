//
//  ContentView.swift
//  ShortestPath
//
//  Created by Sandesh on 21/02/26.
//

import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RouteViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.99, blue: 1.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    mapSection

                    ScrollView {
                        VStack(spacing: 16) {
                            searchPanel
                            resultsPanel
                            selectionPanel
                            routePanel
                            orderedList
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Shortest Path")
        }
    }

    private var mapSection: some View {
        Map(position: $viewModel.cameraPosition, bounds: nil, interactionModes: .all, scope: nil) {
            ForEach(viewModel.indexedLocations) { item in
                Marker("\(item.index + 1). \(item.location.name)", coordinate: item.location.coordinate)
            }

            ForEach(viewModel.routeSegments) { segment in
                MapPolyline(segment.polyline)
                    .stroke(.blue, lineWidth: 6)
            }
        }
        .frame(minHeight: 260)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route Planner")
                    .font(.headline)
                Text("\(viewModel.selectedLocations.count) stops selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding([.top, .leading], 12)
        }
        .onMapCameraChange { context in
            viewModel.updateVisibleRegion(context.region)
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red)
            }
        }
    }

    private var searchPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Add locations")
                    .font(.headline)
                Text("Search and add at least two places to build a route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Search places", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { Task { await viewModel.search() } }

                    Button {
                        Task { await viewModel.search() }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
                }
            }
        }
    }

    private var resultsPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Search results")
                        .font(.headline)
                    Spacer()
                    if viewModel.isSearching {
                        ProgressView()
                    }
                }

                if viewModel.searchResults.isEmpty {
                    Text("No results yet. Try a new search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List(viewModel.searchResults) { result in
                        Button {
                            viewModel.addLocation(from: result.item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.item.name ?? "Unknown place")
                                    .font(.subheadline)
                                if let subtitle = viewModel.subtitle(for: result.item) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .listStyle(.plain)
                }
            }
        }
    }

    private var selectionPanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected locations")
                    .font(.headline)

                if viewModel.selectedLocations.isEmpty {
                    Text("Pick at least two locations to calculate a path.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(viewModel.selectedLocations) { location in
                            HStack(spacing: 12) {
                                if let index = viewModel.displayIndex(for: location) {
                                    NumberBadge(number: index)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                    if !location.subtitle.isEmpty {
                                        Text(location.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 8) {
                                        Button(viewModel.startLocation?.id == location.id ? "Start ✓" : "Start") {
                                            viewModel.setStartLocation(location)
                                        }
                                        .buttonStyle(.bordered)

                                        Button(viewModel.endLocation?.id == location.id ? "End ✓" : "End") {
                                            viewModel.setEndLocation(location)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeLocation(location)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .listStyle(.plain)
                }
            }
        }
    }

    private var routePanel: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Route")
                    .font(.headline)

                Picker("Travel mode", selection: $viewModel.travelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.travelMode) { _, newValue in
                    viewModel.updateTravelMode(newValue)
                }

                HStack {
                    Button {
                        Task { await viewModel.computeShortestPath() }
                    } label: {
                        Label("Compute shortest path", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedLocations.count < 2 || viewModel.isRouting)

                    Button("Clear route") {
                        viewModel.clearRoute()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.routeSegments.isEmpty)
                }

                if let distance = viewModel.totalDistance {
                    Text("Distance: \(formattedDistance(distance))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let time = viewModel.totalTravelTime {
                    Text("Estimated time: \(formattedTravelTime(time))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var orderedList: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Route order")
                    .font(.headline)

                if viewModel.indexedLocations.isEmpty {
                    Text("No route yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    List(viewModel.indexedLocations) { item in
                        HStack(spacing: 12) {
                            NumberBadge(number: item.index + 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.location.name)
                                if !item.location.subtitle.isEmpty {
                                    Text(item.location.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .listStyle(.plain)
                }
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private func formattedDistance(_ distance: Measurement<UnitLength>) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: distance)
    }

    private func formattedTravelTime(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: time) ?? "--"
    }
}

struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.blue))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
    }
}

#Preview {
    ContentView()
}
