import Vapor

func makeArtifactStorage(app: Application, config: ServerConfig) throws -> any ArtifactStorage {
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
    return artifactStorage
}

func routes(
    _ app: Application,
    config: ServerConfig,
    includeMetricsRoutes: Bool,
    artifactStorage: any ArtifactStorage
) throws {
    let manifestController = ManifestController(
        publicDirectory: app.directory.publicDirectory,
        artifactStorage: artifactStorage,
        publishToken: config.publishToken,
        signatureService: try SignatureService(config: config.signing)
    )

    app.get { _ in "Серв запущен все работает" }
    if includeMetricsRoutes {
        try registerMetricsRoutes(app, config: config)
    }

    let v1 = app.grouped("v1")
    v1.get("keys", use: manifestController.getSigningKeys)
    v1.get("keys", ":keyId", use: manifestController.getSigningKey)
    v1.get("manifest", ":appId", "latest", use: manifestController.getLatestManifest)
    v1.get("manifest", ":appId", "version", ":version", use: manifestController.getManifest)
    v1.get("updates", ":appId", use: manifestController.getUpdates)
    v1.post("manifest", ":appId", "version", ":version", use: manifestController.updateManifest)
    v1.post("resource", ":appId", "upload", use: manifestController.uploadResource)
    v1.get("resource", ":appId", "hash", ":hash", use: manifestController.getResource)
    v1.post("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", "upload", use: manifestController.uploadPatch)
    v1.get("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", use: manifestController.getPatch)
    v1.get("patch", ":appId", "from", ":fromVersion", "to", ":toVersion", "meta", use: manifestController.getPatchMeta)
}

func registerMetricsRoutes(_ app: Application, config: ServerConfig) throws {
    app.get("metrics") { req async throws -> Response in
        try authorizeMetricsAccess(req: req, config: config)
        let body = await req.application.apiMetricsCollector.prometheusText()
        let response = Response(status: .ok, body: .init(string: body))
        response.headers.replaceOrAdd(name: .contentType, value: "text/plain; version=0.0.4; charset=utf-8")
        return response
    }
    let v1 = app.grouped("v1")
    v1.get("metrics") { req async throws -> APIMetricsSnapshot in
        try authorizeMetricsAccess(req: req, config: config)
        return await req.application.apiMetricsCollector.snapshot()
    }
}

private func authorizeMetricsAccess(req: Request, config: ServerConfig) throws {
    guard config.metrics.isEnabled else {
        throw Abort(.notFound)
    }

    if let expectedToken = config.metrics.token {
        let bearerToken = req.headers.bearerAuthorization?.token
        let headerToken = req.headers.first(name: "X-Metrics-Token")
        let providedToken = bearerToken ?? headerToken
        guard providedToken == expectedToken else {
            throw Abort(.unauthorized, reason: "invalid metrics token")
        }
    }

    if !config.metrics.allowlist.isEmpty {
        guard let clientIP = clientIPAddress(req: req),
              config.metrics.allowlist.contains(clientIP) else {
            throw Abort(.forbidden, reason: "metrics access denied for client IP")
        }
    }
}
