import Vapor

func routes(_ app: Application, config: ServerConfig) throws {
    let artifactStorage: any ArtifactStorage
    switch config.artifactBackend {
    case .local:
        artifactStorage = LocalArtifactStorage(publicDirectory: app.directory.publicDirectory)
    case .s3:
        guard let s3Config = config.s3 else {
            throw Abort(.internalServerError, reason: "S3 backend selected but S3 config is missing")
        }
        let s3Storage = S3ArtifactStorage(config: s3Config)
        app.lifecycle.use(S3StorageLifecycle(storage: s3Storage))
        artifactStorage = s3Storage
    }
    let manifestController = ManifestController(
        publicDirectory: app.directory.publicDirectory,
        artifactStorage: artifactStorage,
        publishToken: config.publishToken
    )

    app.get { _ in "Серв запущен все работает" }
    let v1 = app.grouped("v1")
    v1.get("manifest", ":appId", "latest", use: manifestController.getLatestManifest)
    v1.get("manifest", ":appId", "version", ":version", use: manifestController.getManifest)
    v1.post("manifest", ":appId", "version", ":version", use: manifestController.updateManifest)
    v1.get("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", use: manifestController.getPatch)
    v1.get("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", "meta", use: manifestController.getPatchMeta)
}
