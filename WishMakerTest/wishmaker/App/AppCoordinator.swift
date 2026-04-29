//
//  AppCoordinator.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import SwiftUI
import UIKit

@MainActor
final class AppCoordinator {
    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies? = nil) {
        let dependencies = dependencies ?? .live()
        self.dependencies = dependencies
        appState = AppState(
            userRepository: dependencies.userRepository,
            chargingRepository: dependencies.chargingRepository,
            vehicleRepository: dependencies.vehicleRepository,
            locationRepository: dependencies.locationRepository
        )
    }

    func start() -> UIViewController {
        RootTabBarController(
            viewControllers: [
                makeUIKitFlow(),
                makeSecondaryFlow(),
                makeSwiftUIFlow(),
                makeProfileFlow()
            ]
        )
    }

    func prepareForStart() {
        appState.bindFirstAvailableVehicle()
    }

    func refreshAfterForeground() {
        appState.refreshAfterForeground()
    }

    func refreshResources() {
        appState.refreshResources()
    }

    private func makeUIKitFlow() -> UIViewController {
        let viewModel = VehicleDashboardViewModel(appState: appState)
        let controller = VehicleDashboardViewController(viewModel: viewModel)
        return makeNavigationController(rootViewController: controller)
    }

    private func makeSecondaryFlow() -> UIViewController {
        let viewModel = ChargingDashboardViewModel(
            appState: appState,
            locationRepository: dependencies.locationRepository
        )
        let hostingController = UIHostingController(rootView: ChargingDashboardView(viewModel: viewModel))
        return makeNavigationController(rootViewController: hostingController)
    }

    private func makeSwiftUIFlow() -> UIViewController {
        let locationsViewModel = LocationsViewModel(
            favoriteLocationsStore: dependencies.favoriteLocationsStore,
            appState: appState,
            locationRepository: dependencies.locationRepository,
            vehicleRepository: dependencies.vehicleRepository
        )
        let hostingController = UIHostingController(
            rootView: LocationsMapView(viewModel: locationsViewModel)
        )
        return makeNavigationController(rootViewController: hostingController)
    }

    private func makeProfileFlow() -> UIViewController {
        let hostingController = UIHostingController(rootView: makeProfileView())
        return makeNavigationController(rootViewController: hostingController)
    }

    private func makeProfileView(dismissOnPullDown: Bool = false) -> ProfileDashboardView {
        let viewModel = ProfileDashboardViewModel(
            appState: appState,
            avatarOptionsRepository: dependencies.avatarOptionsRepository
        )
        return ProfileDashboardView(viewModel: viewModel, dismissOnPullDown: dismissOnPullDown)
    }

    private func makeNavigationController(rootViewController: UIViewController) -> UIViewController {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationController.setNavigationBarHidden(true, animated: false)
        return navigationController
    }
}
