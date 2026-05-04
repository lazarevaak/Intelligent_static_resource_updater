//
//  LocationsCatalog.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

enum LocationsCatalog {
    static var locations: [AppLocation] {
        loadLocations()
    }

    private static func loadLocations() -> [AppLocation] {
        AppResourceProvider.shared.decode(
            [AppLocation].self,
            from: AppResourcePath.locations
        ) ?? []
    }
}
