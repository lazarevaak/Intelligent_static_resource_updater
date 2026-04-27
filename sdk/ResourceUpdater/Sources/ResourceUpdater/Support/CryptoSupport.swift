import CryptoKit
import Foundation

enum CryptoSupport {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verifySignature(
        data: Data,
        signatureBase64: String,
        publicKeyBase64: String
    ) throws {
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw ResourceUpdaterError.invalidHeader("signature")
        }
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            throw ResourceUpdaterError.invalidHeader("public key")
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        if !publicKey.isValidSignature(signature, for: data) {
            throw ResourceUpdaterError.signatureVerificationFailed
        }
    }
}
