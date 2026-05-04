import Foundation

public final class ResourceUpdater: @unchecked Sendable {
    private let api: UpdateAPI
    private let storage: LocalResourceStore
    private let config: ResourceUpdaterConfig

    private let contextBuilder: UpdateContextBuilder
    private let decisionEngine: UpdateDecisionEngine

    public init(
        config: ResourceUpdaterConfig,
        session: URLSession = .shared,
        contextBuilder: UpdateContextBuilder? = nil,
        decisionEngine: UpdateDecisionEngine? = nil
    ) {
        self.config = config
        self.api = UpdateAPI(config: config, session: session)
        self.storage = LocalResourceStore(rootDirectory: config.storageDirectory)

        let batteryService = BatteryService()
        let reachabilityService = ReachabilityService()
        let usageService = ResourceUsageService()

        self.contextBuilder = contextBuilder ?? UpdateContextBuilder(
            batteryService: batteryService,
            reachabilityService: reachabilityService,
            resourceUsageService: usageService
        )
        self.decisionEngine = decisionEngine ?? MLUpdateDecisionEngine.shared
    }

    public func checkForUpdates(
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    ) {
        Task {
            do {
                let updates = try await api.fetchUpdates(fromVersion: storage.currentVersion())

                guard updates.decision != "no-update" else {
                    completion(.success(false))
                    return
                }

                let context = try await contextBuilder.makeContext(
                    from: updates,
                    resourcePath: config.appId,
                    storageDirectory: config.storageDirectory
                )

                let decision = await decisionEngine.evaluate(
                    context: context,
                    isCriticalUpdate: Self.isCriticalUpdate(reason: updates.reason)
                )

                completion(.success(decision.shouldUpdate))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func applyUpdates(
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                try await applyUpdates()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func applyUpdates() async throws {
        let currentVersion = storage.currentVersion()
        let updates = try await api.fetchUpdates(fromVersion: currentVersion)

        switch updates.decision {
        case "no-update":
            return
        case "patch", "manifest-only":
            break
        default:
            throw ResourceUpdaterError.invalidPatchOperation("unknown decision \(updates.decision)")
        }

        let context = try await contextBuilder.makeContext(
            from: updates,
            resourcePath: config.appId,
            storageDirectory: config.storageDirectory
        )

        let decision = await decisionEngine.evaluate(
            context: context,
            isCriticalUpdate: Self.isCriticalUpdate(reason: updates.reason)
        )

        guard decision.shouldUpdate else {
            // Decision engine rejected applying the update in the current conditions.
            return
        }

        switch updates.decision {
        case "patch":
            let manifest = try await api.fetchManifest(descriptor: updates.manifest)
            guard let patchDescriptor = updates.patch else {
                throw ResourceUpdaterError.invalidPatchOperation("patch descriptor missing")
            }
            let patch = try await api.fetchPatch(descriptor: patchDescriptor)
            try storage.applyPatch(patch, targetManifest: manifest)
        case "manifest-only":
            let manifest = try await api.fetchManifest(descriptor: updates.manifest)
            try await storage.applyManifest(manifest) { hash in
                try await self.api.fetchResource(hash: hash)
            }
        default:
            return
        }
    }

    private static func isCriticalUpdate(reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("critical") || lower.contains("security")
    }
}
