//
//  UpdateAPI.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 26.01.2026.
//

import Foundation

public final class UpdateAPI {
    public init() {}
    
    func fetchLatestManifest(
        completion: @escaping (Result<Manifest, Error>) -> Void
    ) {
        // Заглушка
        let dummyManifest = Manifest(
            version: "1.0.0",
            generatedAt: Date(),
            resources: []
        )
        completion(.success(dummyManifest))
    }
}
