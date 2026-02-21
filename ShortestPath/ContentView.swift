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
            VStack(spacing: 0) {
                mapSection

                ScrollView {
                    VStack(spacing: 12) {
                        searchPanel
                        resultsPanel
                        selectionPanel
                        routePanel
                        orderedList
                    }
                    .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Add locations")
                .font(.headline)
            HStack {
                TextField("Search places", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.search() } }

                Button("Search") {
                    Task { await viewModel.search() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
            }
        }
        .padding(.horizontal)
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal)
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal)
    }

    private var routePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button("Compute shortest path") {
                    Task { await viewModel.computeShortestPath() }
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
        .padding(.horizontal)
    }

    private var orderedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Route order")
                .font(.headline)
                .padding(.horizontal)

            if viewModel.indexedLocations.isEmpty {
                Text("No route yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
        .padding(.bottom, 8)
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
