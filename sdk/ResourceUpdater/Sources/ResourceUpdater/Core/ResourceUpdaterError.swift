import Foundation

public enum ResourceUpdaterError: Error, LocalizedError, CustomStringConvertible {
    case invalidResponse
    case unexpectedStatusCode(Int)
    case missingHeader(String)
    case invalidHeader(String)
    case invalidSignatureAlgorithm(String)
    case signatureVerificationFailed
    case hashMismatch(expected: String, actual: String)
    case sizeMismatch(expected: Int, actual: Int)
    case invalidPatchOperation(String)
    case invalidResourcePath(String)
    case unsupportedDeltaAlgorithm(String)
    case resourceNotFound(String)

    public var errorDescription: String? {
        description
    }

    public var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .unexpectedStatusCode(let statusCode):
            return "Unexpected HTTP status code: \(statusCode)"
        case .missingHeader(let header):
            return "Missing response header: \(header)"
        case .invalidHeader(let header):
            return "Invalid response header: \(header)"
        case .invalidSignatureAlgorithm(let algorithm):
            return "Invalid signature algorithm: \(algorithm)"
        case .signatureVerificationFailed:
            return "Signature verification failed"
        case .hashMismatch(let expected, let actual):
            return "Hash mismatch. Expected \(expected), actual \(actual)"
        case .sizeMismatch(let expected, let actual):
            return "Size mismatch. Expected \(expected), actual \(actual)"
        case .invalidPatchOperation(let operation):
            return "Invalid patch operation: \(operation)"
        case .invalidResourcePath(let path):
            return "Invalid resource path: \(path)"
        case .unsupportedDeltaAlgorithm(let algorithm):
            return "Unsupported delta algorithm: \(algorithm)"
        case .resourceNotFound(let path):
            return "Resource not found: \(path)"
        }
    }
}
