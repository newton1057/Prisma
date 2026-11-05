import CryptoKit
import Foundation

/// Dónde se publican las actualizaciones y con qué clave se comprueban.
public enum UpdateChannel {
    public static let base = URL(string: "https://storage.googleapis.com/prisma-updates")!
    public static let manualDownload = URL(string: "https://github.com/newton1057/Prisma/releases")!
    /// Solo la clave privada del llavero de quien publica produce firmas que esta acepte.
    public static let publicKey = "SmrHvQbhETtIohDL39YXcMSQOunV7vP1aYAFWmg+QKo="
}

/// Describe la última versión. La firma cubre todos los campos: alterar uno la invalida.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let file: String
    public let size: Int
    public let sha256: String
    public let notes: String
    public let signature: String

    public init(version: String, build: Int, file: String, size: Int, sha256: String, notes: String, signature: String) {
        self.version = version
        self.build = build
        self.file = file
        self.size = size
        self.sha256 = sha256
        self.notes = notes
        self.signature = signature
    }

    public static func signed(
        version: String, build: Int, file: String, size: Int, sha256: String, notes: String,
        with key: Curve25519.Signing.PrivateKey
    ) throws -> UpdateManifest {
        let text = signedText(version: version, build: build, file: file, size: size, sha256: sha256, notes: notes)
        let signature = try key.signature(for: text).base64EncodedString()
        return UpdateManifest(version: version, build: build, file: file, size: size, sha256: sha256, notes: notes, signature: signature)
    }

    public func hasValidSignature(publicKey: String = UpdateChannel.publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signature = Data(base64Encoded: signature) else { return false }
        let text = Self.signedText(version: version, build: build, file: file, size: size, sha256: sha256, notes: notes)
        return key.isValidSignature(signature, for: text)
    }

    /// Las notas van al final porque son el único campo que puede contener saltos de línea.
    private static func signedText(version: String, build: Int, file: String, size: Int, sha256: String, notes: String) -> Data {
        Data([version, String(build), file, String(size), sha256, notes].joined(separator: "\n").utf8)
    }
}

/// Calcula el hash por bloques: los paquetes pesan más de 100 MB.
public func sha256Hex(of file: URL) throws -> String {
    let reader = try FileHandle(forReadingFrom: file)
    defer { try? reader.close() }
    var hash = SHA256()
    while let block = try reader.read(upToCount: 1 << 20), !block.isEmpty {
        hash.update(data: block)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
