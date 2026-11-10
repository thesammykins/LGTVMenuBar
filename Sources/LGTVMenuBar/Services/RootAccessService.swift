import Foundation
import Observation

/// What the root shell reported about the TV.
public struct RootCapabilities: Equatable, Sendable {
    public var uid: String
    public var kernel: String
    public var hasLunaSend: Bool
    public var pictureMode: String?
    public var powerState: String?
    /// Platform model, e.g. "HE_DTV_W22O_AFABATAA".
    public var platformModel: String?
    /// e.g. "webOSTV 7.0".
    public var productName: String?
    public var firmwareVersion: String?

    public init(uid: String = "", kernel: String = "", hasLunaSend: Bool = false, pictureMode: String? = nil, powerState: String? = nil) {
        self.uid = uid
        self.kernel = kernel
        self.hasLunaSend = hasLunaSend
        self.pictureMode = pictureMode
        self.powerState = powerState
    }

    public var isRoot: Bool { uid == "0" }
}

/// Optional shell access to a TV the owner has rooted.
///
/// Everything here degrades to "unavailable": no feature may depend on root without a fallback.
/// Secrets stay in the Keychain; the configuration only says which kind of secret to use.
@MainActor
@Observable
public final class RootAccessService {
    public enum Status: Equatable, Sendable {
        case disabled
        case notChecked
        case checking
        case available(RootCapabilities)
        case failed(String)
    }

    public private(set) var status: Status = .disabled
    public private(set) var lastCheckedAt: Date?

    @ObservationIgnored private let keychain: KeychainManagerProtocol
    @ObservationIgnored private let shells: [RootAccessSettings.Transport: any RootShellRunning]

    /// Supplies the current configuration; set by the owner.
    @ObservationIgnored var configurationProvider: () -> TVConfiguration? = { nil }
    /// Called with the SSH host key fingerprint the first time a TV is contacted.
    @ObservationIgnored var trustHostKey: (String) -> Void = { _ in }
    @ObservationIgnored var log: (String, String, [String: String]) -> Void = { _, _, _ in }

    public init(
        keychain: KeychainManagerProtocol,
        shells: [RootAccessSettings.Transport: any RootShellRunning] = [.ssh: SSHRootShell(), .telnet: TelnetRootShell()]
    ) {
        self.keychain = keychain
        self.shells = shells
    }

    /// Worth trying: enabled and not known to be broken. Root is used on this basis rather than
    /// only after a successful test, so it keeps working across relaunches.
    public var isUsable: Bool {
        switch status {
        case .available, .notChecked, .checking: return true
        case .disabled, .failed: return false
        }
    }

    public var capabilities: RootCapabilities? {
        if case .available(let capabilities) = status { return capabilities }
        return nil
    }

    /// Brings `status` in line with the configuration after it changes.
    public func configurationDidChange() {
        guard let config = configurationProvider(), config.rootAccess.isEnabled else {
            status = .disabled
            return
        }
        if status == .disabled {
            status = .notChecked
        }
    }

    // MARK: - Secrets

    private func keyAccount(_ config: TVConfiguration) -> String { "ssh-key.\(config.id.uuidString)" }
    private func passwordAccount(_ config: TVConfiguration) -> String { "password.\(config.id.uuidString)" }

    public func hasAppKey(for config: TVConfiguration) -> Bool {
        ((try? keychain.loadSecret(account: keyAccount(config))) ?? nil) != nil
    }

    public func hasPassword(for config: TVConfiguration) -> Bool {
        ((try? keychain.loadSecret(account: passwordAccount(config))) ?? nil) != nil
    }

    /// The `authorized_keys` line for the app's key, creating the key on first use.
    @discardableResult
    public func ensureAppKey(for config: TVConfiguration) throws -> String {
        let account = keyAccount(config)
        let rawKey: Data
        if let existing = try keychain.loadSecret(account: account) {
            rawKey = existing
        } else {
            rawKey = SSHKeyMaterial.generatePrivateKey()
            try keychain.saveSecret(rawKey, account: account)
            log("info", "Generated SSH key for root access", [:])
        }
        return try SSHKeyMaterial.authorizedKeysLine(forPrivateKey: rawKey, comment: "LGTVMenuBar")
    }

    public func setPassword(_ password: String, for config: TVConfiguration) throws {
        if password.isEmpty {
            try keychain.deleteSecret(account: passwordAccount(config))
        } else {
            try keychain.saveSecret(Data(password.utf8), account: passwordAccount(config))
        }
    }

