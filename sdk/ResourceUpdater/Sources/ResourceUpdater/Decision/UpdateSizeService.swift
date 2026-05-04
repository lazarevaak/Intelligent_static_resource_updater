//
//  UpdateSizeService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
public struct UpdateSizeFeature: Equatable, Sendable {
    public let updateSizeMb: Double

    public init(updateSizeMb: Double) {
        self.updateSizeMb = updateSizeMb
    }
}

public struct UpdateSizeService: Sendable {
    public init() {}

    public func updateSizeBytes(from response: UpdatesResponse) -> Int {
        response.patch?.size ?? response.manifest.size
    }

    public func updateSizeMb(from response: UpdatesResponse) -> Double {
        Double(updateSizeBytes(from: response)) / 1_048_576
    }

    public func makeFeature(from response: UpdatesResponse) -> UpdateSizeFeature {
        UpdateSizeFeature(updateSizeMb: updateSizeMb(from: response))
    }
}
