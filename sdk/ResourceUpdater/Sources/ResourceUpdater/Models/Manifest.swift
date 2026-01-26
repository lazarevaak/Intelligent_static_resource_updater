//
//  Manifest.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 26.01.2026.
//

import Foundation

public struct Manifest: Codable {
    public let version: String
    public let generatedAt: Date
    public let resources: [ResourceEntry]
}
