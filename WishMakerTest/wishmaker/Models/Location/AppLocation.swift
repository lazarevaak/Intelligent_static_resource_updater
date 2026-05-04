//
//  AppLocation.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation
import MapKit

struct AppLocation: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let type: LocationType
    let latitude: Double
    let longitude: Double
    let address: String
    let workingHours: String?
    let distanceKm: Double?
    let supercharger: SuperchargerDetails?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var superchargerDetails: SuperchargerDetails? {
        guard type == .supercharger else { return nil }
        return supercharger ?? SuperchargerDetails()
    }
}

struct SuperchargerDetails: Codable, Hashable {
    var powerKw: Double = 72
    var pricePerKwh: Double = 0.35
}

enum LocationType: String, Codable, CaseIterable {
    
    case supercharger
    
    case service
    
    case parking
    
    case favorite

    var title: String {
        switch self {
        case .supercharger:
            return "Supercharger"
        case .service:
            return "Service"
        case .parking:
            return "Parking"
        case .favorite:
            return "Favorite"
        }
    }

    var iconName: String {
        switch self {
        case .supercharger:
            return "bolt.car.fill"
            
        case .service:
            return "wrench.and.screwdriver.fill"
            
        case .parking:
            return "parkingsign.circle.fill"
            
        case .favorite:
            return "star.fill"
            
        }
    }
}
