//
//  ResourceEntry.swift
//  ResourceUpdater
//
//  Created by MacBoock on 26.01.2026.
//

import Foundation

public struct ResourceEntry: Codable {
    public let path: String
    public let hash: String
    public let size: Int
}
