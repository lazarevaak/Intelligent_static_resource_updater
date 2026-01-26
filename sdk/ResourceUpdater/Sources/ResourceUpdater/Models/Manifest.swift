//
//  Manifest.swift
//  ResourceUpdater
//
//  Created by MacBoock on 26.01.2026.
//

import Foundation

public struct Manifest: Codable {
    public let version: String
    public let generatedAt: Date
    public let resources: [ResourceEntry]
}
