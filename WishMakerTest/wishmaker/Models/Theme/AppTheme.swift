//
//  AppTheme.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

struct AppTheme: Codable, Hashable {
    var version: Int = 1
    var colors: [String: String]

    static let `default` = AppTheme(colors: [
        // Base palette (override via resources/theme/theme.json)
        "appBackground": "#000000",
        "primaryText": "#FFFFFF",
        "accent": "#73E6FF",
        "gradientStart": "#0D0F17",
        "gradientMiddle": "#141418",
        "gradientEnd": "#08080D"
    ])
}
