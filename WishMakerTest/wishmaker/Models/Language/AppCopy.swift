//
//  AppCopy.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

struct AppCopy {
    
    let language: AppLanguage

    func locationTypeTitle(_ type: LocationType) -> String {
        switch type {
        case .supercharger:
            return Localization.string("location_type_supercharger", language: language)
            
        case .service:
            return Localization.string("location_type_service", language: language)
            
        case .parking:
            return Localization.string("location_type_parking", language: language)
            
        case .favorite:
            return Localization.string("location_type_favorite", language: language)
            
        }
    }
}
