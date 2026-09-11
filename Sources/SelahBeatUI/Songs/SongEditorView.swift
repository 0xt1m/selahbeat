import SwiftUI
import QuartzCore
import SelahBeatCore

/// Create or edit a song. Tempo can be tapped in rather than typed, which is
/// how a drummer actually knows a tempo.
public struct SongEditorView: View {
    @Bindable private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Song
    @State private var tapTempo = TapTempo()
    private let isNew: Bool
    private let onSave: (Song) -> Void

    public init(model: AppModel, song: Song, isNew: Bool = false, onSave: @escaping (Song) -> Void) {
        self.model = model
        self._draft = State(initialValue: song)
        self.isNew = isNew
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "New Song" : "Edit Song")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    TextField("Artist (optional)", text: Binding(
                        get: { draft.artist ?? "" },
                        set: { draft.artist = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Tempo") {
                    HStack(spacing: 14) {
                        // Typed entry: most of the time you already know the
                        // tempo, and typing beats holding a stepper.
                        TextField("BPM", value: $draft.defaultBPM, format: .number)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.tempoFont(size: 24))
                            .frame(width: 92)
                            .onChange(of: draft.defaultBPM) { _, newValue in
                                let clamped = Song.clampBPM(newValue)
                                if clamped != newValue { draft.defaultBPM = clamped }
                            }
                        Stepper("", value: $draft.defaultBPM, in: Song.minBPM...Song.maxBPM, step: 1)
                            .labelsHidden()
                        InstantButton {
                            if let bpm = tapTempo.tap(at: CACurrentMediaTime()) {
                                draft.defaultBPM = bpm.rounded()
                            }
                        } label: {
                            Text("TAP")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .frame(width: 68, height: 38)
                                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))
                        }
                        Spacer()
                    }
                }

                Section("Meter and key") {
                    Picker("Time signature", selection: $draft.defaultTimeSignature) {
                        ForEach(TimeSignature.common, id: \.self) { Text($0.display).tag($0) }
                    }
                    Picker("Key", selection: Binding(
                        get: { draft.defaultKey?.asciiDisplay ?? "" },
                        set: { draft.defaultKey = $0.isEmpty ? nil : MusicalKey.parse($0) }
                    )) {
                        Text("None").tag("")
                        ForEach(MusicalKey.common) { key in
                            Text(key.display).tag(key.asciiDisplay)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew, model.library.song(draft.id) != nil {
                    let uses = model.library.usageCount(of: draft.id)
                    Button("Delete", role: .destructive) {
                        model.library.deleteSong(draft.id)
                        dismiss()
                    }
                    .help(uses > 0 ? "Used in \(uses) service\(uses == 1 ? "" : "s")" : "Not used in any service")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .sheetSize(width: 460, height: 520)
    }
}
