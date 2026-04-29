//
//  DeviceStorageService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public protocol DeviceStorageServiceProtocol: Sendable {
    func freeDiskSpaceMb(at directory: URL) throws -> Double
}

public struct DeviceStorageService: DeviceStorageServiceProtocol {
    public init() {}

    public func freeDiskSpaceMb(at directory: URL) throws -> Double {
        Double(try freeDiskSpaceBytes(at: directory)) / 1_048_576
    }

    public func freeDiskSpaceBytes(at directory: URL) throws -> Int64 {
        let values = try existingVolumeURL(for: directory).resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])

        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }

        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }

        throw ResourceUpdaterError.invalidResponse
    }

    private func existingVolumeURL(for directory: URL) -> URL {
        var url = directory
        let fileManager = FileManager.default

        while !fileManager.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                break
            }
            url = parent
        }

        return url
    }
}
