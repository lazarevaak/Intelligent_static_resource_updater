import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    var contentConfig = ContentConfiguration.global

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    contentConfig.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    contentConfig.use(decoder: decoder, for: .json)

    ContentConfiguration.global = contentConfig
    app.middleware.use(APIErrorMiddleware())
    app.middleware.use(RequestLoggingMiddleware())

    let config = ServerConfig.fromEnvironment()
    var metadata: Logger.Metadata = [
        "artifact_backend": .string(config.artifactBackend.rawValue),
        "publish_token_source": .string(Environment.get("CI_PUBLISH_TOKEN") == nil ? "default" : "env")
    ]
    if let s3 = config.s3 {
        metadata["s3_bucket"] = .string(s3.bucket)
        metadata["s3_region"] = .string(s3.region)
        metadata["s3_endpoint"] = .string(s3.endpoint ?? "aws-default")
        metadata["s3_path_style"] = .stringConvertible(s3.usePathStyle)
    }
    app.logger.info(
        "server_configured",
        metadata: metadata
    )

    // register routes
    try routes(app, config: config)
}
