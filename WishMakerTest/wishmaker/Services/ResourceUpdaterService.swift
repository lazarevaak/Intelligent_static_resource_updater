//
//  ResourceUpdaterService.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation
import ResourceUpdater

@MainActor
final class ResourceUpdaterService {
    static let shared = ResourceUpdaterService()

    let storageDirectory: URL
    private let updater: ResourceUpdater
    private var isApplyingUpdates = false

    private init() {
        storageDirectory = AppResourceStorage.rootDirectory

        updater = ResourceUpdater(
            config: ResourceUpdaterConfig(
                baseURL: URL(string: "http://81.26.184.66:8081/")!,
                appId: "wishmaker",
                sdkVersion: "1.0.0",
                storageDirectory: storageDirectory
            )
        )
    }

    func applyUpdates() async -> Bool {
        guard !isApplyingUpdates else {
            AppLogger.resources.info("Resource updater skipped because another update is still running")
            return false
        }

        isApplyingUpdates = true
        defer { isApplyingUpdates = false }

        do {
            try await updater.applyUpdates()
            return true
        } catch {
            let nsError = error as NSError
            AppLogger.resources.error("Resource updater failed: \(String(describing: error), privacy: .public). \(error.localizedDescription, privacy: .public). Domain: \(nsError.domain, privacy: .public), code: \(nsError.code)")
            return false
        }
    }
}
