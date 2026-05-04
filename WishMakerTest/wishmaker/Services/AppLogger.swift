//
//  AppLogger.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "wishmaker"

    static let resources = Logger(subsystem: subsystem, category: "resources")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let charging = Logger(subsystem: subsystem, category: "charging")
    static let location = Logger(subsystem: subsystem, category: "location")
}
