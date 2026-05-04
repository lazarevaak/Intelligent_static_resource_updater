//
//  ChargingStationPickerView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import MapKit
import SwiftUI

struct ChargingStationPickerView: View {
    let copy: AppCopy
    let stations: [AppLocation]
    let onPick: (AppLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStation: AppLocation?
    @State private var cameraPosition: MapCameraPosition

    init(copy: AppCopy, stations: [AppLocation], onPick: @escaping (AppLocation) -> Void) {
        self.copy = copy
        self.stations = stations
        self.onPick = onPick

        let center = stations.first?.coordinate ?? CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6176)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(stations) { station in
                        Annotation(station.title, coordinate: station.coordinate) {
                            Button {
                                selectedStation = station
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: station.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                ))
                            } label: {
                                LocationPinView(
                                    type: station.type,
                                    isSelected: selectedStation?.id == station.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .ignoresSafeArea()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(stations) { station in
                            Button {
                                selectedStation = station
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: station.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                ))
                            } label: {
                                LocationCardView(
                                    location: station,
                                    isSelected: selectedStation?.id == station.id,
                                    isFavorite: false,
                                    onFavoriteTap: {},
                                    onTap: {}
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .background(
                    LinearGradient(
                        colors: [
                            AppColors.color(AppColors.appBackground).opacity(0.0),
                            AppColors.color(AppColors.appBackground).opacity(0.85),
                            AppColors.color(AppColors.appBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copy.close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copy.select) {
                        if let selectedStation {
                            onPick(selectedStation)
                            dismiss()
                        }
                    }
                    .disabled(selectedStation == nil)
                }
            }
        }
    }
}
