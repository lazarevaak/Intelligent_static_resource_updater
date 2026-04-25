import Vapor

struct PatchArtifact: Content {
    let schemaVersion: Int
    let appId: String
    let fromVersion: String
    let toVersion: String
    let generatedAt: Date
    let operations: [PatchOperation]
}

struct PatchOperation: Content {
    let op: String
    let path: String
    let hash: String?
    let size: Int?
    let dataBase64: String?
    let delta: BinaryDeltaPatch?
}

struct BinaryDeltaPatch: Content {
    let algorithm: String
    let baseHash: String
    let baseSize: Int
    let targetHash: String
    let targetSize: Int
    let operations: [BinaryDeltaOperation]
}

struct BinaryDeltaOperation: Content {
    let offset: Int
    let deleteLength: Int
    let dataBase64: String
}
