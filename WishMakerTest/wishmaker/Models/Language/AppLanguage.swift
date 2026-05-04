//
//  AppLanguage.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    
    case system
    
    case english
    
    case russian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
            
        case .english:
            return "English"
            
        case .russian:
            return "Русский"
            
        }
    }

    var localizedName: String {
        switch self {
        case .system:
            return "System"
            
        case .english:
            return "English"
            
        case .russian:
            return "Русский"
            
        }
    }

    var resolved: AppLanguage {
        switch self {
        case .system:
            return .system
            
        case .english, .russian:
            return self
            
        }
    }
}
