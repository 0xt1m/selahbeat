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

    /// The common meters, plus whatever this song already uses if it is not
    /// among them - otherwise editing a 7/4 song would show a blank picker and
    /// silently rewrite the meter on save.
    private var meterOptions: [TimeSignature] {
        var options = TimeSignature.common
        if !options.contains(draft.defaultTimeSignature) {
            options.append(draft.defaultTimeSignature)
        }
        return options
    }

    private func mixSlider(_ label: String, _ key: WritableKeyPath<SongMix, Double>) -> some View {
        let binding = Binding<Double>(
            // A song saved before mixes existed has none stored, and it plays
            // at the standard one - so that is what the sliders must show.
            // Reading a missing mix as zero made every such song look muted.
            get: { (draft.mix ?? .standard)[keyPath: key] },
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
                    LabeledTextField("Title", placeholder: "Song title", text: $draft.title)
                    LabeledTextField("Artist", placeholder: "Optional", text: Binding(
                        get: { draft.artist ?? "" },
                        set: { draft.artist = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Tempo") {
                    HStack(spacing: 14) {
                        BPMField(bpm: $draft.defaultBPM)
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
                    // Tagged by display string rather than by the struct itself:
                    // SwiftUI matches struct tags unreliably when the selection
                    // binds through a nested property of a @State value, which
                    // left this picker refusing to change.
                    Picker("Time signature", selection: Binding(
                        get: { draft.defaultTimeSignature.display },
                        set: { chosen in
                            if let match = meterOptions.first(where: { $0.display == chosen }) {
                                draft.defaultTimeSignature = match
                            }
                        }
                    )) {
                        ForEach(meterOptions, id: \.display) { meter in
                            Text(meter.display).tag(meter.display)
                        }
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

                    // Off unless asked for: a pad under a song that does not
                    // want one is worse than no pad at all.
                    Toggle("Play a pad for this song", isOn: Binding(
                        get: { draft.padEnabled ?? false },
                        set: { draft.padEnabled = $0 ? true : nil }
                    ))

                    if draft.padEnabled == true {
                        Picker("Pad sound", selection: Binding(
                            get: { (draft.padSound ?? model.metronome.padSound).rawValue },
                            set: { draft.padSound = PadSound(rawValue: $0) }
                        )) {
                            ForEach(PadSound.allCases) { sound in
                                Text(sound.name).tag(sound.rawValue)
                            }
                        }

                        Text((draft.padSound ?? model.metronome.padSound).detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if draft.padEnabled == true {
                        Text(draft.defaultKey == nil
                             ? "This song has no key yet, so the pad will use whichever key the Metronome screen is set to."
                             : "Starting the click starts a pad in \(draft.defaultKey?.display ?? "")\u{2009}\u{2014} and stops it again with the click.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Every song carries a mix, so there is nothing to switch
                // on: the sliders are the mix, and Reset puts back the
                // standard one rather than leaving the song without any.
                Section("Click mix") {
                    mixSlider("Accent", \.accent)
                    mixSlider("Quarter notes", \.quarter)
                    mixSlider("Eighth notes", \.eighth)
                    mixSlider("Sixteenth notes", \.sixteenth)

                    HStack {
                        Button("Preview this mix") {
                            model.metronome.apply(draft.mix ?? .standard)
                        }
                        Spacer()
                        Button("Reset to default") { draft.mix = .standard }
                            .disabled(draft.mix ?? .standard == .standard)
                    }
                }

                Section("Notes") {
                    NotesField("Anything worth remembering", text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            // No Done bar above the keyboard here: the keyboard button in the
            // footer below does the same job and is always on screen, so the
            // bar would only steal a row of the sheet.
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
                // Only present while the keyboard is up; the Form has no
                // Done bar of its own because this does the same job without
                // costing a row of the sheet.
                KeyboardDismissButton()
                    .padding(.trailing, 6)
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
