import Foundation
import Vapor

actor BackgroundCleanupWorker {
    private let storage: ManifestStorage
    private let config: ServerConfig.CleanupConfig
    private let logger: Logger

    init(storage: ManifestStorage, config: ServerConfig.CleanupConfig, logger: Logger) {
        self.storage = storage
        self.config = config
        self.logger = logger
    }

    func runOnce() async {
        do {
            let appIds = try await targetAppIds()
            for appId in appIds {
                let result = try await storage.cleanup(appId: appId, keepLast: config.keepLast)
                logger.info(
                    "background_cleanup_completed",
                    metadata: [
                        "app_id": .string(appId),
                        "keep_last": .stringConvertible(config.keepLast),
                        "removed_versions": .stringConvertible(result.removedVersions.count),
                        "removed_patch_artifacts": .stringConvertible(result.removedPatchArtifacts),
                        "removed_resource_binaries": .stringConvertible(result.removedResourceBinaries)
                    ]
                )
            }
        } catch {
            logger.error(
                "background_cleanup_failed",
                metadata: ["error": .string(String(describing: error))]
            )
        }
    }

    private func targetAppIds() async throws -> [String] {
        if let configured = config.appIds {
            return configured
        }
        return try await storage.listAppIds()
    }
}

final class BackgroundCleanupLifecycle: LifecycleHandler, @unchecked Sendable {
    private let worker: BackgroundCleanupWorker
    private let intervalSeconds: Int
    private var task: Task<Void, Never>?

    init(worker: BackgroundCleanupWorker, intervalSeconds: Int) {
        self.worker = worker
        self.intervalSeconds = intervalSeconds
    }

    func didBoot(_ application: Application) throws {
        task = Task {
            await worker.runOnce()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                } catch {
                    break
                }
                if Task.isCancelled {
                    break
                }
                await worker.runOnce()
            }
        }
    }

    func shutdown(_ application: Application) {
        task?.cancel()
        task = nil
    }
}
