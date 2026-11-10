import Foundation
import CryptoKit
import Citadel
import NIOCore
import NIOSSH

/// Trust-on-first-use host key check. The first key seen is reported back so it can be saved;
/// afterwards any other key fails the connection before credentials are sent.
private final class PinnedHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let trustedFingerprint: String?
    private let lock = NSLock()
    private var _observedFingerprint: String?

    init(trustedFingerprint: String?) {
        self.trustedFingerprint = trustedFingerprint
    }

    var observedFingerprint: String? {
        lock.lock()
        defer { lock.unlock() }
        return _observedFingerprint
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = Self.fingerprint(of: hostKey)
        lock.lock()
        _observedFingerprint = fingerprint
        lock.unlock()

        if let trustedFingerprint, trustedFingerprint != fingerprint {
            validationCompletePromise.fail(RootShellError.hostKeyMismatch(expected: trustedFingerprint, actual: fingerprint))
        } else {
            validationCompletePromise.succeed(())
        }
    }

    /// Same form `ssh-keygen -lf` prints: "SHA256:" + unpadded base64 of the key blob's digest.
    static func fingerprint(of hostKey: NIOSSHPublicKey) -> String {
        let openSSH = String(openSSHPublicKey: hostKey)
        let parts = openSSH.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            return "SHA256:unknown"
        }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(digest)"
    }
}

/// Root shell over SSH, entirely in-process: no `ssh` binary, no files in `~/.ssh`.
public struct SSHRootShell: RootShellRunning {
    public init() {}

    public func run(
        _ command: String,
        endpoint: RootShellEndpoint,
        credential: RootShellCredential,
        trustedHostKeyFingerprint: String?,
        timeout: Duration
    ) async throws -> RootShellOutput {
        let authentication: SSHAuthenticationMethod
        switch credential {
        case .none:
            throw RootShellError.notConfigured("SSH needs a key or a password.")
        case .password(let password):
            authentication = .passwordBased(username: endpoint.username, password: password)
        case .ed25519PrivateKey(let rawKey):
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawKey) else {
                throw RootShellError.notConfigured("The saved SSH key is damaged. Generate a new one.")
            }
            authentication = .ed25519(username: endpoint.username, privateKey: key)
        }

        let validator = PinnedHostKeyValidator(trustedFingerprint: trustedHostKeyFingerprint)
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let wrapped = RootShellFraming.wrap(command, nonce: nonce)
        let host = endpoint.host
        let port = endpoint.port

        // SSHAuthenticationMethod is an immutable value built from Sendable inputs above; the
        // library simply has not annotated it.
        nonisolated(unsafe) let unsafeAuthentication = authentication

        do {
            let text: String = try await withDeadline(timeout, timeoutError: RootShellError.timedOut) {
                var settings = SSHClientSettings(
                    host: host,
                    port: port,
                    authenticationMethod: { unsafeAuthentication },
                    hostKeyValidator: .custom(validator)
                )
                // The dropbear builds shipped for webOS are old; allow RSA host keys, AES-CTR and
                // group14 key exchange in addition to the modern defaults.
                settings.algorithms = .all
                settings.connectTimeout = .seconds(8)

                let client = try await SSHClient.connect(to: settings)
                do {
                    let buffer = try await client.executeCommand(wrapped, maxResponseSize: 1 << 20, mergeStreams: true)
                    try? await client.close()
                    return String(buffer: buffer)
                } catch {
                    try? await client.close()
                    throw error
                }
            }

            guard let result = RootShellFraming.extract(from: text, nonce: nonce) else {
                throw RootShellError.malformedOutput(String(text.prefix(200)))
            }
            return RootShellOutput(output: result.output, exitStatus: result.status, hostKeyFingerprint: validator.observedFingerprint)
        } catch let error as RootShellError {
            throw error
        } catch {
            // A host key mismatch surfaces wrapped by the transport; report it as what it is.
            if let trustedHostKeyFingerprint, let observed = validator.observedFingerprint, observed != trustedHostKeyFingerprint {
                throw RootShellError.hostKeyMismatch(expected: trustedHostKeyFingerprint, actual: observed)
            }
            let description = String(describing: error)
            let lowered = description.lowercased()
            if lowered.contains("auth") || lowered.contains("allauthenticationoptionsfailed") {
                throw RootShellError.authenticationFailed
            }
            throw RootShellError.connectionFailed(description)
        }
    }
}

enum SSHKeyMaterial {
    /// A fresh Ed25519 private key in raw form, for the Keychain.
    static func generatePrivateKey() -> Data {
        Curve25519.Signing.PrivateKey().rawRepresentation
    }

    /// The `authorized_keys` line for a raw Ed25519 private key.
    static func authorizedKeysLine(forPrivateKey rawKey: Data, comment: String) throws -> String {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
        let algorithm = "ssh-ed25519"
        var blob = Data()
        for field in [Data(algorithm.utf8), key.publicKey.rawRepresentation] {
            var length = UInt32(field.count).bigEndian
            blob.append(Data(bytes: &length, count: 4))
            blob.append(field)
        }
        return "\(algorithm) \(blob.base64EncodedString()) \(comment)"
    }
}
