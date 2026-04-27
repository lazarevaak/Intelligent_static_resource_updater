@preconcurrency import Crypto
import Foundation
import Vapor

struct SignatureService: Sendable {
    struct SignatureEnvelope: Sendable {
        let data: Data
        let sha256: String
        let signatureBase64: String
        let algorithm: String
        let keyId: String
    }

    private struct KeyEntry: @unchecked Sendable {
        let keyId: String
        let createdAt: Date
        let privateKey: Curve25519.Signing.PrivateKey
        let publicKeyBase64: String
    }

    private let activeKeyId: String
    private let activeKey: KeyEntry
    private let keysById: [String: KeyEntry]

    init(config: ServerConfig.SigningConfig) throws {
        var map: [String: KeyEntry] = [:]
        map.reserveCapacity(config.keys.count)
        for key in config.keys {
            guard let rawKey = Data(base64Encoded: key.privateKeyBase64) else {
                throw Abort(.internalServerError, reason: "invalid base64 private key for keyId=\(key.keyId)")
            }
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
            let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
            map[key.keyId] = KeyEntry(
                keyId: key.keyId,
                createdAt: key.createdAt,
                privateKey: privateKey,
                publicKeyBase64: publicKeyBase64
            )
        }

        guard let active = map[config.activeKeyId] else {
            throw Abort(.internalServerError, reason: "active signing key not found: \(config.activeKeyId)")
        }
        self.activeKeyId = config.activeKeyId
        self.activeKey = active
        self.keysById = map
    }

    func sign<T: Encodable>(_ payload: T) throws -> SignatureEnvelope {
        let data = try canonicalJSON(payload)
        return try signRaw(data)
    }

    func sign(_ payload: Data) throws -> SignatureEnvelope {
        try signRaw(payload)
    }

    private func signRaw(_ data: Data) throws -> SignatureEnvelope {
        let signature = try activeKey.privateKey.signature(for: data)
        return SignatureEnvelope(
            data: data,
            sha256: sha256(data),
            signatureBase64: signature.base64EncodedString(),
            algorithm: "ed25519",
            keyId: activeKey.keyId
        )
    }

    func publicKeys() -> [SigningPublicKey] {
        keysById.values
            .map {
                SigningPublicKey(
                    keyId: $0.keyId,
                    alg: "ed25519",
                    publicKeyBase64: $0.publicKeyBase64,
                    createdAt: $0.createdAt,
                    active: $0.keyId == activeKeyId
                )
            }
            .sorted { $0.keyId < $1.keyId }
    }

    func publicKey(keyId: String) -> SigningPublicKey? {
        guard let key = keysById[keyId] else { return nil }
        return SigningPublicKey(
            keyId: key.keyId,
            alg: "ed25519",
            publicKeyBase64: key.publicKeyBase64,
            createdAt: key.createdAt,
            active: key.keyId == activeKeyId
        )
    }

    private func canonicalJSON<T: Encodable>(_ payload: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
