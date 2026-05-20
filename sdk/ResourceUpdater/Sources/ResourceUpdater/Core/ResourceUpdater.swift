import Foundation
import OSLog

public final class ResourceUpdater: @unchecked Sendable {
    private static let logger = Logger(subsystem: "ResourceUpdater", category: "updates")

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
                let currentVersion = storage.currentVersion()
                let updates = try await api.fetchUpdates(fromVersion: currentVersion)
                Self.logUpdateResponse(updates, currentVersion: currentVersion, mode: "check")

                guard updates.decision != "no-update" else {
                    completion(.success(false))
                    return
                }

                let decision = try await evaluateDecision(for: updates, mode: "check")

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
        Self.logUpdateResponse(updates, currentVersion: currentVersion, mode: "apply")

        switch updates.decision {
        case "no-update":
            return
        case "patch", "manifest-only":
            break
        default:
            throw ResourceUpdaterError.invalidPatchOperation("unknown decision \(updates.decision)")
        }

        let decision = try await evaluateDecision(for: updates, mode: "apply")
        guard decision.shouldUpdate else {
            Self.logger.info("ML rejected update apply latest=\(updates.latestVersion, privacy: .public) reason=\(updates.reason, privacy: .public)")
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

    private func evaluateDecision(for updates: UpdatesResponse, mode: String) async throws -> UpdateDecision {
        let context = try await contextBuilder.makeContext(
            from: updates,
            resourcePath: config.appId,
            storageDirectory: config.storageDirectory
        )
        let decision = await decisionEngine.evaluate(
            context: context,
            isCriticalUpdate: Self.isCriticalUpdate(reason: updates.reason)
        )
        Self.logDecision(decision, context: context, updates: updates, mode: mode)
        return decision
    }

    private static func logUpdateResponse(
        _ updates: UpdatesResponse,
        currentVersion: String?,
        mode: String
    ) {
        logger.info("Update response mode=\(mode, privacy: .public) decision=\(updates.decision, privacy: .public) from=\(currentVersion ?? "nil", privacy: .public) latest=\(updates.latestVersion, privacy: .public) reason=\(updates.reason, privacy: .public) manifestSize=\(updates.manifest.size, privacy: .public) patchSize=\(updates.patch?.size ?? 0, privacy: .public)")
    }

    private static func logDecision(
        _ decision: UpdateDecision,
        context: UpdateDecisionContext,
        updates: UpdatesResponse,
        mode: String
    ) {
        logger.info("ML update decision mode=\(mode, privacy: .public) shouldUpdate=\(decision.shouldUpdate, privacy: .public) probability=\(decision.probability ?? -1, privacy: .public) serverDecision=\(updates.decision, privacy: .public) latest=\(updates.latestVersion, privacy: .public) reason=\(updates.reason, privacy: .public) sizeMb=\(context.updateSizeMb, privacy: .public) online=\(context.isOnline, privacy: .public) network=\(context.networkType, privacy: .public) lowData=\(context.isLowDataMode, privacy: .public) battery=\(context.batteryLevel ?? -1, privacy: .public) charging=\(context.isCharging, privacy: .public) freeDiskMb=\(context.freeDiskSpaceMb, privacy: .public)")
    }
}
