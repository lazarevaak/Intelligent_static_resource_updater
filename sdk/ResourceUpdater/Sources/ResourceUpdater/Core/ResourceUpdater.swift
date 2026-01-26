import Foundation

public final class ResourceUpdater {
    private let api: UpdateAPI
    private let storage:  LocalResourceStore
    
    public init(
        api: UpdateAPI = UpdateAPI(),
        storage: LocalResourceStore = LocalResourceStore()
    ) {
        self.api = api
        self.storage = storage
    }
    
    public func checkForUpdates(
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        api.fetchLatestManifest { result in
            switch result {
            case .success(let manifest):
                let hasUpdates = self.storage.isUpdateNeeded(manifest)
                completion(.success(hasUpdates))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    public func applyUpdates(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // TODO: download patches, validate, apply
        completion(.success(()))
    }
}
