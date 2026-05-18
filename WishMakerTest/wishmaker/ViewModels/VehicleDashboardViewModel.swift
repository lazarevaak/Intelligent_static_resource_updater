//
//  VehicleDashboardViewModel.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation
import Combine

@MainActor
final class VehicleDashboardViewModel {
    private let appState: AppState
    private var cancellable: AnyCancellable?

    private(set) var vehicle: TeslaVehicle?
    private(set) var copy: AppCopy

    var onUpdate: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        self.copy = appState.copy
        self.vehicle = appState.activeVehicle

        cancellable = appState.stateDidChange.sink { [weak self] in
            self?.refresh()
        }
    }

    func load() {
        onUpdate?()
    }

    var displayTitle: String {
        vehicle?.brandTitle ?? "Car"
    }

    var modelNameText: String {
        vehicle?.displayName ?? "Demo Car"
    }

    var quickActions: [VehicleQuickAction] {
        vehicle?.dashboardQuickActions ?? []
    }

    var infoRows: [VehicleStatusRow] {
        vehicle?.dashboardRows ?? []
    }

    private func refresh() {
        vehicle = appState.activeVehicle
        copy = appState.copy
        onUpdate?()
    }
}
