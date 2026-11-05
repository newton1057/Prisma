import CryptoKit
import Foundation
import Testing
import UpdateCore

private let key = Curve25519.Signing.PrivateKey()
private let publicKey = key.publicKey.rawRepresentation.base64EncodedString()

private func signedManifest() throws -> UpdateManifest {
    try .signed(version: "1.2.3", build: 7, file: "versiones/1.2.3/app.zip", size: 1024, sha256: "abc", notes: "Primera línea\nSegunda línea", with: key)
}

@Test func aceptaLaFirmaLegitima() throws {
    #expect(try signedManifest().hasValidSignature(publicKey: publicKey))
}

@Test func rechazaCualquierCampoAlterado() throws {
    let m = try signedManifest()
    let altered = [
        UpdateManifest(version: "9.9.9", build: m.build, file: m.file, size: m.size, sha256: m.sha256, notes: m.notes, signature: m.signature),
        UpdateManifest(version: m.version, build: 99, file: m.file, size: m.size, sha256: m.sha256, notes: m.notes, signature: m.signature),
        UpdateManifest(version: m.version, build: m.build, file: "malo.zip", size: m.size, sha256: m.sha256, notes: m.notes, signature: m.signature),
        UpdateManifest(version: m.version, build: m.build, file: m.file, size: 1, sha256: m.sha256, notes: m.notes, signature: m.signature),
        UpdateManifest(version: m.version, build: m.build, file: m.file, size: m.size, sha256: "def", notes: m.notes, signature: m.signature),
        UpdateManifest(version: m.version, build: m.build, file: m.file, size: m.size, sha256: m.sha256, notes: "Otras notas", signature: m.signature),
    ]
    for manifest in altered {
        #expect(!manifest.hasValidSignature(publicKey: publicKey))
    }
}

@Test func rechazaUnaFirmaDeOtraClave() throws {
    let other = Curve25519.Signing.PrivateKey()
    let m = try signedManifest()
    let forged = try UpdateManifest.signed(version: m.version, build: m.build, file: m.file, size: m.size, sha256: m.sha256, notes: m.notes, with: other)
    #expect(!forged.hasValidSignature(publicKey: publicKey))
}

@Test func unaFirmaOClaveDeformeNoRompeLaApp() throws {
    let m = try signedManifest()
    let broken = UpdateManifest(version: m.version, build: m.build, file: m.file, size: m.size, sha256: m.sha256, notes: m.notes, signature: "no es base64")
    #expect(!broken.hasValidSignature(publicKey: publicKey))
    #expect(!m.hasValidSignature(publicKey: "PENDIENTE"))
    #expect(!m.hasValidSignature(publicKey: ""))
}

@Test func laFirmaSobreviveAlViajarComoJSON() throws {
    let data = try JSONEncoder().encode(signedManifest())
    #expect(try JSONDecoder().decode(UpdateManifest.self, from: data).hasValidSignature(publicKey: publicKey))
}

@Test func laClavePublicaDelCanalEsUtilizable() throws {
    let data = try #require(Data(base64Encoded: UpdateChannel.publicKey))
    #expect(throws: Never.self) { try Curve25519.Signing.PublicKey(rawRepresentation: data) }
}

@Test func calculaElHashDeUnArchivo() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString).txt")
    try Data("abc".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(try sha256Hex(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
