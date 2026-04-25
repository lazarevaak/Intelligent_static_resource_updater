import Foundation
import Vapor

struct APIMetricsSnapshot: Content {
    struct EndpointSnapshot: Content {
        struct LatencySnapshot: Content {
            let p50: Double
            let p95: Double
            let p99: Double
        }

        let endpoint: String
        let totalRequests: Int
        let status2xx: Int
        let status4xx: Int
        let status5xx: Int
        let status304: Int
        let notModifiedRatio: Double
        let averageResponseBytes: Double
        let latencyMs: LatencySnapshot
    }

    let generatedAt: Date
    let endpoints: [EndpointSnapshot]
}

actor APIMetricsCollector {
    private static let latencyBucketsMs: [Double] = [1, 5, 10, 25, 50, 100, 250, 500, 1000]
    private static let responseSizeBucketsBytes: [Double] = [256, 1024, 4096, 16384, 65536, 262144, 1048576]

    private struct EndpointMetrics {
        var totalRequests: Int = 0
        var status2xx: Int = 0
        var status4xx: Int = 0
        var status5xx: Int = 0
        var status304: Int = 0
        var totalResponseBytes: Int = 0
        var latencySamplesMs: [Double] = []
        var responseSizeSamples: [Double] = []
    }

    private let maxSamplesPerEndpoint: Int
    private var byEndpoint: [String: EndpointMetrics] = [:]

    init(maxSamplesPerEndpoint: Int = 5000) {
        self.maxSamplesPerEndpoint = maxSamplesPerEndpoint
    }

    func record(path: String, status: HTTPResponseStatus, durationMs: Double, responseBytes: Int) {
        guard let endpoint = classify(path: path) else {
            return
        }

        var metrics = byEndpoint[endpoint, default: .init()]
        metrics.totalRequests += 1
        metrics.totalResponseBytes += max(responseBytes, 0)
        metrics.latencySamplesMs.append(max(durationMs, 0))
        metrics.responseSizeSamples.append(Double(max(responseBytes, 0)))
        if metrics.latencySamplesMs.count > maxSamplesPerEndpoint {
            metrics.latencySamplesMs.removeFirst(metrics.latencySamplesMs.count - maxSamplesPerEndpoint)
        }
        if metrics.responseSizeSamples.count > maxSamplesPerEndpoint {
            metrics.responseSizeSamples.removeFirst(metrics.responseSizeSamples.count - maxSamplesPerEndpoint)
        }

        switch status.code {
        case 200..<300:
            metrics.status2xx += 1
        case 400..<500:
            metrics.status4xx += 1
        case 500..<600:
            metrics.status5xx += 1
        default:
            break
        }
        if status == .notModified {
            metrics.status304 += 1
        }

        byEndpoint[endpoint] = metrics
    }

    func snapshot() -> APIMetricsSnapshot {
        let endpoints = byEndpoint.keys.sorted().map { endpoint in
            let metrics = byEndpoint[endpoint] ?? .init()
            let latencies = percentiles(for: metrics.latencySamplesMs)
            let total = max(metrics.totalRequests, 1)
            return APIMetricsSnapshot.EndpointSnapshot(
                endpoint: endpoint,
                totalRequests: metrics.totalRequests,
                status2xx: metrics.status2xx,
                status4xx: metrics.status4xx,
                status5xx: metrics.status5xx,
                status304: metrics.status304,
                notModifiedRatio: Double(metrics.status304) / Double(total),
                averageResponseBytes: Double(metrics.totalResponseBytes) / Double(total),
                latencyMs: .init(p50: latencies.p50, p95: latencies.p95, p99: latencies.p99)
            )
        }
        return APIMetricsSnapshot(generatedAt: Date(), endpoints: endpoints)
    }

    func prometheusText() -> String {
        var lines: [String] = [
            "# HELP resource_update_api_requests_total Total API requests by endpoint group and status class.",
            "# TYPE resource_update_api_requests_total counter",
            "# HELP resource_update_api_requests_304_total Total API responses with HTTP 304 by endpoint group.",
            "# TYPE resource_update_api_requests_304_total counter",
            "# HELP resource_update_api_not_modified_ratio Ratio of HTTP 304 responses by endpoint group.",
            "# TYPE resource_update_api_not_modified_ratio gauge",
            "# HELP resource_update_api_response_bytes_avg Average response size in bytes by endpoint group.",
            "# TYPE resource_update_api_response_bytes_avg gauge",
            "# HELP resource_update_api_latency_ms API latency histogram in milliseconds by endpoint group.",
            "# TYPE resource_update_api_latency_ms histogram",
            "# HELP resource_update_api_response_bytes API response size histogram in bytes by endpoint group.",
            "# TYPE resource_update_api_response_bytes histogram"
        ]

        for endpoint in byEndpoint.keys.sorted() {
            let metrics = byEndpoint[endpoint] ?? .init()
            let total = max(metrics.totalRequests, 1)
            let latencyHistogram = histogram(samples: metrics.latencySamplesMs, buckets: Self.latencyBucketsMs)
            let responseSizeHistogram = histogram(samples: metrics.responseSizeSamples, buckets: Self.responseSizeBucketsBytes)

            lines.append(#"resource_update_api_requests_total{endpoint="\#(endpoint)",status_class="2xx"} \#(metrics.status2xx)"#)
            lines.append(#"resource_update_api_requests_total{endpoint="\#(endpoint)",status_class="4xx"} \#(metrics.status4xx)"#)
            lines.append(#"resource_update_api_requests_total{endpoint="\#(endpoint)",status_class="5xx"} \#(metrics.status5xx)"#)
            lines.append(#"resource_update_api_requests_304_total{endpoint="\#(endpoint)"} \#(metrics.status304)"#)
            lines.append(#"resource_update_api_not_modified_ratio{endpoint="\#(endpoint)"} \#(Double(metrics.status304) / Double(total))"#)
            lines.append(#"resource_update_api_response_bytes_avg{endpoint="\#(endpoint)"} \#(Double(metrics.totalResponseBytes) / Double(total))"#)
            appendHistogram(
                name: "resource_update_api_latency_ms",
                endpoint: endpoint,
                histogram: latencyHistogram,
                to: &lines
            )
            appendHistogram(
                name: "resource_update_api_response_bytes",
                endpoint: endpoint,
                histogram: responseSizeHistogram,
                to: &lines
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func classify(path: String) -> String? {
        if path.hasPrefix("/v1/updates/") { return "updates" }
        if path.hasPrefix("/v1/manifest/") { return "manifest" }
        if path.hasPrefix("/v1/patch/") { return "patch" }
        return nil
    }

    private func percentiles(for samples: [Double]) -> (p50: Double, p95: Double, p99: Double) {
        guard !samples.isEmpty else {
            return (0, 0, 0)
        }
        let sorted = samples.sorted()
        func value(_ q: Double) -> Double {
            let index = Int((Double(sorted.count - 1) * q).rounded(.toNearestOrAwayFromZero))
            return sorted[min(max(index, 0), sorted.count - 1)]
        }
        return (value(0.50), value(0.95), value(0.99))
    }

    private func histogram(samples: [Double], buckets: [Double]) -> (buckets: [(le: String, value: Int)], count: Int, sum: Double) {
        var bucketCounts = Array(repeating: 0, count: buckets.count)
        var count = 0
        var sum = 0.0

        for sample in samples {
            let normalized = max(sample, 0)
            count += 1
            sum += normalized
            for (index, bucket) in buckets.enumerated() where normalized <= bucket {
                bucketCounts[index] += 1
            }
        }

        let renderedBuckets = zip(buckets, bucketCounts).map { bucket, value in
            (le: renderNumber(bucket), value: value)
        } + [(le: "+Inf", value: count)]

        return (renderedBuckets, count, sum)
    }

    private func appendHistogram(
        name: String,
        endpoint: String,
        histogram: (buckets: [(le: String, value: Int)], count: Int, sum: Double),
        to lines: inout [String]
    ) {
        for bucket in histogram.buckets {
            lines.append(#"\#(name)_bucket{endpoint="\#(endpoint)",le="\#(bucket.le)"} \#(bucket.value)"#)
        }
        lines.append(#"\#(name)_sum{endpoint="\#(endpoint)"} \#(renderNumber(histogram.sum))"#)
        lines.append(#"\#(name)_count{endpoint="\#(endpoint)"} \#(histogram.count)"#)
    }
    private func renderNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}

private enum APIMetricsStorageKey: StorageKey {
    typealias Value = APIMetricsCollector
}

extension Application {
    var apiMetricsCollector: APIMetricsCollector {
        get {
            if let existing = storage[APIMetricsStorageKey.self] {
                return existing
            }
            let created = APIMetricsCollector()
            storage[APIMetricsStorageKey.self] = created
            return created
        }
        set {
            storage[APIMetricsStorageKey.self] = newValue
        }
    }
}
