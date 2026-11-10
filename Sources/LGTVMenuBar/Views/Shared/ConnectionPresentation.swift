import SwiftUI

/// How the connection is described to the user, in one place for the menu, Settings and setup.
struct ConnectionPresentation: Equatable {
    enum Tone: Equatable {
        case good, busy, idle, problem

        var color: Color {
            switch self {
            case .good: return .green
            case .busy: return .orange
            case .idle: return .secondary
            case .problem: return .red
            }
        }
    }

    let title: String
    let detail: String?
    /// The symbol differs per state, so status never rests on colour alone.
    let symbolName: String
    let tone: Tone
    let showsProgress: Bool

    static func make(
        state: ConnectionState,
        tvName: String?,
        foreground: TVForeground,
        pairingRequiresUser: Bool,
        isRefreshingPixels: Bool = false
    ) -> ConnectionPresentation {
        guard let tvName else {
            return ConnectionPresentation(title: "No TV set up", detail: "Add your TV in Settings.", symbolName: "tv.slash", tone: .idle, showsProgress: false)
        }

        if isRefreshingPixels, !state.isConnected {
            return ConnectionPresentation(title: tvName, detail: "Off for a pixel refresh", symbolName: "sparkles.tv", tone: .busy, showsProgress: false)
        }

        switch state {
        case .connected:
            let detail: String
            switch foreground {
            case .input(let input): detail = "On \(input.displayName)"
            case .app: detail = "Showing a TV app"
            case .unknown: detail = "Connected"
            }
            return ConnectionPresentation(title: tvName, detail: detail, symbolName: "checkmark.circle.fill", tone: .good, showsProgress: false)
        case .connecting:
            return ConnectionPresentation(title: tvName, detail: "Connecting…", symbolName: "arrow.triangle.2.circlepath", tone: .busy, showsProgress: true)
        case .registering:
            return ConnectionPresentation(title: tvName, detail: "Pairing…", symbolName: "arrow.triangle.2.circlepath", tone: .busy, showsProgress: true)
        case .awaitingPairing:
            return ConnectionPresentation(title: tvName, detail: "Accept the prompt on your TV", symbolName: "hand.tap.fill", tone: .busy, showsProgress: true)
        case .disconnected:
            if pairingRequiresUser {
                return ConnectionPresentation(title: tvName, detail: "Pairing needed. Choose Connect, then accept the prompt on the TV.", symbolName: "exclamationmark.triangle.fill", tone: .problem, showsProgress: false)
            }
            return ConnectionPresentation(title: tvName, detail: "Not connected", symbolName: "moon.zzz.fill", tone: .idle, showsProgress: false)
        case .error(let error):
            return ConnectionPresentation(title: tvName, detail: "Connection lost: \(error.localizedDescription)", symbolName: "exclamationmark.triangle.fill", tone: .problem, showsProgress: false)
        }
    }
}

extension TVController {
    var connectionPresentation: ConnectionPresentation {
        ConnectionPresentation.make(
            state: connectionState,
            tvName: configuration?.name,
            foreground: foreground,
            pairingRequiresUser: pairingRequiresUser,
            isRefreshingPixels: pixelRefreshStartedAt != nil
        )
    }

    /// Inputs to offer in pickers: the TV's own list when known, otherwise the HDMI inputs.
    var inputChoices: [(input: TVInputType, title: String)] {
        let reported: [(TVInputType, String)] = (capabilities?.inputs ?? []).compactMap { info in
            guard let input = TVInputType(rawValue: info.id) else { return nil }
            let label = info.label.trimmingCharacters(in: .whitespaces)
            let title = label.isEmpty || label.caseInsensitiveCompare(input.displayName) == .orderedSame
                ? input.displayName
                : "\(input.displayName) (\(label))"
            return (input, title)
        }
        if !reported.isEmpty {
            return reported.map { (input: $0.0, title: $0.1) }
        }
        return [TVInputType.hdmi1, .hdmi2, .hdmi3, .hdmi4].map { (input: $0, title: $0.displayName) }
    }

    /// A binding that writes one configuration field as soon as it changes.
    func configurationBinding<Value: Equatable>(
        _ keyPath: WritableKeyPath<TVConfiguration, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: { self.configuration?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                do {
                    try self.updateConfiguration { $0[keyPath: keyPath] = newValue }
                } catch {
                    self.diagnosticLogger.log(level: "error", category: "Settings", message: "Could not save setting", metadata: ["error": error.localizedDescription])
                }
            }
        )
    }
}

/// Symbol, name and state of the connection.
struct ConnectionStatusView: View {
    let presentation: ConnectionPresentation
    var titleFont: Font = .headline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if presentation.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.tone.color)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(titleFont)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short message shown in place, instead of an alert, for results and problems.
struct InlineNotice: View {
    enum Kind { case success, warning, failure, info }

    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(color)
        }
        .font(.callout)
    }

    private var symbolName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info: return "info.circle"
        }
    }

    private var color: Color {
        switch kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        case .info: return .secondary
        }
    }
}

/// A labelled text field that saves when editing ends, and only if the value is valid.
///
/// Saving per keystroke would store half-typed addresses; a Save button loses edits when the
/// window closes. Committing on Return or when focus leaves avoids both.
struct CommittedTextField: View {
    let title: String
    let prompt: String
    let value: String
    var validate: (String) -> String? = { _ in nil }
    let commit: (String) -> Void

    @State private var draft = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $draft, prompt: Text(prompt))
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitDraft() }
                }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isFocused { draft = newValue }
        }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        problem = validate(trimmed)
        guard problem == nil, trimmed != value else { return }
        commit(trimmed)
    }
}

/// Explanatory text under a settings section, aligned with the section's leading edge.
struct SectionFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
