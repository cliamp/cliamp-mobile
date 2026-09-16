@preconcurrency import Citadel
import Crypto
@preconcurrency import NIOSSH
import Foundation
import NIOCore
import NIOSSH
import Synchronization

/// Failures a user has to read, phrased the way the wizard shows them.
public enum SshError: Error, LocalizedError, Sendable {
    case hostKeyMismatch(expected: String, actual: String)
    case keyUnreadable(String)
    case refusedCredentials
    case noSftpSubsystem
    case unreachable(String)
    case noMusicFolder
    case notAFolder(String)
    case missing(String)
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .hostKeyMismatch:
            "the host key does not match the one saved for this account"
        case .keyUnreadable(let detail):
            "could not read that private key: \(detail)"
        case .refusedCredentials:
            "the server refused those credentials"
        case .noSftpSubsystem:
            "connected, but the server does not offer sftp"
        case .unreachable(let detail):
            "could not reach the host: \(detail)"
        case .noMusicFolder:
            "connected, but found no music folder - give it a path"
        case .notAFolder(let folders):
            "not a folder on the server: \(folders)"
        case .missing(let path):
            "no such file: \(path)"
        case .validation(let message):
            message
        }
    }
}

/// Trust-on-first-use, pinned afterwards: the first probe records what the
/// host offered and the wizard shows it; every later connection must present
/// the same key or it is refused.
private final class PinnedHostKey: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let expected: String
    private let learned = Mutex<String?>(nil)

    init(expected: String) {
        self.expected = expected
    }

    var learnedFingerprint: String? {
        learned.withLock { $0 }
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 128)
        _ = hostKey.write(to: &buffer)
        let actual = fingerprint(ofPublicKeyBlob: Data(buffer.readableBytesView))
        if expected.isEmpty {
            learned.withLock { $0 = actual }
            validationCompletePromise.succeed(())
        } else if actual == expected {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SshError.hostKeyMismatch(expected: expected, actual: actual))
        }
    }
}

/// Offers the configured credential set, in order, exactly once each. SSH's
/// `none` method is a real offer (Tailscale's whole login), not a fallback.
private final class AccountAuthentication: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let offers: [NIOSSHUserAuthenticationOffer.Offer]
    private var index = 0

    init(username: String, offers: [NIOSSHUserAuthenticationOffer.Offer]) {
        self.username = username
        self.offers = offers
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard index < offers.count else {
            nextChallengePromise.succeed(nil)
            return
        }
        let offer = offers[index]
        index += 1
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username, serviceName: "ssh-connection", offer: offer
            )
        )
    }
}

