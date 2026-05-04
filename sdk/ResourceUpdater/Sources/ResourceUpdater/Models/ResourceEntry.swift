//
//  ResourceEntry.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct ResourceEntry: Codable {
    public let path: String
    public let hash: String
    public let size: Int
}