    public func forgetSecrets(for config: TVConfiguration) {
        try? keychain.deleteSecret(account: keyAccount(config))
        try? keychain.deleteSecret(account: passwordAccount(config))
        log("warning", "Root access secrets removed from the Keychain", [:])
    }

    private func credential(for config: TVConfiguration) throws -> RootShellCredential {
        let settings = config.rootAccess
        switch settings.authentication {
        case .password:
            if let data = try keychain.loadSecret(account: passwordAccount(config)), let password = String(data: data, encoding: .utf8) {
                return .password(password)
            }
            if settings.transport == .telnet {
                return .none
            }
            throw RootShellError.notConfigured("Enter the TV's shell password first.")
        case .appKey:
            if settings.transport == .telnet {
                return .none
            }
            guard let key = try keychain.loadSecret(account: keyAccount(config)) else {
                throw RootShellError.notConfigured("Install the app's key on the TV first.")
            }
            return .ed25519PrivateKey(key)
        }
    }

    // MARK: - Running Commands

    /// Runs a command on the TV as configured. Throws when root access is off or fails.
    @discardableResult
    public func run(_ command: String, timeout: Duration = .seconds(15), credentialOverride: RootShellCredential? = nil) async throws -> RootShellOutput {
        guard let config = configurationProvider() else {
            throw RootShellError.notConfigured("No TV is configured.")
        }
        let settings = config.rootAccess
        guard settings.isEnabled else {
            throw RootShellError.notConfigured("Root access is turned off.")
        }
        guard let shell = shells[settings.transport] else {
            throw RootShellError.notConfigured("\(settings.transport.displayName) is not available.")
        }

        let endpoint = RootShellEndpoint(
            host: settings.effectiveHost(tvAddress: config.ipAddress),
            port: settings.effectivePort,
            username: settings.username.isEmpty ? "root" : settings.username
        )
        let credential = try credentialOverride ?? credential(for: config)
        let started = ContinuousClock.now

        do {
            let result = try await shell.run(
                command,
                endpoint: endpoint,
                credential: credential,
                trustedHostKeyFingerprint: settings.trustedHostKeyFingerprint,
                timeout: timeout
            )

            if settings.trustedHostKeyFingerprint == nil, let fingerprint = result.hostKeyFingerprint {
                log("warning", "Trusting the TV's SSH host key on first use", ["fingerprint": fingerprint, "host": endpoint.host])
                trustHostKey(fingerprint)
            }

            log("info", "Root command finished", [
                "transport": settings.transport.rawValue,
                "host": endpoint.host,
                "exitStatus": result.exitStatus.map(String.init) ?? "unknown",
                "elapsed": "\(started.duration(to: .now))",
                "command": String(command.prefix(160)),
                "output": String(result.output.prefix(600))
            ])
            return result
        } catch {
            log("error", "Root command failed", [
                "transport": settings.transport.rawValue,
                "host": endpoint.host,
                "command": String(command.prefix(160)),
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    /// Calls a Luna service on the TV with `luna-send` and returns the decoded reply.
    public func luna(_ uri: String, parameters: [String: Any] = [:]) async throws -> [String: Any] {
        guard uri.range(of: #"^luna://[A-Za-z0-9._/\-]+$"#, options: .regularExpression) != nil else {
            throw RootShellError.notConfigured("Refusing to call a malformed Luna address.")
        }
        guard JSONSerialization.isValidJSONObject(parameters),
              let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            throw RootShellError.notConfigured("The Luna parameters could not be encoded.")
        }

        let command = "luna-send -n 1 \(RootShellFraming.shellQuote(uri)) \(RootShellFraming.shellQuote(json))"
        let result = try await run(command)
        guard result.exitStatus == 0 else {
            throw RootShellError.commandFailed(status: result.exitStatus ?? -1, output: result.output)
        }
        guard let replyData = result.output.data(using: .utf8),
              let reply = try? JSONSerialization.jsonObject(with: replyData) as? [String: Any] else {
            throw RootShellError.malformedOutput(String(result.output.prefix(200)))
        }
        return reply
    }

    // MARK: - Probing

    static let probeCommand = [
        #"echo "uid=$(id -u)""#,
        #"echo "kernel=$(uname -r)""#,
        #"echo "luna=$(command -v luna-send >/dev/null 2>&1 && echo yes || echo no)""#,
        #"echo "picture=$(luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{"category":"picture","keys":["pictureMode"]}' 2>/dev/null)""#,
        #"echo "power=$(luna-send -n 1 luna://com.webos.service.tvpower/power/getPowerState '{}' 2>/dev/null)""#,
        #"echo "software=$(luna-send -n 1 luna://com.webos.service.update/getCurrentSWInformation '{}' 2>/dev/null)""#
    ].joined(separator: "; ")

    static func parseProbe(_ output: String) -> RootCapabilities {
        var capabilities = RootCapabilities()
        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator]
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "uid": capabilities.uid = value
            case "kernel": capabilities.kernel = value
            case "luna": capabilities.hasLunaSend = value == "yes"
            case "picture":
                if let json = jsonObject(value), let settings = json["settings"] as? [String: Any] {
                    capabilities.pictureMode = settings["pictureMode"] as? String
                }
            case "power":
                if let json = jsonObject(value) {
                    capabilities.powerState = json["state"] as? String
                }
            case "software":
                if let json = jsonObject(value) {
                    capabilities.platformModel = json["model_name"] as? String
                    capabilities.productName = json["product_name"] as? String
                    let version = [json["major_ver"] as? String, json["minor_ver"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
                    capabilities.firmwareVersion = version.isEmpty ? nil : version.joined(separator: ".")
                }
            default:
                break
            }
        }
        return capabilities
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Connects, checks that the shell really is root on a webOS TV, and records what it offers.
    @discardableResult
    public func refresh(credentialOverride: RootShellCredential? = nil) async -> Status {
        guard let config = configurationProvider(), config.rootAccess.isEnabled else {
            status = .disabled
            return status
        }

        status = .checking
        do {
            let result = try await run(Self.probeCommand, credentialOverride: credentialOverride)
            let capabilities = Self.parseProbe(result.output)
            lastCheckedAt = Date()

            if capabilities.uid.isEmpty {
                status = .failed("The shell answered, but not like a TV. Check the address and port.")
            } else if !capabilities.isRoot {
                status = .failed("Connected as user id \(capabilities.uid), not root.")
            } else {
                status = .available(capabilities)
            }
        } catch {
            lastCheckedAt = Date()
            status = .failed(error.localizedDescription)
        }
        return status
    }

    /// The OLED panel's maintenance state. Throws when the TV has no panel-care service.
    public func panelCareStatus() async throws -> PanelCareStatus {
        let result = try await run(PanelCareStatus.queryCommand)
        guard let status = PanelCareStatus.parse(result.output) else {
            throw RootShellError.malformedOutput("The TV did not report panel-care information.")
        }
        return status
    }

    /// The TV's inputs as its input manager reports them, including which is labelled a PC.
    public func inputList() async throws -> [TVInputInfo] {
        let reply = try await luna("luna://com.webos.service.eim/getAllInputStatus")
        guard let devices = reply["devices"] as? [[String: Any]] else {
            throw RootShellError.malformedOutput("The TV did not report its inputs.")
        }
        return devices.compactMap { device in
            guard let id = device["id"] as? String else { return nil }
            return TVInputInfo(
                id: id,
                label: device["label"] as? String ?? id,
                icon: device["icon"] as? String ?? "",
                isConnected: device["connected"] as? Bool ?? false
            )
        }
    }

    /// Adds the app's public key to the TV's `authorized_keys` using a one-off password login.
    /// The password is used for this connection only and is not stored.
    public func installAppKey(usingPassword password: String) async throws {
        guard let config = configurationProvider() else {
            throw RootShellError.notConfigured("No TV is configured.")
        }
        let line = try ensureAppKey(for: config)
        let quoted = RootShellFraming.shellQuote(line)
        let command = [
            "mkdir -p /home/root/.ssh",
            "chmod 700 /home/root/.ssh",
            "touch /home/root/.ssh/authorized_keys",
            "(grep -qxF \(quoted) /home/root/.ssh/authorized_keys || echo \(quoted) >> /home/root/.ssh/authorized_keys)",
            "chmod 600 /home/root/.ssh/authorized_keys"
        ].joined(separator: " && ")

        let override: RootShellCredential = config.rootAccess.transport == .telnet && password.isEmpty ? .none : .password(password)
        let result = try await run(command, credentialOverride: override)
        guard result.exitStatus == 0 else {
            throw RootShellError.commandFailed(status: result.exitStatus ?? -1, output: result.output)
        }
        log("warning", "Installed the app's SSH key on the TV", [:])
    }
}
