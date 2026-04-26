import Foundation
import Vapor

private enum RequestIDStorageKey: StorageKey {
    typealias Value = String
}

extension Request {
    var requestID: String {
        get { storage[RequestIDStorageKey.self] ?? UUID().uuidString }
        set { storage[RequestIDStorageKey.self] = newValue }
    }
}

struct RequestIDMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let headerValue = request.headers.first(name: "X-Request-Id")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = (headerValue?.isEmpty == false) ? headerValue! : UUID().uuidString
        request.requestID = requestID
        request.logger[metadataKey: "request-id"] = .string(requestID)
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Request-Id", value: requestID)
        return response
    }
}

struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let abort as any AbortError {
            return makeErrorResponse(
                request: request,
                status: abort.status,
                reason: abort.reason,
                code: code(for: abort.status)
            )
        } catch {
            request.logger.report(error: error)
            return makeErrorResponse(
                request: request,
                status: .internalServerError,
                reason: "internal server error",
                code: "internal_error"
            )
        }
    }

    private func code(for status: HTTPStatus) -> String {
        switch status {
        case .badRequest: return "bad_request"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "not_found"
        case .conflict: return "conflict"
        case .tooManyRequests: return "too_many_requests"
        case .notImplemented: return "not_implemented"
        default: return "http_\(status.code)"
        }
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    private let config: ServerConfig.RateLimitConfig
    private let store: any RateLimitStore

    init(config: ServerConfig.RateLimitConfig, store: any RateLimitStore) {
        self.config = config
        self.store = store
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let policy = policy(for: request) {
            let evaluation = try await store.consume(
                key: policy.key,
                limit: policy.limit,
                windowSeconds: 60,
                now: Date()
            )
            if !evaluation.allowed {
                let response = makeErrorResponse(
                    request: request,
                    status: .tooManyRequests,
                    reason: "rate limit exceeded",
                    code: "too_many_requests"
                )
                response.headers.replaceOrAdd(name: "Retry-After", value: String(evaluation.retryAfter))
                return response
            }
        }

        return try await next.respond(to: request)
    }

    private func policy(for request: Request) -> (key: String, limit: Int)? {
        guard request.method == .GET else {
            return nil
        }

        guard let clientIP = clientIPAddress(req: request) else {
            return nil
        }

        let path = request.url.path
        if path.hasPrefix("/v1/updates/"),
           let appId = request.parameters.get("appId") {
            return ("updates:\(clientIP):\(appId)", config.updatesPerMinute)
        }

        if path.hasPrefix("/v1/patch/"),
           let appId = request.parameters.get("appId"),
           let fromVersion = request.parameters.get("fromVersion"),
           let toVersion = request.parameters.get("toVersion") {
            return ("patch:\(clientIP):\(appId):\(fromVersion):\(toVersion)", config.patchPerMinute)
        }

        return nil
    }
}

struct RequestLoggingMiddleware: AsyncMiddleware {
    private let metrics: APIMetricsCollector

    init(metrics: APIMetricsCollector) {
        self.metrics = metrics
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = DispatchTime.now().uptimeNanoseconds
        let response = try await next.respond(to: request)
        let end = DispatchTime.now().uptimeNanoseconds
        let durationMs = Double(end - start) / 1_000_000
        let responseBytes = Int(response.headers.first(name: .contentLength) ?? "") ?? 0
        let requestId = request.requestID

        await metrics.record(
            path: request.url.path,
            status: response.status,
            durationMs: durationMs,
            responseBytes: responseBytes
        )

        request.logger.info(
            "request_completed",
            metadata: [
                "request_id": .string(requestId),
                "method": .string(request.method.rawValue),
                "path": .string(request.url.path),
                "status": .stringConvertible(response.status.code),
                "duration_ms": .string(String(format: "%.2f", durationMs)),
                "response_bytes": .stringConvertible(responseBytes)
                ]
        )
        response.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
        return response
    }
}

func makeErrorResponse(request: Request, status: HTTPStatus, reason: String, code: String) -> Response {
    let requestId = request.requestID
    request.logger.error(
        "request_failed",
        metadata: [
            "request_id": .string(requestId),
            "status": .stringConvertible(status.code),
            "code": .string(code),
            "message": .string(reason),
            "path": .string(request.url.path),
            "method": .string(request.method.rawValue)
        ]
    )

    let envelope = ErrorEnvelope(
        error: ErrorDetails(
            code: code,
            message: reason,
            requestId: requestId
        )
    )
    let response = Response(status: status)
    response.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
    do {
        try response.content.encode(envelope)
    } catch {
        response.body = .init(string: #"{"error":{"code":"internal_error","message":"failed to encode error","requestId":"\#(requestId)"}}"#)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
    }
    return response
}

func clientIPAddress(req: Request) -> String? {
    if let forwarded = req.headers.first(name: "X-Forwarded-For")?
        .split(separator: ",")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !forwarded.isEmpty {
        return forwarded
    }
    return req.remoteAddress?.ipAddress
}
