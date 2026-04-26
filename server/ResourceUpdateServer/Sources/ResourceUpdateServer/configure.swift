import Vapor

public func configure(_ app: Application) async throws {
    let config = try ServerConfig.fromEnvironment()
    let collector = APIMetricsCollector()
    try await configurePublicApplication(
        app,
        config: config,
        metricsCollector: collector,
        includeMetricsRoutes: config.metrics.listener == nil
    )
}

func configurePublicApplication(
    _ app: Application,
    config: ServerConfig,
    metricsCollector: APIMetricsCollector,
    includeMetricsRoutes: Bool
) async throws {
    configureContent(on: app)
    app.apiMetricsCollector = metricsCollector
    let artifactStorage = try makeArtifactStorage(app: app, config: config)
    let rateLimitStore = try makeRateLimitStore(
        config: config.rateLimit,
        publicDirectory: app.directory.publicDirectory,
        eventLoop: app.eventLoopGroup.next(),
        logger: app.logger
    )

    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(APIErrorMiddleware())
    app.middleware.use(RateLimitMiddleware(config: config.rateLimit, store: rateLimitStore))
    app.middleware.use(RequestLoggingMiddleware(metrics: app.apiMetricsCollector))

    var metadata: Logger.Metadata = [
        "artifact_backend": .string(config.artifactBackend.rawValue),
        "publish_token_source": .string("env"),
        "signing_active_key_id": .string(config.signing.activeKeyId),
        "signing_keys_count": .stringConvertible(config.signing.keys.count),
        "rate_limit_backend": .string(config.rateLimit.backend.rawValue),
        "rate_limit_updates_per_minute": .stringConvertible(config.rateLimit.updatesPerMinute),
        "rate_limit_patch_per_minute": .stringConvertible(config.rateLimit.patchPerMinute),
        "metrics_routes_included": .stringConvertible(includeMetricsRoutes)
    ]
    if let sharedDirectory = config.rateLimit.sharedDirectory {
        metadata["rate_limit_shared_dir"] = .string(sharedDirectory)
    }
    if let listener = config.metrics.listener {
        metadata["metrics_bind_host"] = .string(listener.host)
        metadata["metrics_port"] = .stringConvertible(listener.port)
    }
    if let cleanup = config.cleanup {
        metadata["cleanup_interval_seconds"] = .stringConvertible(cleanup.intervalSeconds)
        metadata["cleanup_keep_last"] = .stringConvertible(cleanup.keepLast)
        metadata["cleanup_app_ids"] = .string(cleanup.appIds?.joined(separator: ",") ?? "*")
    }
    if let s3 = config.s3 {
        metadata["s3_bucket"] = .string(s3.bucket)
        metadata["s3_region"] = .string(s3.region)
        metadata["s3_endpoint"] = .string(s3.endpoint ?? "aws-default")
        metadata["s3_path_style"] = .stringConvertible(s3.usePathStyle)
    }
    app.logger.info("server_configured", metadata: metadata)

    if let cleanupConfig = config.cleanup {
        let storage = ManifestStorage(
            publicDirectory: app.directory.publicDirectory,
            artifactStorage: artifactStorage
        )
        let worker = BackgroundCleanupWorker(
            storage: storage,
            config: cleanupConfig,
            logger: app.logger
        )
        app.lifecycle.use(
            BackgroundCleanupLifecycle(
                worker: worker,
                intervalSeconds: cleanupConfig.intervalSeconds
            )
        )
    }

    try routes(
        app,
        config: config,
        includeMetricsRoutes: includeMetricsRoutes,
        artifactStorage: artifactStorage
    )
}

func configureMetricsApplication(
    _ app: Application,
    config: ServerConfig,
    metricsCollector: APIMetricsCollector
) async throws {
    configureContent(on: app)
    app.apiMetricsCollector = metricsCollector
    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(APIErrorMiddleware())
    app.middleware.use(RequestLoggingMiddleware(metrics: app.apiMetricsCollector))
    try registerMetricsRoutes(app, config: config)
}

private func configureContent(on app: Application) {
    var contentConfig = ContentConfiguration.global

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    contentConfig.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    contentConfig.use(decoder: decoder, for: .json)

    ContentConfiguration.global = contentConfig
}
