import Vapor

struct UpdatesResponse: Content {
    let decision: String
    let appId: String
    let fromVersion: String?
    let latestVersion: String
    let sdkVersion: String?
    let reason: String
    let manifest: SignedObjectDescriptor
    let patch: SignedObjectDescriptor?
}

struct SignedObjectDescriptor: Content {
    let url: String
    let sha256: String
    let signature: String
    let signatureAlgorithm: String
    let signatureKeyId: String
    let size: Int
}
