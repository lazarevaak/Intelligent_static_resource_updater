//
//  VehiclePickerSheetView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import SwiftUI

struct VehiclePickerSheetView: View {
    let copy: AppCopy
    let vehicles: [TeslaVehicle]
    let onBind: (TeslaVehicle) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if vehicles.isEmpty {
                    Text(copy.noCarsBound)
                        .foregroundStyle(AppColors.color(AppColors.subtitleText))
                        .listRowBackground(AppColors.color(AppColors.appBackground))
                } else {
                    ForEach(vehicles) { vehicle in
                        Button {
                            onBind(vehicle)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vehicle.displayName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppColors.color(AppColors.primaryText))

                                Text("\(vehicle.currentRangeKm) km")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.color(AppColors.mapCardSubtitle))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppColors.color(AppColors.appBackground))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.color(AppColors.appBackground))
            .navigationTitle(copy.chooseVehicle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copy.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}
