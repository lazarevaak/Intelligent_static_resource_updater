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
}
