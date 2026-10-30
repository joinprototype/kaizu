import CryptoKit
import Foundation

/// The public feed's newest release. `archive` and `signature` are missing from
/// an older feed, which then only offers the download.
public struct UpdateRelease: Decodable, Sendable, Equatable {
    public let version: String
    public let build: Int
    /// The DMG, for people who install by hand.
    public let url: URL
    /// The zip Kaizu installs by itself.
    public let archive: URL?
    public let signature: String?
}

public enum UpdateFailure: Error, Equatable {
    case cannotReplaceApp
    case notOffered
    case badDownload
    case badSignature
    case unpackFailed
    case wrongArchive
    case wrongApp
    case wrongBuild
    case badCodeSignature
}

/// An Ed25519 signature over the build number and the archive's digest, so an
/// old update can't be replayed as new. scripts/update-sign.swift makes them.
public enum UpdateSignature {
    public static func message(archive: URL, build: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: archive)
        defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 1 << 20), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return Data("kaizu-update-\(build)\n".utf8) + Data(digest.finalize())
    }

    public static func isValid(_ signature: String, archive: URL, build: Int, publicKey: String) -> Bool {
        guard let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let bytes = Data(base64Encoded: signature),
              let message = try? message(archive: archive, build: build)
        else { return false }
        return key.isValidSignature(bytes, for: message)
    }
}

/// An update checked and ready to swap in.
public struct StagedUpdate: Sendable, Equatable {
    public let app: URL
    public let version: String
    public let build: Int
}

/// Turns a downloaded archive into an app that's safe to swap in. Nothing is
/// unpacked until the signature holds, and any failure deletes the folder.
public struct UpdateStage: Sendable {
    public let folder: URL
    public let bundleID: String
    public let publicKey: String

    public init(folder: URL, bundleID: String, publicKey: String) {
        self.folder = folder
        self.bundleID = bundleID
        self.publicKey = publicKey
    }

    public func stage(archive: URL, build: Int, signature: String) throws -> StagedUpdate {
        do {
            guard UpdateSignature.isValid(signature, archive: archive, build: build, publicKey: publicKey) else {
                throw UpdateFailure.badSignature
            }
            let unpacked = folder.appending(path: "unpacked", directoryHint: .isDirectory)
            guard Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]) else {
                throw UpdateFailure.unpackFailed
            }
            let contents = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            guard contents.count == 1, let app = contents.first, app.pathExtension == "app" else {
                throw UpdateFailure.wrongArchive
            }
            return try inspect(app, build: build)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func inspect(_ app: URL, build: Int) throws -> StagedUpdate {
        let plist = app.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw UpdateFailure.wrongApp }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateFailure.wrongApp }
        guard info["CFBundleVersion"] as? String == String(build) else { throw UpdateFailure.wrongBuild }
        guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else {
            throw UpdateFailure.badCodeSignature
        }
        return StagedUpdate(app: app, version: info["CFBundleShortVersionString"] as? String ?? "?", build: build)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

public enum UpdatePlace {
    /// Whether Kaizu can replace itself where it sits. Not when run from a
    /// disk image or translocated by Gatekeeper, or from a folder it can't
    /// write to: those keep the download notice.
    public static func canReplace(app: URL) -> Bool {
        let path = app.standardizedFileURL.path
        guard app.pathExtension == "app", !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else {
            return false
        }
        let parent = app.deletingLastPathComponent()
        let readOnly = (try? parent.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true
        return !readOnly && FileManager.default.isWritableFile(atPath: parent.path)
    }
}

public enum UpdateSwap {
    /// Runs on after Kaizu quits. The new app first moves beside the old one,
    /// so a copy that fails (another volume) leaves the old one untouched, and
    /// the renames that follow are as near to one step as a shell gets.
    /// Arguments: pid, app path, staged path, relaunch flag.
    public static let script = #"""
    trap '' HUP INT TERM
    pid=$1 app=$2 staged=$3 relaunch=$4
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
      waited=$((waited + 1))
      if [ "$waited" -gt 1200 ]; then exit 1; fi
      sleep 0.05
    done
    incoming="$app.incoming.$$"
    outgoing="$app.outgoing.$$"
    if mv "$staged" "$incoming"; then
      if mv "$app" "$outgoing"; then
        if mv "$incoming" "$app"; then
          rm -rf "$outgoing"
        else
          mv "$outgoing" "$app"
        fi
      fi
    fi
    rm -rf "$incoming"
    if [ "$relaunch" = 1 ]; then /usr/bin/open "$app"; fi
    """#

    /// Leaves a helper running that swaps `staged` in for `app` once `pid` exits.
    public static func launch(pid: Int32, app: URL, staged: URL, relaunch: Bool) throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "kaizu-update", String(pid), app.path, staged.path, relaunch ? "1" : "0"]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
}
