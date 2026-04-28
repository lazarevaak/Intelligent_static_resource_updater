@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
    @Test("GET /v1/metrics returns per-endpoint API metrics")
    func apiMetricsEndpoint() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let fromManifest = makeEmptyManifest(version: fromVersion)
            let toManifest = makeEmptyManifest(version: toVersion)
            let patchData = Data(#"{"schemaVersion":1,"appId":"demo","fromVersion":"1.0.0","toVersion":"1.1.0","generatedAt":"2026-01-01T00:00:00Z","operations":[]}"#.utf8)
            let patchHash = sha256(patchData)

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: patchHash)
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            var manifestEtag: String?
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/version/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    manifestEtag = res.headers.first(name: "ETag")
                }
            )
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/version/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: manifestEtag ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )

            var patchEtag: String?
            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    patchEtag = res.headers.first(name: "ETag")
                }
            )
            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: patchEtag ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=2.0",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/metrics",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Metrics-Token", value: metricsToken)
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: metricsAllowedIP)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let snapshot = try? res.content.decode(APIMetricsSnapshot.self)
                    #expect(snapshot != nil)
                    let manifest = snapshot?.endpoints.first(where: { $0.endpoint == "manifest" })
                    let patch = snapshot?.endpoints.first(where: { $0.endpoint == "patch" })
                    let updates = snapshot?.endpoints.first(where: { $0.endpoint == "updates" })
                    #expect(manifest != nil)
                    #expect(patch != nil)
                    #expect(updates != nil)
                    #expect((manifest?.totalRequests ?? 0) >= 2)
                    #expect((manifest?.status304 ?? 0) >= 1)
                    #expect((patch?.totalRequests ?? 0) >= 2)
                    #expect((patch?.status304 ?? 0) >= 1)
                    #expect((updates?.totalRequests ?? 0) >= 1)
                    #expect((updates?.latencyMs.p95 ?? 0) >= 0)
                    #expect((updates?.averageResponseBytes ?? 0) >= 0)
                }
            )
        }
    }

    @Test("GET /metrics returns Prometheus text format")
    func prometheusMetricsEndpoint() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "1.0.0"
            let manifest = makeEmptyManifest(version: version)

            try await publishManifest(app: app, appId: appId, version: version, manifest: manifest)

            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/latest",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )

            try await app.testing().test(
                .GET,
                "metrics",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Metrics-Token", value: metricsToken)
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: metricsAllowedIP)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.contentType?.description.contains("text/plain") == true)
                    let body = String(buffer: res.body)
                    #expect(body.contains("# HELP resource_update_api_requests_total"))
                    #expect(body.contains(#"resource_update_api_requests_total{endpoint="manifest",status_class="2xx"}"#))
                    #expect(body.contains(#"resource_update_api_requests_304_total{endpoint="manifest"}"#))
                    #expect(body.contains(#"# TYPE resource_update_api_latency_ms histogram"#))
                    #expect(body.contains(#"resource_update_api_latency_ms_bucket{endpoint="manifest",le="5"}"#))
                    #expect(body.contains(#"resource_update_api_latency_ms_sum{endpoint="manifest"}"#))
                    #expect(body.contains(#"resource_update_api_latency_ms_count{endpoint="manifest"}"#))
                    #expect(body.contains(#"resource_update_api_response_bytes_bucket{endpoint="manifest",le="1024"}"#))
                    #expect(body.contains(#"resource_update_api_response_bytes_sum{endpoint="manifest"}"#))
                    #expect(body.contains(#"resource_update_api_response_bytes_count{endpoint="manifest"}"#))
                }
            )
        }
    }

    @Test("Metrics endpoints require token")
    func metricsRequireToken() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(
                .GET,
                "metrics",
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/metrics",
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("Metrics allowlist denies unknown IP and allows configured IP")
    func metricsAllowlist() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(
                .GET,
                "metrics",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Metrics-Token", value: metricsToken)
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.7")
                },
                afterResponse: { res async in
                    #expect(res.status == .forbidden)
                }
            )

            try await app.testing().test(
                .GET,
                "metrics",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Metrics-Token", value: metricsToken)
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: metricsAllowedIP)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("GET updates is rate limited per IP and appId")
    func updatesRateLimit() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "1.0.0"
            try await publishManifest(app: app, appId: appId, version: version, manifest: makeEmptyManifest(version: version))

            for _ in 0..<3 {
                try await app.testing().test(
                    .GET,
                    "v1/updates/\(appId)?fromVersion=0.9.0&sdkVersion=1.0",
                    beforeRequest: { req in
                        req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.10")
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )
            }

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=0.9.0&sdkVersion=1.0",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.10")
                },
                afterResponse: { res async in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: "Retry-After") != nil)
                    let envelope = try? res.content.decode(ErrorEnvelope.self)
                    #expect(envelope?.error.code == "too_many_requests")
                    #expect(envelope?.error.message == "rate limit exceeded")
                }
            )
        }
    }

    @Test("GET patch is rate limited per IP, appId and version pair")
    func patchRateLimit() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: makeEmptyManifest(version: fromVersion))
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: makeEmptyManifest(version: toVersion))

            for _ in 0..<2 {
                try await app.testing().test(
                    .GET,
                    "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                    beforeRequest: { req in
                        req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.11")
                    },
                    afterResponse: { res async in
                        #expect(res.status == .ok)
                    }
                )
            }

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.11")
                },
                afterResponse: { res async in
                    #expect(res.status == .tooManyRequests)
                    #expect(res.headers.first(name: "Retry-After") != nil)
                    let envelope = try? res.content.decode(ErrorEnvelope.self)
                    #expect(envelope?.error.code == "too_many_requests")
                    #expect(envelope?.error.message == "rate limit exceeded")
                }
            )
        }
    }

    @Test("Public app hides metrics routes when dedicated metrics listener is configured")
    func publicAppHidesMetricsWhenDedicatedListenerConfigured() async throws {
        let config = makeServerConfig(
            metrics: .init(
                token: metricsToken,
                allowlist: [metricsAllowedIP],
                listener: .init(host: "127.0.0.1", port: 9091)
            )
        )

        try await withApp(configure: { app in
            try await configurePublicApplication(
                app,
                config: config,
                metricsCollector: APIMetricsCollector(),
                includeMetricsRoutes: false
            )
        }, { app in
            try await app.testing().test(.GET, "metrics", afterResponse: { res async in
                #expect(res.status == .notFound)
            })

            try await app.testing().test(.GET, "v1/metrics", afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        })
    }

    @Test("Public app configures cleanup lifecycle and shared file rate limit store")
    func publicAppConfiguresCleanupLifecycleAndSharedRateLimitStore() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let sharedRateLimitDirectory = URL(fileURLWithPath: publicDirectory, isDirectory: true)
                .appendingPathComponent("shared-rate-limit", isDirectory: true)
                .path
            let config = ServerConfig(
                publishToken: publishToken,
                artifactBackend: .local,
                s3: nil,
                signing: .init(
                    activeKeyId: signingKeyId,
                    keys: [
                        .init(
                            keyId: signingKeyId,
                            privateKeyBase64: signingPrimaryPrivateKeyBase64,
                            createdAt: Date(timeIntervalSince1970: 0)
                        )
                    ]
                ),
                metrics: .init(token: metricsToken, allowlist: [], listener: nil),
                rateLimit: .init(
                    backend: .sharedFile,
                    updatesPerMinute: 0,
                    patchPerMinute: 0,
                    sharedDirectory: sharedRateLimitDirectory
                ),
                cleanup: .init(intervalSeconds: 1, keepLast: 1, appIds: nil)
            )

            try await withApp(configure: { app in
                app.directory.publicDirectory = publicDirectory
                try await configurePublicApplication(
                    app,
                    config: config,
                    metricsCollector: APIMetricsCollector(),
                    includeMetricsRoutes: true
                )
            }, { app in
                try await app.testing().test(.GET, "favicon.ico", afterResponse: { res async in
                    #expect(res.status == .noContent)
                })
            })
        }
    }

    @Test("S3 backend without S3 config is rejected")
    func s3BackendWithoutConfigIsRejected() async throws {
        try await withApp(configure: { app in
            let config = ServerConfig(
                publishToken: publishToken,
                artifactBackend: .s3,
                s3: nil,
                signing: .init(activeKeyId: signingKeyId, keys: []),
                metrics: .init(token: nil, allowlist: [], listener: nil),
                rateLimit: .init(backend: .memory, updatesPerMinute: 1, patchPerMinute: 1, sharedDirectory: nil),
                cleanup: nil
            )

            #expect(throws: (any Error).self) {
                try makeArtifactStorage(app: app, config: config)
            }
        }, { _ in })
    }

    @Test("Dedicated metrics app exposes metrics routes")
    func dedicatedMetricsAppExposesMetrics() async throws {
        let collector = APIMetricsCollector()
        let config = makeServerConfig(
            metrics: .init(
                token: metricsToken,
                allowlist: [metricsAllowedIP],
                listener: .init(host: "127.0.0.1", port: 9091)
            )
        )

        await collector.record(path: "/v1/manifest/demo", status: .ok, durationMs: 1.5, responseBytes: 128)

        try await withApp(configure: { app in
            try await configureMetricsApplication(
                app,
                config: config,
                metricsCollector: collector
            )
        }, { app in
            try await app.testing().test(
                .GET,
                "metrics",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Metrics-Token", value: metricsToken)
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: metricsAllowedIP)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let body = String(buffer: res.body)
                    #expect(body.contains(#"resource_update_api_requests_total{endpoint="manifest",status_class="2xx"} 1"#))
                }
            )
        })
    }
}
