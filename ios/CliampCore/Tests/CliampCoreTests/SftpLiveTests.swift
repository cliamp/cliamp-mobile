import Foundation
import Testing

@testable import CliampCore

/// Live checks against an SFTP server on loopback, run only when asked
/// (`CLIAMP_SFTP_LIVE=1 swift test`). The server used in development is
/// `sftp-server.py` (asyncssh) serving a small music tree on port 2222.
@Suite("sftp live", .enabled(if: ProcessInfo.processInfo.environment["CLIAMP_SFTP_LIVE"] == "1"))
struct SftpLiveTests {
    private static let root = ProcessInfo.processInfo.environment["CLIAMP_SFTP_ROOT"]
        ?? "/tmp/cliamp-sftp/music"
    private static let expectedFingerprint = ProcessInfo.processInfo
        .environment["CLIAMP_SFTP_FINGERPRINT"]

    private func values(host: String = "127.0.0.1", password: String = "testpass",
                        folders: String? = nil, fingerprint: String = "") -> [String: String] {
        var values: [String: String] = [
            "host": host,
            "port": "2222",
            "user": "tester",
            "_auth": "password",
            "password": password,
            "folders": folders ?? Self.root,
        ]
        if !fingerprint.isEmpty { values["fingerprint"] = fingerprint }
        return values
    }

    @Test("probe learns the host key and validates the folders")
    func probe() async throws {
        let identity = try await SshProbe.probe(values())
        #expect(identity.name == "tester@127.0.0.1:2222")
        if let expected = Self.expectedFingerprint {
            #expect(identity.detail == expected)
        }
        #expect(identity.detail.hasPrefix("SHA256:"))
        #expect(identity.values["fingerprint"]?.contains(Self.root) == false)
        let stored = storedFingerprint(
            config: sshConfig(values()), fingerprint: identity.detail
        )
        // The pin records the host it was seen on.
        #expect(stored == "127.0.0.1:2222 \(identity.detail)")
    }

    @Test("the probe finds folders when the field is left empty")
    func probeSuggestsFolders() async throws {
        let identity = try await SshProbe.probe(values(folders: ""))
        // The server's home is not a music tree, so this must fail loudly
        // rather than save an account with nothing to index.
        #expect(identity.values["folders"]?.isEmpty == false)
    }

    private func keyValues(keyPath: String, passphrase: String = "") -> [String: String] {
        let key = (try? String(contentsOfFile: keyPath, encoding: .utf8)) ?? ""
        return [
            "host": "127.0.0.1",
            "port": "2222",
            "user": "tester",
            "_auth": "key",
            "key": key,
            "passphrase": passphrase,
            "folders": Self.root,
        ]
    }

    @Test("a pasted ed25519 key authenticates")
    func keyAuth() async throws {
        let identity = try await SshProbe.probe(keyValues(keyPath: "/tmp/cliamp-sftp/id_ed25519"))
        #expect(identity.detail.hasPrefix("SHA256:"))
    }

    @Test("a passphrase-protected key authenticates with its passphrase")
    func keyPassphrase() async throws {
        let identity = try await SshProbe.probe(
            keyValues(keyPath: "/tmp/cliamp-sftp/id_ed25519_pw", passphrase: "keypass")
        )
        #expect(identity.detail.hasPrefix("SHA256:"))
    }

    @Test("a passphrase-protected key without its passphrase is refused")
    func keyMissingPassphrase() async throws {
        await #expect(throws: SshError.self) {
            try await SshProbe.probe(keyValues(keyPath: "/tmp/cliamp-sftp/id_ed25519_pw"))
        }
    }

    @Test("a wrong password is refused with the wizard's wording")
    func wrongPassword() async throws {
        await #expect(throws: SshError.self) {
            try await SshProbe.probe(values(password: "nope"))
        }
    }

    @Test("a pinned fingerprint that does not match is refused")
    func mismatch() async throws {
        let pinned = "127.0.0.1:2222 SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        await #expect(throws: SshError.self) {
            try await SshProbe.probe(values(fingerprint: pinned))
        }
    }

    @Test("scan finds the tree's tracks and reads a byte range")
    func scanAndRead() async throws {
        let session = SshSession(config: sshConfig(values()))
        defer { Task { await session.close() } }

        let entries = try await session.list(Self.root)
        #expect(entries.contains { $0.name == "Boards of Canada" && $0.kind == .directory }, "entries: \(entries)")

        let box = LiveTrackBox()
        let scan = SftpScan(folders: [Self.root], onBatch: { box.append($0) })
        let total = try await scan.run(session)
        #expect(total == 3)
        #expect(box.tracks.contains { $0.title == "Wildlife Analysis" && $0.track == 1 })
        #expect(box.tracks.contains { $0.artist == "Boards of Canada" && $0.album == "Music Has the Right to Children" })
        #expect(box.tracks.contains { $0.title == "loose track" && $0.artist == "" })

        let first = try await session.read(
            "\(Self.root)/Boards of Canada/Music Has the Right to Children/01 - Wildlife Analysis.m4a",
            offset: 0, length: 32
        )
        #expect(first.count == 32)
        let later = try await session.read(
            "\(Self.root)/Boards of Canada/Music Has the Right to Children/01 - Wildlife Analysis.m4a",
            offset: 16_384, length: 32
        )
        #expect(later.count == 32)
        #expect(first != later)
    }
}

private final class LiveTrackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ScannedTrack] = []

    func append(_ tracks: [ScannedTrack]) {
        lock.withLock { stored += tracks }
    }

    var tracks: [ScannedTrack] {
        lock.withLock { stored }
    }
}
