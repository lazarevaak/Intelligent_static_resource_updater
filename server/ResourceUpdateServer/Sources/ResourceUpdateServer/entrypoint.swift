import Vapor
import ArgumentParser
import Foundation
import Logging
import NIOCore
import NIOPosix

@main
enum Entrypoint {
    static func main() async throws {
        let cliSubcommands = Set(["publish-local", "dry-run", "validate", "cleanup"])
        if CommandLine.arguments.count >= 2, cliSubcommands.contains(CommandLine.arguments[1]) {
            do {
                var command = try ResourceUpdateCLI.parse(Array(CommandLine.arguments.dropFirst(1)))
                try command.run()
            } catch is CleanExit {
                return
            } catch {
                let message = "\(error.localizedDescription)\n"
                if let data = message.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
                throw error
            }
            return
        }

        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let config = try ServerConfig.fromEnvironment()
        let sharedMetricsCollector = APIMetricsCollector()
        let app = try await Application.make(env)
        configurePublicListener(app)
        var metricsApp: Application?
        if let listener = config.metrics.listener {
            let internalMetricsApp = try await Application.make(env)
            internalMetricsApp.http.server.configuration.hostname = listener.host
            internalMetricsApp.http.server.configuration.port = listener.port
            try await configureMetricsApplication(
                internalMetricsApp,
                config: config,
                metricsCollector: sharedMetricsCollector
            )
            internalMetricsApp.logger.info(
                "metrics_listener_configured",
                metadata: [
                    "host": .string(listener.host),
                    "port": .stringConvertible(listener.port)
                ]
            )
            metricsApp = internalMetricsApp
        }

        // This attempts to install NIO as the Swift Concurrency global executor.
        // You can enable it if you'd like to reduce the amount of context switching between NIO and Swift Concurrency.
        // Note: this has caused issues with some libraries that use `.wait()` and cleanly shutting down.
        // If enabled, you should be careful about calling async functions before this point as it can cause assertion failures.
        // let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        // app.logger.debug("Tried to install SwiftNIO's EventLoopGroup as Swift's global concurrency executor", metadata: ["success": .stringConvertible(executorTakeoverSuccess)])
        
        do {
            try await configurePublicApplication(
                app,
                config: config,
                metricsCollector: sharedMetricsCollector,
                includeMetricsRoutes: metricsApp == nil
            )

            if let metricsApp {
                async let publicServer: Void = app.execute()
                async let internalMetricsServer: Void = metricsApp.execute()
                _ = try await (publicServer, internalMetricsServer)
            } else {
                try await app.execute()
            }
        } catch {
            app.logger.report(error: error)
            if let metricsApp {
                metricsApp.logger.report(error: error)
            }
            try? await metricsApp?.asyncShutdown()
            try? await app.asyncShutdown()
            throw error
        }
        try await metricsApp?.asyncShutdown()
        try await app.asyncShutdown()
    }

    private static func configurePublicListener(_ app: Application) {
        let host = Environment.get("HOST")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty {
            app.http.server.configuration.hostname = host
        }

        let rawPort = Environment.get("PORT")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawPort, let port = Int(rawPort), port > 0 {
            app.http.server.configuration.port = port
        }
    }
}
