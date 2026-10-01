import SwiftUI
import UniformTypeIdentifiers
import SelahBeatCore

/// A library file, for exporting and importing.
struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var archive: LibraryArchive

    init(archive: LibraryArchive) { self.archive = archive }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = try LibraryArchive.read(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try archive.data())
    }
}

/// Backup, restore and the recovery code.
///
/// Deliberately plain about what it does and does not do: this is the screen
/// someone reads at the moment they have lost a phone.
public struct BackupView: View {
    @Bindable private var model: AppModel

    @State private var busy = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var restoreCode = ""
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingRestore = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if model.backup == nil {
                Section {
                    Text("No server is set, so there is nothing to back up to. The file below still works.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            accountSection
            fileSection

            if let message {
                Section { Text(message).font(.caption).foregroundStyle(Theme.running) }
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.caption).foregroundStyle(Theme.danger) }
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.dark)
        .fileExporter(isPresented: $showingExporter,
                      document: LibraryDocument(archive: model.library.archive()),
                      contentType: .json,
                      defaultFilename: model.library.archive().suggestedFilename) { result in
            switch result {
            case .success(let url): report("Saved to \(url.lastPathComponent)")
            case .failure(let error): fail(error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url): importArchive(at: url)
            case .failure(let error): fail(error.localizedDescription)
            }
        }
    }

    private var accountSection: some View {
        Section {
            if let backup = model.backup {
                HStack {
                    Text("Backup")
                    Spacer()
                    Text(backup.isRegistered ? "On" : "Not set up yet")
                        .foregroundStyle(.secondary)
                }

                if let lastSync = backup.lastSync {
                    HStack {
                        Text("Last backed up")
                        Spacer()
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Button(backup.isRegistered ? "Back up now" : "Start backing up") {
                    run { _ = try await backup.syncNow() ; report("Library backed up") }
                }
                .disabled(busy)

                if let code = backup.recoveryCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECOVERY CODE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                        Text(code)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.accent)
                        Text("Write this down. It is the only way back to your songs on a new phone, and nobody can look it up for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if backup.isRegistered {
                    Button("Show a recovery code") {
                        run { _ = try await backup.refreshRecoveryCode() }
                    }
                    .disabled(busy)
                }

                Button("Restore from another device\u{2026}") { showingRestore = true }
                    .disabled(busy)

                if showingRestore {
                    LabeledTextField("Recovery code", placeholder: "XXXX-XXXX-XXXX", text: $restoreCode)
                    Button("Restore") {
                        run {
                            let summary = try await backup.restore(withCode: restoreCode)
                            restoreCode = ""
                            showingRestore = false
                            report(summary.summary)
                        }
                    }
                    .disabled(busy || restoreCode.count < 8)
                }
            }
        } header: {
            Text("This device")
        } footer: {
            Text("Backup needs no account: your songs are stored under a random id that only this device knows. The recovery code is what moves it to a new phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fileSection: some View {
        Section {
            Button("Export a backup file\u{2026}") { showingExporter = true }
            Button("Import a backup file\u{2026}") { showingImporter = true }
        } header: {
            Text("File")
        } footer: {
            Text("A .selahbeat file holds every song and service. It needs no network and keeps working whatever happens to the server. Importing never overwrites: anything already here is left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func importArchive(at url: URL) {
        // A file chosen outside the app's own container is only readable while
        // its security scope is open.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let archive = try LibraryArchive.read(from: try Data(contentsOf: url))
            report(model.library.importArchive(archive).summary)
        } catch {
            fail("That file could not be read as a SelahBeat backup.")
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task {
            do { try await work() } catch { fail(describe(error)) }
            busy = false
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case SyncClient.Failure.offline: return "No connection to the server."
        case SyncClient.Failure.notFound: return "That code does not match an account."
        case SyncClient.Failure.rateLimited(let seconds):
            return "Too many attempts. Try again in \(max(1, seconds / 60)) minutes."
        default: return "Something went wrong. Try again."
        }
    }

    private func report(_ text: String) {
        message = text
        errorMessage = nil
    }

    private func fail(_ text: String) {
        errorMessage = text
        message = nil
    }
}
