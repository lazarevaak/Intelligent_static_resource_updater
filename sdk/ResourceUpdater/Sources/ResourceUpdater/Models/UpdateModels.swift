import Foundation

public struct UpdatesResponse: Codable {
    public let decision: String
    public let appId: String
    public let fromVersion: String?
    public let latestVersion: String
    public let sdkVersion: String?
    public let reason: String
    public let manifest: SignedObjectDescriptor
    public let patch: SignedObjectDescriptor?
}

public struct SignedObjectDescriptor: Codable {
    public let url: String
    public let sha256: String
    public let signature: String
    public let signatureAlgorithm: String
    public let signatureKeyId: String
    public let size: Int
}

public struct SigningPublicKey: Codable {
    public let keyId: String
    public let alg: String
    public let publicKeyBase64: String
    public let createdAt: Date
    public let active: Bool
}

public struct PatchArtifact: Codable {
    public let schemaVersion: Int
    public let appId: String
    public let fromVersion: String
    public let toVersion: String
    public let generatedAt: Date
    public let operations: [PatchOperation]
}

public struct PatchOperation: Codable {
    public let op: String
    public let path: String
    public let hash: String?
    public let size: Int?
    public let dataBase64: String?
    public let delta: BinaryDeltaPatch?
}

public struct BinaryDeltaPatch: Codable {
    public let algorithm: String
    public let baseHash: String
    public let baseSize: Int
    public let targetHash: String
    public let targetSize: Int
    public let operations: [BinaryDeltaOperation]
}

public struct BinaryDeltaOperation: Codable {
    public let offset: Int
    public let deleteLength: Int
    public let dataBase64: String
}
