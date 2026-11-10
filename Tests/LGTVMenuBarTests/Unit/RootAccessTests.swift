import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("Root shell framing")
struct RootShellFramingTests {
    @Test("output and status are extracted from a clean stream")
    func cleanStream() {
        let stream = "__LGTV_BEGIN_AB12__\nline one\nline two\n__LGTV_DONE_AB12_0__\n"
        let result = RootShellFraming.extract(from: stream, nonce: "AB12")
        #expect(result?.output == "line one\nline two")
        #expect(result?.status == 0)
    }

    @Test("the echoed command line is not mistaken for output")
    func echoedCommand() {
        let command = RootShellFraming.wrap("id -u", nonce: "AB12")
        let stream = "# \(command)\r\n__LGTV_BEGIN_AB12__\r\n0\r\n__LGTV_DONE_AB12_3__\r\n# "
        let result = RootShellFraming.extract(from: stream, nonce: "AB12")
        #expect(result?.output == "0")
        #expect(result?.status == 3)
    }

    @Test("nothing is returned until the completion marker arrives")
    func incomplete() {
        #expect(RootShellFraming.extract(from: "__LGTV_BEGIN_AB12__\npartial", nonce: "AB12") == nil)
        #expect(RootShellFraming.extract(from: RootShellFraming.wrap("id", nonce: "AB12"), nonce: "AB12") == nil)
    }

    @Test("shell quoting neutralises single quotes")
    func quoting() {
        #expect(RootShellFraming.shellQuote("plain") == "'plain'")
        #expect(RootShellFraming.shellQuote("it's; rm -rf /") == "'it'\\''s; rm -rf /'")
    }

    @Test("an Ed25519 key produces a well-formed authorized_keys line")
    func authorizedKeysLine() throws {
        let line = try SSHKeyMaterial.authorizedKeysLine(forPrivateKey: SSHKeyMaterial.generatePrivateKey(), comment: "LGTVMenuBar")
        let parts = line.split(separator: " ")
        #expect(parts.count == 3)
        #expect(parts[0] == "ssh-ed25519")
        // Every Ed25519 public key blob starts with the same length-prefixed algorithm name.
        #expect(parts[1].hasPrefix("AAAAC3NzaC1lZDI1NTE5AAAAI"))
        #expect(Data(base64Encoded: String(parts[1]))?.count == 51)
        #expect(parts[2] == "LGTVMenuBar")
    }
}

@Suite("RootAccessService")
@MainActor
struct RootAccessServiceTests {
    private static let rootProbe = """
    uid=0
    kernel=5.4.96
    luna=yes
    picture={"category":"picture","settings":{"pictureMode":"game"},"returnValue":true}
    power={"state":"Active","returnValue":true}
    """

    private final class Box { var config: TVConfiguration; var trusted: [String] = []; init(_ config: TVConfiguration) { self.config = config } }