/// One SSH connection's SFTP session. Actor-owned because Citadel's client
/// types are not Sendable; every call serializes here, which is also what a
/// single SFTP channel wants.
public actor SshSession: RemoteFileTree {
    private let config: SshConfig
    private var client: SSHClient?
    private var sftp: SFTPClient?
    /// The connection being established, shared by concurrent first callers so
    /// actor reentrancy cannot open (and then lose) several transports.
    private var connecting: Task<SFTPClient, Error>?
    /// Directory listings leak their remote handles in the SFTP client we
    /// depend on (Citadel never sends CLOSE for OPENDIR), so the channel is
    /// recycled periodically: closing it reclaims every leaked handle at once.
    private var listingsSinceRecycle = 0

    /// The fingerprint this session pinned or confirmed, once connected.
    public private(set) var fingerprint: String?

    public init(config: SshConfig) {
        self.config = config
    }

    // MARK: connecting

    private func channel() async throws -> SFTPClient {
        if let sftp { return sftp }
        if let connecting { return try await connecting.value }
        let config = self.config
        let validator = PinnedHostKey(expected: config.fingerprint)
        let task = Task<SFTPClient, Error>.detached {
            try await Self.connect(config: config, validator: validator)
        }
        connecting = task
        do {
            let sftp = try await task.value
            guard !Task.isCancelled else {
                try? await sftp.close()
                throw CancellationError()
            }
            self.sftp = sftp
            connecting = nil
            fingerprint = config.fingerprint.isEmpty
                ? validator.learnedFingerprint
                : config.fingerprint
            return sftp
        } catch {
            connecting = nil
            if let error = error as? SshError { throw error }
            throw Self.failure(error)
        }
    }

    private static func connect(config: SshConfig, validator: PinnedHostKey) async throws -> SFTPClient {
        let offers = try offers(for: config)
        let auth = AccountAuthentication(username: config.user, offers: offers)
        let settings = SSHClientSettings(
            host: config.host,
            port: config.port,
            authenticationMethod: { SSHAuthenticationMethod.custom(auth) },
            hostKeyValidator: .custom(validator)
        )
        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch let error as SshError {
            throw error
        } catch is InvalidHostKey {
            throw SshError.hostKeyMismatch(expected: config.fingerprint, actual: "")
        } catch {
            throw failure(error)
        }
        do {
            return try await client.openSFTP()
        } catch {
            try? await client.close()
            throw failure(error)
        }
    }

    /// Recycles the SFTP channel every so many listings, reclaiming the
    /// directory handles the dependency leaks.
    private func recycleIfNeeded() async {
        guard listingsSinceRecycle >= 200, let client else { return }
        listingsSinceRecycle = 0
        let old = sftp
        sftp = nil
        try? await old?.close()
        sftp = try? await client.openSFTP()
    }

    /// Turns Citadel's transport errors into the wizard's wording.
    private static func failure(_ error: Error) -> Error {
        let raw = String(describing: error).lowercased()
        if raw.contains("host key") || raw.contains("invalidhostkey") {
            return SshError.hostKeyMismatch(expected: "", actual: "")
        }
        if raw.contains("auth") || raw.contains("exhausted") {
            return SshError.refusedCredentials
        }
        if raw.contains("subsystem") {
            return SshError.noSftpSubsystem
        }
        if raw.contains("connection refused") || raw.contains("connect") || raw.contains("timeout") {
            return SshError.unreachable(String(describing: error))
        }
        return error
    }

    /// Builds the offer for the configured auth path. A key is parsed here,
    /// before any socket is opened, so a malformed key or wrong passphrase
    /// reports itself instead of masquerading as bad credentials.
    private static func offers(for config: SshConfig) throws -> [NIOSSHUserAuthenticationOffer.Offer] {
        switch config.auth {
        case .password:
            return [.password(.init(password: config.password))]
        case .none:
            // Tailscale (or any tailnet login) has no credential to send:
            // SSH's "none" method is the whole offer.
            return [.none]
        case .key:
            let passphrase = config.passphrase.isEmpty ? nil : Data(config.passphrase.utf8)
            let key = config.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ed25519 = try? Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase) {
                return [.privateKey(.init(privateKey: .init(ed25519Key: ed25519)))]
            }
            if let rsa = try? Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase) {
                // RSA offers sign with ssh-rsa (SHA-1) here; servers that have
                // disabled that algorithm refuse it. Ed25519 is preferred.
                return [.privateKey(.init(privateKey: .init(custom: rsa)))]
            }
            throw SshError.keyUnreadable(
                "unsupported or malformed key (ed25519 and RSA OpenSSH keys work), or the passphrase is wrong"
            )
        }
    }

    public func close() async {
        connecting?.cancel()
        connecting = nil
        if let sftp { try? await sftp.close() }
        if let client { try? await client.close() }
        sftp = nil
        client = nil
    }

    // MARK: RemoteFileTree

    public func canonicalize(_ path: String) async throws -> String {
        let sftp = try await channel()
        do {
            return try await sftp.getRealPath(atPath: path)
        } catch {
            throw Self.failure(error)
        }
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        let sftp = try await channel()
        defer { listingsSinceRecycle += 1 }
        do {
            let names = try await sftp.listDirectory(atPath: path)
            await recycleIfNeeded()
            var entries: [RemoteEntry] = []
            // One NAME response can hold several entries (asyncssh batches
            // them), so every component counts, not just the message's last.
            for name in names {
                for component in name.components {
                    let filename = component.filename
                    guard filename != ".", filename != "..", !filename.isEmpty else { continue }
                    entries.append(Self.entry(
                        path: path,
                        name: filename,
                        attributes: component.attributes,
                        longname: component.longname
                    ))
                }
            }
            return entries
        } catch {
            throw Self.failure(error)
        }
    }

    public func stat(_ path: String) async throws -> RemoteEntry? {
        let sftp = try await channel()
        do {
            let attributes = try await sftp.getAttributes(at: path)
            // `stat` already has the full path: it must not be joined again.
            let modified = attributes.accessModificationTime?.modificationTime
                .timeIntervalSince1970 ?? 0
            return RemoteEntry(
                name: (path as NSString).lastPathComponent,
                path: path,
                kind: Self.kind(of: attributes, longname: ""),
                size: Int64(attributes.size ?? 0),
                modifiedAt: Int64(max(0, modified))
            )
        } catch {
            return nil
        }
    }

    /// Reads one range, chunked to the 32 KiB SFTP servers actually honour.
    /// The player asks for larger ranges than a single READ allows.
    public func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data {
        let sftp = try await channel()
        do {
            return try await sftp.withFile(filePath: path, flags: [.read]) { file in
                var data = Data()
                var position = offset
                var remaining = Int64(length)
                let chunk: UInt32 = 32 * 1024
                while remaining > 0 {
                    let wanted = UInt32(min(Int64(chunk), remaining))
                    let buffer = try await file.read(from: position, length: wanted)
                    let bytes = buffer.readableBytes
                    if bytes == 0 { break }
                    data.append(contentsOf: buffer.readableBytesView)
                    position += UInt64(bytes)
                    remaining -= Int64(bytes)
                }
                return data
            }
        } catch {
            throw Self.failure(error)
        }
    }

    private static func entry(
        path: String,
        name: String,
        attributes: SFTPFileAttributes,
        longname: String = ""
    ) -> RemoteEntry {
        let kind = kind(of: attributes, longname: longname)
        let modified = attributes.accessModificationTime?.modificationTime
            .timeIntervalSince1970 ?? 0
        return RemoteEntry(
            name: name,
            path: path.hasSuffix("/") ? path + name : path + "/" + name,
            kind: kind,
            size: Int64(attributes.size ?? 0),
            modifiedAt: Int64(max(0, modified))
        )
    }

    /// The SFTP type bits when the server sent them, else the leading letter
    /// of the `ls -l` line — asyncssh's readdir omits permissions for many
    /// entries, and without this every subfolder reads as "other".
    static func kind(of attributes: SFTPFileAttributes, longname: String) -> RemoteEntry.Kind {
        if let mode = attributes.permissions {
            switch mode & 0o170000 {
            case 0o040000: return .directory
            case 0o100000: return .file
            case 0o120000: return .symlink
            default: break
            }
        }
        switch longname.first {
        case "d": return .directory
        case "l": return .symlink
        case "-": return .file
        default: return .other
        }
    }
}

