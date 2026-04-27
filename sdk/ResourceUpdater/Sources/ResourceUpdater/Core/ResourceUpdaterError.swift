import Foundation

public enum ResourceUpdaterError: Error {
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
}
