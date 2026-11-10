import Foundation

/// Calls the pairing connection is not allowed to make: writing settings and input labels.
///
/// They go through the root shell when one is configured, and otherwise through the
/// notification service, which the TV lets trigger a Luna call (the approach used by bscpylgtv
/// and ColorControl). Reading the picture mode lives here too because it shares the fallback.
@MainActor
final class TVPrivilegedCalls {
    private let client: WebOSClientProtocol
    private let root: RootAccessService
    private let log: (String, String, [String: String]) -> Void

    private static let settingsServiceSSAP = "ssap://settings/getSystemSettings"
    private static let getLuna = "luna://com.webos.settingsservice/getSystemSettings"
    private static let setLuna = "luna://com.webos.settingsservice/setSystemSettings"

    init(client: WebOSClientProtocol, root: RootAccessService, log: @escaping (String, String, [String: String]) -> Void) {
        self.client = client
        self.root = root
        self.log = log
    }

    func readPictureMode() async throws -> String {
        let query: [String: Any] = ["category": "picture", "keys": ["pictureMode"]]

        do {
            let reply = try await client.request(uri: Self.settingsServiceSSAP, payload: query)
            if let mode = reply.dictionary("settings")?["pictureMode"] as? String {
                return mode
            }
            log("warning", "Picture mode missing from settings reply", ["reply": reply.jsonString])
        } catch {
            log("info", "Picture mode not readable over the pairing connection", ["error": error.localizedDescription])
            guard root.isUsable else { throw error }
        }

        guard root.isUsable else {
            throw LGTVError.invalidResponse
        }
        let reply = try await root.luna(Self.getLuna, parameters: query)
        guard let mode = (reply["settings"] as? [String: Any])?["pictureMode"] as? String else {
            throw LGTVError.invalidResponse
        }
        return mode
    }

    func setPictureMode(_ mode: String) async throws {
        try await invokePrivileged(Self.setLuna, parameters: ["category": "picture", "settings": ["pictureMode": mode]])
    }

    /// Calls a Luna service the pairing connection is not allowed to call directly (it answers
    /// "401 insufficient permissions"): through the root shell when there is one, otherwise by
    /// having the TV's notification service make the call.
    func invokePrivileged(_ lunaURI: String, parameters: [String: Any]) async throws {
        if root.isUsable {
            do {
                let reply = try await root.luna(lunaURI, parameters: parameters)
                guard reply["returnValue"] as? Bool == true else {
                    throw LGTVError.commandFailed("The TV refused the request (\(lunaURI))")
                }
                log("info", "Privileged call made through the root shell", ["uri": lunaURI])
                return
            } catch let error as LGTVError {
                throw error
            } catch {
                // The shell being down must not take the feature with it.
                log("warning", "Root shell unavailable for privileged call; using the notification service", ["uri": lunaURI, "error": error.localizedDescription])
            }
        }

        let action: [String: Any] = ["uri": lunaURI, "params": parameters]
        let alert = try await client.request(uri: "ssap://system.notifications/createAlert", payload: [
            "message": " ",
            "buttons": [["label": "", "onClick": lunaURI, "params": parameters]],
            "onclose": action,
            "onfail": action
        ])
        guard let alertId = alert.string("alertId") else {
            throw LGTVError.commandFailed("The TV did not accept the request (\(lunaURI))")
        }
        _ = try await client.request(uri: "ssap://system.notifications/closeAlert", payload: ["alertId": alertId])
        log("info", "Privileged call made through the notification service", ["uri": lunaURI])
    }
}