/// Connects, verifies the folders and comes back with what the wizard needs to
/// save: the host key it now trusts and the folders it will index. Nothing is
/// written until this succeeds — a wrong path or a refused key would otherwise
/// surface as an empty library with nothing to point at.
public enum SshProbe {
    public static func probe(_ values: [String: String]) async throws -> ProviderIdentity {
        let config = sshConfig(values)
        let session = SshSession(config: config)
        defer { Task { await session.close() } }
        return try await probe(config: config, session: session)
    }

    static func probe(config: SshConfig, session: SshSession) async throws -> ProviderIdentity {
        // Touch the session so a bad key or credential fails here rather than
        // on the first scan.
        _ = try await session.canonicalize(".")

        let folders: [String]
        if config.folders.isEmpty {
            folders = await suggestMusicFolders(session)
            guard !folders.isEmpty else { throw SshError.noMusicFolder }
        } else {
            folders = config.folders
        }
        var missing: [String] = []
        for folder in folders where await !isDirectory(session, path: folder) {
            missing.append(folder)
        }
        guard missing.isEmpty else { throw SshError.notAFolder(missing.joined(separator: ", ")) }

        let pinned = await session.fingerprint ?? config.fingerprint
        return ProviderIdentity(
            name: config.endpoint,
            detail: pinned,
            values: [
                "fingerprint": storedFingerprint(config: config, fingerprint: pinned),
                "folders": folders.joined(separator: "\n"),
            ]
        )
    }
}
