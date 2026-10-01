import SwiftUI
import SelahBeatCore

/// The code for one service, and what can be done with it.
public struct ShareServiceSheet: View {
    @Bindable private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let serviceID: UUID

    @State private var code: String?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var copied = false

    public init(model: AppModel, serviceID: UUID) {
        self.model = model
        self.serviceID = serviceID
    }

    private var membership: ShareService.Membership? {
        model.shares?.membership(forService: serviceID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Share \(model.library.service(serviceID)?.name ?? "service")")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)

            let shareCode = code ?? membership?.code

            if let shareCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ANYONE WITH THIS CODE CAN EDIT THE SET LIST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)

                    HStack {
                        Text(shareCode)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") { copy(shareCode) }
                            .buttonStyle(.plain)
                            .foregroundStyle(copied ? Theme.running : Theme.accent)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(14)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner))

                Text("They add it in Services, under Join by code. Everyone sees changes as they happen. Only you can rename or delete the service.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                HStack {
                    Button("New code") {
                        run {
                            guard let shares = model.shares else { return }
                            code = try await shares.rotateCode(forService: serviceID,
                                                               token: try await model.syncToken())
                        }
                    }
                    .help("Stops the old code working, without removing anyone already in")

                    Button("Stop sharing", role: .destructive) {
                        run {
                            guard let shares = model.shares else { return }
                            try await shares.stopSharing(serviceId: serviceID,
                                                         token: try await model.syncToken())
                            dismiss()
                        }
                    }
                    Spacer()
                }
                .disabled(busy)
            } else {
                Text("Sharing puts a copy of this set list on the server and gives you a code. Your band mates can add and reorder songs, and set keys and tempos \u{2014} their changes never touch your own library.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)

                Button("Create a code") {
                    run { code = try await model.shareService(serviceID) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Theme.danger)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .sheetSize(width: 460, height: 380)
        .background(Theme.surface)
    }

    private func copy(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        copied = true
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task {
            do { try await work() } catch { errorMessage = describe(error) }
            busy = false
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case SyncClient.Failure.offline: return "No connection to the server."
        case SyncClient.Failure.notFound: return "That share no longer exists."
        default: return "Something went wrong. Try again."
        }
    }
}

/// Starting a service: a new one, or someone else's by code.
///
/// One door rather than two tiles - creating and joining are the same
/// intention ("I need this service on my phone"), and a second tile on the
/// grid made the common case look like a choice.
public struct NewServiceSheet: View {
    @Bindable private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let onReady: (UUID) -> Void

    @State private var name: String
    @State private var code = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    public init(model: AppModel, onReady: @escaping (UUID) -> Void) {
        self.model = model
        self.onReady = onReady
        self._name = State(initialValue: model.library.suggestedServiceName())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Service")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)

            VStack(alignment: .leading, spacing: 10) {
                LabeledTextField("Name", placeholder: "Sunday Morning", text: $name)
                    .focused($nameFocused)
                HStack {
                    Spacer()
                    Button("Create") { create() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if model.shares != nil {
                HStack(spacing: 10) {
                    Rectangle().fill(Theme.secondaryText.opacity(0.25)).frame(height: 1)
                    Text("OR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Rectangle().fill(Theme.secondaryText.opacity(0.25)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabeledTextField("Join by code", placeholder: "XXXX-XXXX-XXXX", text: $code)
                    Text("Someone else's set list, which you can both edit.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    HStack {
                        Spacer()
                        Button("Join") { join() }
                            .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 8)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Theme.danger)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .sheetSize(width: 440, height: 420)
        .background(Theme.surface)
        .onAppear { nameFocused = true }
    }

    private func create() {
        let service = model.library.createService(name: name.trimmingCharacters(in: .whitespaces))
        onReady(service.id)
        dismiss()
    }

    private func join() {
        busy = true
        errorMessage = nil
        Task {
            do {
                let service = try await model.joinService(code: code)
                onReady(service.id)
                dismiss()
            } catch {
                errorMessage = describe(error)
            }
            busy = false
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case SyncClient.Failure.offline: return "No connection to the server."
        case SyncClient.Failure.notFound: return "That code does not match a shared service."
        case SyncClient.Failure.rateLimited: return "Too many tries. Wait a minute and try again."
        default: return "Something went wrong. Try again."
        }
    }
}
