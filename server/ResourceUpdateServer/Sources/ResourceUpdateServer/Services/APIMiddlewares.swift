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

    private func makeErrorResponse(request: Request, status: HTTPStatus, reason: String, code: String) -> Response {
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

    private func code(for status: HTTPStatus) -> String {
        switch status {
        case .badRequest: return "bad_request"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "not_found"
        case .conflict: return "conflict"
        case .notImplemented: return "not_implemented"
        default: return "http_\(status.code)"
        }
    }
}

struct RequestLoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = DispatchTime.now().uptimeNanoseconds
        let response = try await next.respond(to: request)
        let end = DispatchTime.now().uptimeNanoseconds
        let durationMs = Double(end - start) / 1_000_000
        let requestId = request.requestID

        request.logger.info(
            "request_completed",
            metadata: [
                "request_id": .string(requestId),
                "method": .string(request.method.rawValue),
                "path": .string(request.url.path),
                "status": .stringConvertible(response.status.code),
                "duration_ms": .string(String(format: "%.2f", durationMs))
                ]
        )
        response.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
        return response
    }
}