    private func makeService(
        _ settings: RootAccessSettings,
        shell: FakeRootShell = FakeRootShell(),
        keychain: MockKeychainManager = MockKeychainManager()
    ) -> (RootAccessService, FakeRootShell, Box, MockKeychainManager) {
        var config = TVConfiguration(name: "TV", ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:DD:EE:FF")
        config.rootAccess = settings
        let box = Box(config)
        let service = RootAccessService(keychain: keychain, shells: [.ssh: shell, .telnet: shell])
        service.configurationProvider = { box.config }
        service.trustHostKey = { fingerprint in
            box.trusted.append(fingerprint)
            box.config.rootAccess.trustedHostKeyFingerprint = fingerprint
        }
        service.configurationDidChange()
        return (service, shell, box, keychain)
    }

    @Test("probe output is parsed into capabilities")
    func parseProbe() {
        let capabilities = RootAccessService.parseProbe(Self.rootProbe)
        #expect(capabilities == RootCapabilities(uid: "0", kernel: "5.4.96", hasLunaSend: true, pictureMode: "game", powerState: "Active"))
        #expect(capabilities.isRoot)
    }

    @Test("a probe with missing or broken fields still parses what it can")
    func parsePartialProbe() {
        let capabilities = RootAccessService.parseProbe("uid=1000\nluna=no\npicture=\npower=not json")
        #expect(capabilities.uid == "1000")
        #expect(!capabilities.isRoot)
        #expect(capabilities.pictureMode == nil)
        #expect(capabilities.powerState == nil)
    }

    @Test("root access that is switched off never opens a shell")
    func disabledNeverConnects() async {
        let (service, shell, _, _) = makeService(RootAccessSettings(isEnabled: false))
        #expect(service.status == .disabled)
        await #expect(throws: RootShellError.self) { try await service.run("id") }
        #expect(await service.refresh() == .disabled)
        #expect(shell.calls.isEmpty)
    }

    @Test("a working root shell is reported as available")
    func refreshAvailable() async throws {
        let (service, shell, config, keychain) = makeService(RootAccessSettings(isEnabled: true, authentication: .password))
        try keychain.saveSecret(Data("alpine".utf8), account: "password.\(config.config.id.uuidString)")
        shell.setHandler { _ in RootShellOutput(output: Self.rootProbe, exitStatus: 0) }

        let status = await service.refresh()

        #expect(status == .available(RootCapabilities(uid: "0", kernel: "5.4.96", hasLunaSend: true, pictureMode: "game", powerState: "Active")))
        #expect(shell.calls.first?.endpoint == RootShellEndpoint(host: "10.0.0.2", port: 22, username: "root"))
        #expect(shell.calls.first?.credential == .password("alpine"))
    }

    @Test("a shell that is not root is reported as a failure")
    func refreshNotRoot() async throws {
        let (service, shell, config, keychain) = makeService(RootAccessSettings(isEnabled: true, authentication: .password))
        try keychain.saveSecret(Data("x".utf8), account: "password.\(config.config.id.uuidString)")
        shell.setHandler { _ in RootShellOutput(output: "uid=5001\nkernel=5.4\nluna=yes", exitStatus: 0) }

        #expect(await service.refresh() == .failed("Connected as user id 5001, not root."))
    }

    @Test("SSH without a key or password fails before connecting")
    func missingCredentials() async {
        let (service, shell, _, _) = makeService(RootAccessSettings(isEnabled: true, authentication: .appKey))
        guard case .failed = await service.refresh() else {
            Issue.record("expected a failure")
            return
        }
        #expect(shell.calls.isEmpty)
    }

    @Test("Telnet runs without a credential and honours host and port overrides")
    func telnetEndpoint() async throws {
        let settings = RootAccessSettings(isEnabled: true, transport: .telnet, hostOverride: "10.0.0.50", port: 2323, username: "admin")
        let (service, shell, _, _) = makeService(settings)
        try await service.run("id -u")
        #expect(shell.calls.first?.endpoint == RootShellEndpoint(host: "10.0.0.50", port: 2323, username: "admin"))
        #expect(shell.calls.first?.credential == RootShellCredential.none)
    }

    @Test("the first SSH host key is trusted once and then pinned")
    func trustOnFirstUse() async throws {
        let (service, shell, box, keychain) = makeService(RootAccessSettings(isEnabled: true, authentication: .password))
        try keychain.saveSecret(Data("x".utf8), account: "password.\(box.config.id.uuidString)")
        shell.setHandler { _ in RootShellOutput(output: "", exitStatus: 0, hostKeyFingerprint: "SHA256:abc") }

        try await service.run("true")
        try await service.run("true")

        #expect(box.trusted == ["SHA256:abc"])
        #expect(shell.calls[0].trustedHostKeyFingerprint == nil)
        #expect(shell.calls[1].trustedHostKeyFingerprint == "SHA256:abc")
    }

    @Test("Luna calls are quoted and their replies decoded")
    func lunaCall() async throws {
        let (service, shell, _, _) = makeService(RootAccessSettings(isEnabled: true, transport: .telnet))
        shell.setHandler { _ in RootShellOutput(output: #"{"returnValue":true,"settings":{"pictureMode":"game"}}"#, exitStatus: 0) }

        let reply = try await service.luna("luna://com.webos.settingsservice/getSystemSettings", parameters: ["category": "picture", "note": "it's"])

        #expect((reply["settings"] as? [String: Any])?["pictureMode"] as? String == "game")
        #expect(shell.calls.first?.command == #"luna-send -n 1 'luna://com.webos.settingsservice/getSystemSettings' '{"category":"picture","note":"it'\''s"}'"#)
    }

    @Test("a malformed Luna address is refused without touching the TV")
    func lunaRejectsInjection() async {
        let (service, shell, _, _) = makeService(RootAccessSettings(isEnabled: true, transport: .telnet))
        await #expect(throws: RootShellError.self) {
            _ = try await service.luna("luna://x'; reboot; echo '")
        }
        #expect(shell.calls.isEmpty)
    }

    @Test("installing the app key logs in with the one-off password and appends the public key")
    func installAppKey() async throws {
        let (service, shell, box, keychain) = makeService(RootAccessSettings(isEnabled: true, authentication: .appKey))

        try await service.installAppKey(usingPassword: "alpine")

        let call = try #require(shell.calls.first)
        #expect(call.credential == .password("alpine"))
        #expect(call.command.contains("/home/root/.ssh/authorized_keys"))
        #expect(call.command.contains("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5"))
        #expect(service.hasAppKey(for: box.config))
        // The password was for that one connection only.
        #expect(try keychain.loadSecret(account: "password.\(box.config.id.uuidString)") == nil)

        try await service.run("true")
        guard case .ed25519PrivateKey = shell.calls[1].credential else {
            Issue.record("expected key authentication after installing the key")
            return
        }
    }

    @Test("forgetting secrets removes both the key and the password")
    func forgetSecrets() throws {
        let (service, _, box, _) = makeService(RootAccessSettings(isEnabled: true))
        try service.ensureAppKey(for: box.config)
        try service.setPassword("pw", for: box.config)
        #expect(service.hasAppKey(for: box.config) && service.hasPassword(for: box.config))

        service.forgetSecrets(for: box.config)
        #expect(!service.hasAppKey(for: box.config) && !service.hasPassword(for: box.config))
    }
}

@Suite("TelnetRootShell against a loopback server", .serialized)
struct TelnetRootShellTests {
    @Test("runs a command on an unauthenticated shell and strips negotiation, banner and echo")
    func unauthenticated() async throws {
        let server = FakeTelnetServer(commandOutput: "0")
        try await server.start()
        defer { server.stop() }

        let result = try await TelnetRootShell().run(
            "id -u",
            endpoint: RootShellEndpoint(host: "127.0.0.1", port: server.port, username: "root"),
            credential: .none,
            trustedHostKeyFingerprint: nil,
            timeout: .seconds(8)
        )
        #expect(result == RootShellOutput(output: "0", exitStatus: 0))
    }

    @Test("answers login and password prompts and reports the exit status")
    func withLogin() async throws {
        let server = FakeTelnetServer(requiredPassword: "alpine", commandOutput: "not found", exitStatus: 127)
        try await server.start()
        defer { server.stop() }

        let result = try await TelnetRootShell().run(
            "nosuchcommand",
            endpoint: RootShellEndpoint(host: "127.0.0.1", port: server.port, username: "root"),
            credential: .password("alpine"),
            trustedHostKeyFingerprint: nil,
            timeout: .seconds(8)
        )
        #expect(result.output == "not found")
        #expect(result.exitStatus == 127)
    }

    @Test("a password prompt without a password is an authentication failure")
    func missingPassword() async throws {
        let server = FakeTelnetServer(requiredPassword: "alpine")
        try await server.start()
        defer { server.stop() }

        await #expect(throws: RootShellError.authenticationFailed) {
            _ = try await TelnetRootShell().run(
                "id",
                endpoint: RootShellEndpoint(host: "127.0.0.1", port: server.port, username: "root"),
                credential: .none,
                trustedHostKeyFingerprint: nil,
                timeout: .seconds(8)
            )
        }
    }

    @Test("an unreachable port fails instead of hanging")
    func unreachable() async {
        await #expect(throws: RootShellError.self) {
            _ = try await TelnetRootShell().run(
                "id",
                endpoint: RootShellEndpoint(host: "127.0.0.1", port: 1, username: "root"),
                credential: .none,
                trustedHostKeyFingerprint: nil,
                timeout: .seconds(3)
            )
        }
    }
}
