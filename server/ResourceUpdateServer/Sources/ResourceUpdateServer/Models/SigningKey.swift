import Vapor

struct SigningPublicKey: Content {
    let keyId: String
    let alg: String
    let publicKeyBase64: String
    let createdAt: Date
    let active: Bool
}
