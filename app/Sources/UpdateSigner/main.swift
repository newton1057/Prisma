import CryptoKit
import Foundation
import UpdateCore

// Administra la clave privada de actualizaciones y firma cada versión. Nunca la imprime.

private let service = "Prisma actualizaciones"
private let account = "ed25519"

private func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data("\(text)\n".utf8))
    exit(1)
}

/// `security` no cambia entre compilaciones, así que el llavero no vuelve a pedir permiso.
@discardableResult
private func security(_ arguments: [String], input: String? = nil) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let output = Pipe()
    let stdin = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = input == nil ? FileHandle.nullDevice : stdin
    do { try process.run() } catch { fail("No se pudo ejecutar security.") }
    if let input {
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func storedKey() -> Curve25519.Signing.PrivateKey? {
    let result = security(["find-generic-password", "-a", account, "-s", service, "-w"])
    guard result.status == 0,
          let data = Data(base64Encoded: result.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

private func requiredKey() -> Curve25519.Signing.PrivateKey {
    guard let key = storedKey() else { fail("Falta la clave de firma en el llavero de este Mac.") }
    return key
}

private func printPublicKey(_ key: Curve25519.Signing.PrivateKey) {
    print(key.publicKey.rawRepresentation.base64EncodedString())
}

private func size(of file: URL) throws -> Int {
    guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { fail("No se pudo medir \(file.path).") }
    return size
}

private let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch (arguments.first, arguments.count) {
    case ("generar", 1):
        guard storedKey() == nil else { fail("Ya existe una clave de firma; reemplazarla dejaría sin actualizaciones a las apps instaladas.") }
        let key = Curve25519.Signing.PrivateKey()
        // Entra por stdin para que el secreto no aparezca en la lista de procesos.
        let secret = key.rawRepresentation.base64EncodedString()
        security(["-i"], input: "add-generic-password -a \(account) -s \"\(service)\" -T /usr/bin/security -w \(secret)\n")
        guard storedKey() != nil else { fail("No se pudo guardar la clave en el llavero.") }
        printPublicKey(key)
    case ("publica", 1):
        printPublicKey(requiredKey())
    case ("respaldar", 2):
        let destination = URL(fileURLWithPath: arguments[1])
        guard !FileManager.default.fileExists(atPath: destination.path) else { fail("Ya existe \(destination.path).") }
        let secret = Data(requiredKey().rawRepresentation.base64EncodedString().utf8)
        guard FileManager.default.createFile(atPath: destination.path, contents: secret, attributes: [.posixPermissions: 0o600]) else {
            fail("No se pudo escribir \(destination.path).")
        }
        print("Respaldo guardado. Guárdalo en un lugar seguro y bórralo de aquí.")
    case ("restaurar", 2):
        guard storedKey() == nil else { fail("Ya existe una clave de firma; no se restaura encima.") }
        let source = URL(fileURLWithPath: arguments[1])
        guard let data = try? Data(contentsOf: source),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let raw = Data(base64Encoded: text),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
            fail("El archivo no contiene una clave de firma válida.")
        }
        security(["-i"], input: "add-generic-password -a \(account) -s \"\(service)\" -T /usr/bin/security -w \(text)\n")
        guard storedKey() != nil else { fail("No se pudo guardar la clave en el llavero.") }
        printPublicKey(key)
    case ("manifiesto", 6):
        let package = URL(fileURLWithPath: arguments[1])
        guard let build = Int(arguments[3]) else { fail("El build debe ser un número.") }
        let manifest = try UpdateManifest.signed(
            version: arguments[2], build: build, file: arguments[4], size: try size(of: package),
            sha256: try sha256Hex(of: package), notes: arguments[5], with: requiredKey()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(manifest), as: UTF8.self))
    case ("verificar", 3):
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let package = URL(fileURLWithPath: arguments[2])
        guard manifest.hasValidSignature() else { fail("La firma no corresponde a la clave pública incluida en la app.") }
        guard try size(of: package) == manifest.size, try sha256Hex(of: package) == manifest.sha256 else {
            fail("El paquete no coincide con el manifiesto.")
        }
        print("Manifiesto y paquete correctos.")
    default:
        fail("""
        Uso:
          UpdateSigner generar
          UpdateSigner publica
          UpdateSigner respaldar <archivo>
          UpdateSigner restaurar <archivo>
          UpdateSigner manifiesto <paquete> <version> <build> <ruta en el bucket> <notas>
          UpdateSigner verificar <latest.json> <paquete>
        """)
    }
} catch {
    fail("Error: \(error.localizedDescription)")
}
