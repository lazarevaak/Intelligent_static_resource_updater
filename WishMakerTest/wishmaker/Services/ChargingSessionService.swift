//
//  ChargingSessionService.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import Combine
import Foundation

@MainActor
final class ChargingSessionService {
    @Published private(set) var charging: Charging {
        didSet {
            persist()
        }
    }

    @Published private(set) var limitReachedAlertIsPresented = false

    private let chargingRepository: any ChargingRepositoryProtocol
    private let locationRepository: any LocationRepositoryProtocol
    private var chargingTask: Task<Void, Never>?

    init(
        chargingRepository: any ChargingRepositoryProtocol,
        locationRepository: any LocationRepositoryProtocol,
        activeVehicle: TeslaVehicle?
    ) {
        self.chargingRepository = chargingRepository
        self.locationRepository = locationRepository
        charging = chargingRepository.loadCharging() ?? Charging()

        refreshSelectedChargingStation()
        applyInitialVehicleBaselineIfNeeded(activeVehicle: activeVehicle)
        refreshAfterForeground()

        if charging.status == .charging {
            startChargingTask()
        }
    }

    deinit {
        chargingTask?.cancel()
    }

    func selectChargingStation(_ station: AppLocation) {
        guard station.superchargerDetails != nil else {
            AppLogger.charging.warning("Ignored non-supercharger station selection: \(station.title, privacy: .public)")
            return
        }
        charging.selectedStation = station
    }

    func setChargeLimitPercent(_ percent: Int) {
        charging.chargeLimitPercent = max(50, min(100, percent))
    }

    func setLimitReachedAlertPresented(_ isPresented: Bool) {
        limitReachedAlertIsPresented = isPresented
    }

    func startCharging() {
        guard charging.selectedStation?.superchargerDetails != nil else {
            AppLogger.charging.warning("Start charging ignored because no supercharger is selected")
            return
        }
        guard charging.status != .charging else { return }

        limitReachedAlertIsPresented = false
        charging.status = .charging
        charging.lastBatteryUpdate = Date()
        startChargingTask()
    }

    func stopCharging() {
        chargingTask?.cancel()
        chargingTask = nil
        if charging.status == .charging {
            charging.status = .stopped
        }
    }

    func resetForVehicle(_ vehicle: TeslaVehicle?) {
        stopCharging()
        limitReachedAlertIsPresented = false
        charging.reset(
            batteryLevel: vehicle?.batteryLevel ?? 0.5,
            chargeLimitPercent: vehicle?.chargeLimitPercent ?? 80
        )
    }

    func refreshAfterForeground() {
        applyElapsedTimeIfNeeded(now: Date())

        if charging.status == .charging, chargingTask == nil {
            startChargingTask()
        }
    }

    func refreshResources() {
        refreshSelectedChargingStation()
    }

    private func applyInitialVehicleBaselineIfNeeded(activeVehicle: TeslaVehicle?) {
        guard charging.selectedStation == nil, charging.addedEnergyKwh == 0, charging.cost == 0 else {
            return
        }

        charging.reset(
            batteryLevel: activeVehicle?.batteryLevel ?? 0.5,
            chargeLimitPercent: activeVehicle?.chargeLimitPercent ?? 80
        )
    }

    private func tickCharging() {
        guard charging.status == .charging else { return }
        advanceCharging(to: Date())
    }

    private func startChargingTask() {
        chargingTask?.cancel()
        chargingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tickCharging()
            }
        }
    }

    private func advanceCharging(to now: Date) {
        guard charging.status == .charging else { return }
        guard
            let stationDetails = charging.selectedStation?.superchargerDetails,
            stationDetails.powerKw > 0
        else {
            AppLogger.charging.warning("Charging stopped because selected station has no valid power")
            charging.lastBatteryUpdate = now
            stopCharging()
            return
        }

        let seconds = max(0, now.timeIntervalSince(charging.lastBatteryUpdate))
        guard seconds > 0 else { return }

        let capacityKwh = 75.0
        let energyDelta = stationDetails.powerKw * seconds / 3600.0
        charging.addedEnergyKwh += energyDelta
        charging.cost += energyDelta * stationDetails.pricePerKwh

        let levelDelta = energyDelta / capacityKwh
        charging.batteryLevel = min(1.0, charging.batteryLevel + levelDelta)
        charging.lastBatteryUpdate = now

        let targetLevel = Double(charging.chargeLimitPercent) / 100.0
        if charging.batteryLevel >= targetLevel {
            charging.batteryLevel = targetLevel
            limitReachedAlertIsPresented = true
            stopCharging()
        }
    }

    private func refreshSelectedChargingStation() {
        guard let selectedStation = charging.selectedStation else { return }

        if let currentStation = locationRepository.locations.first(where: { $0.id == selectedStation.id }) {
            charging.selectedStation = currentStation
        }

        if charging.selectedStation?.superchargerDetails == nil {
            AppLogger.charging.warning("Stored charging station is no longer a supercharger: \(selectedStation.title, privacy: .public)")
            charging.selectedStation = nil
            if charging.status == .charging {
                charging.status = .stopped
            }
        }
    }

    private func applyElapsedTimeIfNeeded(now: Date) {
        if charging.status == .charging {
            advanceCharging(to: now)
            return
        }

        applyDischargeIfNeeded(now: now)
    }

    private func applyDischargeIfNeeded(now: Date) {
        let seconds = max(0, now.timeIntervalSince(charging.lastBatteryUpdate))
        guard seconds > 60 else { return }

        let dischargePerDay = 0.10
        let dischargePerSecond = dischargePerDay / (24 * 60 * 60)
        let delta = dischargePerSecond * seconds

        charging.batteryLevel = max(0, charging.batteryLevel - delta)
        charging.lastBatteryUpdate = now
    }

    private func persist() {
        chargingRepository.saveCharging(charging)
    }
}
