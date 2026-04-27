import Foundation

public final class ResourceUpdater: @unchecked Sendable {
    private let api: UpdateAPI
    private let storage: LocalResourceStore

    public init(
        config: ResourceUpdaterConfig,
        session: URLSession = .shared
    ) {
        self.api = UpdateAPI(config: config, session: session)
        self.storage = LocalResourceStore(rootDirectory: config.storageDirectory)
    }

    public func checkForUpdates(
        completion: @escaping @Sendable (Result<Bool, Error>) -> Void
    ) {
        Task {
            do {
                let updates = try await api.fetchUpdates(fromVersion: storage.currentVersion())
                completion(.success(updates.decision != "no-update"))
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
            throw ResourceUpdaterError.invalidPatchOperation("unknown decision \(updates.decision)")
        }
    }
}
