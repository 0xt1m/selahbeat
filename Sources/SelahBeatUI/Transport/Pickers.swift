import SwiftUI
import SelahBeatCore

public struct TimeSignaturePicker: View {
    private let controller: MetronomeController
    @State private var showingCustom = false
    @State private var customBeats = 4
    @State private var customNoteValue = 4

    public init(controller: MetronomeController) {
        self.controller = controller
    }

    public var body: some View {
        Menu {
            ForEach(TimeSignature.common, id: \.self) { signature in
                Button {
                    controller.timeSignature = signature
                } label: {
                    HStack {
                        Text(signature.display)
                        if signature.isCompound { Text("compound").foregroundStyle(.secondary) }
                        if signature == controller.timeSignature { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button("Custom\u{2026}") {
                customBeats = controller.timeSignature.beats
                customNoteValue = controller.timeSignature.noteValue
                showingCustom = true
            }
        } label: {
            VStack(spacing: 0) {
                Text(controller.timeSignature.display)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("METER")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .kerning(1)
            }
            .frame(minWidth: 62, minHeight: Theme.minHitTarget)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showingCustom) {
            customEditor
        }
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom time signature").font(.headline)
            HStack {
                Stepper("Beats: \(customBeats)", value: $customBeats, in: 1...32)
            }
            Picker("Note value", selection: $customNoteValue) {
                ForEach([2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Apply") {
                controller.timeSignature = TimeSignature(beats: customBeats, noteValue: customNoteValue)
                showingCustom = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .sheetSize(width: 280, height: 200)
    }
}

public struct SubdivisionPicker: View {
    private let controller: MetronomeController

    public init(controller: MetronomeController) {
        self.controller = controller
    }

    public var body: some View {
        Menu {
            ForEach(Subdivision.allCases) { subdivision in
                Button {
                    controller.subdivision = subdivision
                } label: {
                    HStack {
                        Text("\(subdivision.symbol)  \(subdivision.label)")
                        if subdivision == controller.subdivision { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            VStack(spacing: 0) {
                Text(controller.subdivision.symbol)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                Text("SUBDIV")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .kerning(1)
            }
            .frame(minWidth: 58, minHeight: Theme.minHitTarget)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

public struct SoundPicker: View {
    private let controller: MetronomeController
    private let showsLabel: Bool

    public init(controller: MetronomeController, showsLabel: Bool = true) {
        self.controller = controller
        self.showsLabel = showsLabel
    }

    public var body: some View {
        Menu {
            ForEach(ClickTimbre.allCases) { timbre in
                Button {
                    // Auditions the sound immediately when stopped, so picking
                    // one is a listening decision rather than a guess.
                    controller.previewTimbre(timbre)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(timbre.name)
                            Text(timbre.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if timbre == controller.timbre { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                if showsLabel {
                    Text(controller.timbre.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minHitTarget)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
