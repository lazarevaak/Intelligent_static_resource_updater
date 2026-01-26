//
//  LocalResourceStore.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 26.01.2026.
//

import Foundation

public final class LocalResourceStore {
    private var currentVersion: String?
    
    public init() {}
    
    func isUpdateNeeded(_ manifest: Manifest) -> Bool {
        return manifest.version != currentVersion
    }

    func save(manifest: Manifest) {
        currentVersion = manifest.version
    }
}
