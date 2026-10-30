// Signs update archives so Kaizu only installs builds we published.
//   swift scripts/update-sign.swift new <key-file>            writes a new key, prints the public half
//   swift scripts/update-sign.swift sign <key-file> <zip> <build>   prints the signature
// The signature covers the build number too, so an old update can't be replayed as new.
import CryptoKit
import Foundation

let args = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch args.dropFirst().first {
case "new":
    guard args.count == 3 else { fail("usage: new <key-file>") }
    let path = args[2]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) already exists") }
    let key = Curve25519.Signing.PrivateKey()
    let created = FileManager.default.createFile(
        atPath: path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600]
    )
    guard created else { fail("couldn't write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 5, let build = Int(args[4]) else { fail("usage: sign <key-file> <zip> <build>") }
    guard let stored = try? String(contentsOfFile: args[2], encoding: .utf8),
          let raw = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
          let archive = try? Data(contentsOf: URL(fileURLWithPath: args[3]))
    else { fail("couldn't read the key or the archive") }
    let message = Data("kaizu-update-\(build)\n".utf8) + Data(SHA256.hash(data: archive))
    guard let signature = try? key.signature(for: message) else { fail("signing failed") }
    print(signature.base64EncodedString())
default:
    fail("usage: new <key-file> | sign <key-file> <zip> <build>")
}
