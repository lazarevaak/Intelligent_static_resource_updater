//
//  LocationsMapView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import MapKit
import SwiftUI

struct LocationsMapView: View {
    @StateObject private var viewModel: LocationsViewModel
    @State private var isFavoritesSheetPresented = false
    @State private var hasRequestedLocationAccess = false

    init(viewModel: LocationsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                mapView

                VStack(spacing: 0) {
                    topOverlay(topInset: proxy.safeAreaInsets.top)
                    Spacer()
                }
                .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .background(AppColors.color(AppColors.appBackground))
        .ignoresSafeArea()
        .onAppear {
            requestLocationAccessAfterInitialRender()
        }
        .alert(
            viewModel.copy.buildRouteTitle,
            isPresented: routePromptIsPresented,
            presenting: viewModel.routePromptLocation
        ) { location in
            Button(viewModel.copy.notNow, role: .cancel) {
                viewModel.cancelRoutePrompt()
            }
            Button(viewModel.copy.build) {
                viewModel.buildRoute(to: location)
            }
        } message: { location in
            Text(viewModel.copy.routePrompt(location: location.title))
        }
        .sheet(isPresented: $isFavoritesSheetPresented) {
            FavoriteLocationsSheetView(
                copy: viewModel.copy,
                locations: viewModel.favoriteLocations,
                onSelect: { location in
                    viewModel.selectLocation(location)
                },
                onToggleFavorite: { location in
                    viewModel.toggleFavorite(for: location)
                }
            )
        }
    }

    private func requestLocationAccessAfterInitialRender() {
        guard !hasRequestedLocationAccess else { return }
        hasRequestedLocationAccess = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            viewModel.requestLocationAccessIfNeeded()
        }
    }

    private func topOverlay(topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer()

            VStack(spacing: 10) {
                favoritesButton

                if viewModel.userCoordinate != nil {
                    centerOnUserButton
                }
            }
        }
        .padding(.top, max(topInset, 16) + 22)
    }

    private var bottomOverlay: some View {
        VStack(spacing: 14) {
            filterView
            locationsList
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, AppTabBarMetrics.contentBottomInset)
    }

    private var mapView: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()

            if let routePolyline = viewModel.activeRoutePolyline {
                MapPolyline(routePolyline)
                    .stroke(AppColors.color(AppColors.accent), lineWidth: 6)
            }

            if let userCoordinate = viewModel.userCoordinate {
                Annotation(viewModel.vehicle.locationPinTitle, coordinate: userCoordinate, anchor: .bottom) {
                    TeslaLocationPinView(title: viewModel.vehicle.locationPinTitle)
                }
            }

            ForEach(viewModel.filteredLocations) { location in
                Annotation(location.title, coordinate: location.coordinate) {
                    Button {
                        viewModel.selectLocation(location)
                    } label: {
                        LocationPinView(
                            type: location.type,
                            isSelected: viewModel.selectedLocation?.id == location.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var favoritesButton: some View {
        Button {
            isFavoritesSheetPresented = true
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(AppColors.color(AppColors.mapOverlayBackground))
                        .overlay(
                            Circle()
                                .stroke(AppColors.color(AppColors.mapOverlayBorder), lineWidth: 1)
                        )
                )
                .shadow(color: AppColors.color(AppColors.mapCardShadow), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var centerOnUserButton: some View {
        Button {
            viewModel.centerOnUser()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(AppColors.color(AppColors.mapOverlayBackground))
                        .overlay(
                            Circle()
                                .stroke(AppColors.color(AppColors.mapOverlayBorder), lineWidth: 1)
                        )
                )
                .shadow(color: AppColors.color(AppColors.mapCardShadow), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var filterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterButton(title: viewModel.copy.all, filter: .all)
                filterButton(title: viewModel.copy.favorites, filter: .favorites)

                ForEach(LocationType.allCases, id: \.self) { type in
                    filterButton(title: viewModel.copy.locationTypeTitle(type), filter: .type(type))
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func filterButton(title: String, filter: LocationsViewModel.LocationFilter) -> some View {
        let isSelected = viewModel.selectedFilter == filter

        return Button {
            viewModel.selectFilter(filter)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    AppColors.color(isSelected ? AppColors.primaryText : AppColors.mapFilterText)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppColors.color(isSelected ? AppColors.mapFilterSelected : AppColors.mapFilterBackground))
                        .overlay(
                            Capsule()
                                .stroke(AppColors.color(AppColors.mapFilterBorder), lineWidth: isSelected ? 0 : 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var locationsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.filteredLocations) { location in
                    LocationCardView(
                        location: location,
                        isSelected: viewModel.selectedLocation?.id == location.id,
                        isFavorite: viewModel.isFavorite(location),
                        onFavoriteTap: {
                            viewModel.toggleFavorite(for: location)
                        }
                    ) {
                        viewModel.selectLocation(location)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var routePromptIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.routePromptLocation != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    viewModel.cancelRoutePrompt()
                }
            }
        )
    }
}

#Preview {
    LocationsMapView(
        viewModel: LocationsViewModel(
            favoriteLocationsStore: FavoriteLocationsStore(
                context: PersistenceController(inMemory: true).container.viewContext
            ),
            appState: AppState(),
            locationRepository: StaticLocationRepository(),
            vehicleRepository: StaticVehicleRepository()
        )
    )
}
