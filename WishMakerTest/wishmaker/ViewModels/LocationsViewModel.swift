//
//  LocationsViewModel.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation
import CoreLocation
import MapKit
import Combine
import SwiftUI

@MainActor
final class LocationsViewModel: NSObject, ObservableObject {
    enum LocationFilter: Hashable {
        case all
        case favorites
        case type(LocationType)
    }

    @Published var locations: [AppLocation]
    @Published var selectedLocation: AppLocation?
    @Published var selectedFilter: LocationFilter = .all
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var activeRoute: MKRoute?
    @Published var activeRoutePolyline: MKPolyline?
    @Published var routePromptLocation: AppLocation?
    @Published private(set) var favoriteLocationIDs: Set<UUID> = []
    
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6176),
            span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22)
        )
    )
    private let locationManager = CLLocationManager()
    private let favoriteLocationsStore: FavoriteLocationsStoreProtocol
    private let locationRepository: any LocationRepositoryProtocol
    private let vehicleRepository: any VehicleRepositoryProtocol
    
    private let appState: AppState
    
    private var appStateCancellable: AnyCancellable?
    private var hasCenteredOnUser = false

    init(
        favoriteLocationsStore: FavoriteLocationsStoreProtocol,
        appState: AppState,
        locationRepository: any LocationRepositoryProtocol,
        vehicleRepository: any VehicleRepositoryProtocol
    ) {
        self.favoriteLocationsStore = favoriteLocationsStore
        self.appState = appState
        self.locationRepository = locationRepository
        self.vehicleRepository = vehicleRepository
        locations = locationRepository.locations
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        appStateCancellable = appState.stateDidChange.sink { [weak self] in
            self?.refreshResourceBackedState()
        }
        loadFavorites()
    }

    var vehicle: TeslaVehicle {
        appState.activeVehicle
            ?? vehicleRepository.primaryVehicle
    }

    var copy: AppCopy {
        appState.copy
    }

    var filteredLocations: [AppLocation] {
        switch selectedFilter {
        case .all:
            return locations
            
        case .favorites:
            return locations.filter { favoriteLocationIDs.contains($0.id) }
            
        case .type(let type):
            return locations.filter { $0.type == type }
            
        }
    }

    func requestLocationAccessIfNeeded() {
        authorizationStatus = locationManager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            
        case .denied, .restricted:
            break
            
        @unknown default:
            break
            
        }
    }

    func centerOnUser() {
        guard let userCoordinate else { return }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )
        )
    }

    func selectFilter(_ filter: LocationFilter) {
        selectedFilter = filter

        if let selectedLocation, !filteredLocations.contains(selectedLocation) {
            self.selectedLocation = nil
        }

        focusOnAvailableLocations()
    }

    func selectLocation(_ location: AppLocation) {
        selectedLocation = location
        activeRoute = nil
        activeRoutePolyline = nil
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )

        guard userCoordinate != nil else { return }
        routePromptLocation = location
    }

    func isFavorite(_ location: AppLocation) -> Bool {
        favoriteLocationIDs.contains(location.id)
    }

    func toggleFavorite(for location: AppLocation) {
        do {
            if favoriteLocationIDs.contains(location.id) {
                try favoriteLocationsStore.remove(id: location.id)
                favoriteLocationIDs.remove(location.id)
            } else {
                try favoriteLocationsStore.save(location)
                favoriteLocationIDs.insert(location.id)
            }
        } catch {
            AppLogger.persistence.error("Failed to update favorite location \(location.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        if case .favorites = selectedFilter, !favoriteLocationIDs.contains(location.id) {
            if selectedLocation?.id == location.id {
                selectedLocation = nil
            }
            focusOnAvailableLocations()
        }
    }

    var favoriteLocations: [AppLocation] {
        locations
            .filter { favoriteLocationIDs.contains($0.id) }
            .sorted { $0.title < $1.title }
    }

    func cancelRoutePrompt() {
        routePromptLocation = nil
    }

    func buildRoute(to location: AppLocation) {
        guard let userCoordinate else { return }

        routePromptLocation = nil

        Task {
            let automobileRoute = await calculateRoute(
                from: userCoordinate,
                to: location.coordinate,
                transportType: .automobile
            )
            let walkingRoute = await calculateRoute(
                from: userCoordinate,
                to: location.coordinate,
                transportType: .walking
            )

            if let route = automobileRoute ?? walkingRoute {
                await MainActor.run {
                    activeRoute = route
                    activeRoutePolyline = route.polyline
                    cameraPosition = .rect(route.polyline.boundingMapRect)
                }
                return
            }

            let fallbackPolyline = makeDirectPolyline(
                from: userCoordinate,
                to: location.coordinate
            )

            await MainActor.run {
                activeRoute = nil
                activeRoutePolyline = fallbackPolyline
                cameraPosition = .rect(fallbackPolyline.boundingMapRect)
            }
        }
    }

    private func focusOnAvailableLocations() {
        let visibleLocations = filteredLocations

        guard !visibleLocations.isEmpty else { return }

        if visibleLocations.count == 1, let location = visibleLocations.first {
            selectLocation(location)
            return
        }

        let latitudes = visibleLocations.map(\.latitude)
        let longitudes = visibleLocations.map(\.longitude)

        guard
            let minLatitude = latitudes.min(),
            let maxLatitude = latitudes.max(),
            let minLongitude = longitudes.min(),
            let maxLongitude = longitudes.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.8, 0.03),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.8, 0.03)
        )

        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func loadFavorites() {
        do {
            let favorites = try favoriteLocationsStore.fetchFavorites()
            favoriteLocationIDs = Set(favorites.map(\.id))
        } catch {
            AppLogger.persistence.error("Failed to load favorite locations: \(error.localizedDescription, privacy: .public)")
            favoriteLocationIDs = []
        }
    }

    private func refreshResourceBackedState() {
        let updatedLocations = locationRepository.locations
        locations = updatedLocations

        if let selectedLocation {
            self.selectedLocation = updatedLocations.first { $0.id == selectedLocation.id }
            if self.selectedLocation == nil {
                activeRoute = nil
                activeRoutePolyline = nil
            }
        }

        if let routePromptLocation {
            self.routePromptLocation = updatedLocations.first { $0.id == routePromptLocation.id }
        }

        loadFavorites()
        objectWillChange.send()
    }

    private func calculateRoute(
        from sourceCoordinate: CLLocationCoordinate2D,
        to destinationCoordinate: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: sourceCoordinate)
        )
        request.destination = MKMapItem(
            placemark: MKPlacemark(coordinate: destinationCoordinate)
        )
        request.transportType = transportType

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.first
        } catch {
            AppLogger.location.error("Failed to calculate route: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func makeDirectPolyline(
        from sourceCoordinate: CLLocationCoordinate2D,
        to destinationCoordinate: CLLocationCoordinate2D
    ) -> MKPolyline {
        var coordinates = [sourceCoordinate, destinationCoordinate]
        return MKPolyline(coordinates: &coordinates, count: coordinates.count)
    }
}

extension LocationsViewModel: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        userCoordinate = location.coordinate

        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            centerOnUser()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.location.error("Location manager failed: \(error.localizedDescription, privacy: .public)")
        manager.stopUpdatingLocation()
    }
}
