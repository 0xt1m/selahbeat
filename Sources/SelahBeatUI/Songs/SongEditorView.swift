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

    private func mixSlider(_ label: String, _ key: WritableKeyPath<SongMix, Double>) -> some View {
        let binding = Binding<Double>(
            get: { draft.mix?[keyPath: key] ?? 0 },
            set: { newValue in
                var mix = draft.mix ?? .standard
                mix[keyPath: key] = newValue
                draft.mix = mix
            }
        )
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(binding.wrappedValue == 0 ? "muted"
                     : "\(Int(binding.wrappedValue / 2.0 * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(binding.wrappedValue == 0 ? Theme.warning : Theme.secondaryText)
            }
            Slider(value: binding, in: 0...2).tint(Theme.accent)
        }
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

                Section("Click mix") {
                    Toggle("Custom mix for this song", isOn: Binding(
                        get: { draft.mix != nil },
                        set: { on in
                            // Seed from whatever is currently set up, so the
                            // starting point is what you were just listening to.
                            draft.mix = on ? model.metronome.currentMix : nil
                        }
                    ))

                    if draft.mix != nil {
                        mixSlider("Accent", \.accent)
                        mixSlider("Quarter notes", \.quarter)
                        mixSlider("Eighth notes", \.eighth)
                        mixSlider("Sixteenth notes", \.sixteenth)

                        Button("Preview this mix") {
                            if let mix = draft.mix { model.metronome.apply(mix) }
                        }
                    } else {
                        Text("This song will use whatever the mix is set to.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    NotesField("Anything worth remembering", text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    ))
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
