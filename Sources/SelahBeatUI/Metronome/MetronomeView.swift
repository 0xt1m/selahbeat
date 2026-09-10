import SwiftUI
import SelahBeatCore

/// The full metronome screen.
///
/// On a narrow screen everything stacks. On a Mac window or an iPad the
/// controls split into two columns and scale up, rather than sitting in a
/// phone-width strip down the middle of a large display.
public struct MetronomeView: View {
    @Bindable private var model: AppModel
    @State private var savingSong: Song?

    public init(model: AppModel) {
        self.model = model
    }

    private var controller: MetronomeController { model.metronome }

    /// The width at which two columns start to earn their place.
    private let wideThreshold: CGFloat = 780

    public var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= wideThreshold

            ScrollView {
                Group {
                    if isWide {
                        wideBody(width: proxy.size.width)
                    } else {
                        narrowBody
                    }
                }
                .padding(isWide ? 28 : 22)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.surface)
        }
        .background(Theme.surface)
        .sheet(item: $savingSong) { song in
            SongEditorView(model: model, song: song, isNew: true) { saved in
                let stored = model.library.addSong(saved)
                model.metronome.loadSong(stored)
            }
        }
    }

    // MARK: - Layouts

    private var narrowBody: some View {
        VStack(spacing: 24) {
            tempoBlock(bpmSize: 104, controlWidth: 440)
            accentEditor
            soundBlock
            levelBlock
        }
        .frame(maxWidth: 720)
    }

    private func wideBody(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 22) {
                tempoBlock(bpmSize: min(190, width * 0.13), controlWidth: 560)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 20) {
                accentEditor
                soundBlock
                levelBlock
            }
            .frame(maxWidth: .infinity)
        }
        // Past this, columns get uncomfortably far apart on an ultrawide display.
        .frame(maxWidth: 1500)
    }

    // MARK: - Tempo

    private func tempoBlock(bpmSize: CGFloat, controlWidth: CGFloat) -> some View {
        VStack(spacing: 16) {
            if let loaded = controller.loadedItem {
                VStack(spacing: 3) {
                    Text(loaded.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                    if let key = loaded.key {
                        Text("Key of \(key.display)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Text(controller.bpm == controller.bpm.rounded()
                 ? String(Int(controller.bpm))
                 : String(format: "%.1f", controller.bpm))
                .font(Theme.tempoFont(size: bpmSize))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("BEATS PER MINUTE")
                .font(.system(size: 11, weight: .bold))
                .kerning(2)
                .foregroundStyle(Theme.secondaryText)

            tempoSlider

            HStack(spacing: 12) {
                ForEach([-5.0, -1.0, 1.0, 5.0], id: \.self) { delta in
                    InstantButton {
                        controller.nudge(delta)
                    } label: {
                        Text(delta > 0 ? "+\(Int(delta))" : "\(Int(delta))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.minHitTarget)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }

            // Start and Tap sit together directly under the nudge row: the two
            // controls a drummer reaches for while counting a song in.
            HStack(spacing: 12) {
                StartStopButton(controller: controller)
                TapPad(controller: controller, compact: false)
                    .frame(maxWidth: 150)
            }

            saveAsSongButton
        }
        .frame(maxWidth: controlWidth)
    }

    /// Dragging this while the click is running is safe: a tempo change
    /// rebases the scheduler so the already-pending tick stays where it was
    /// going to land, and only the interval after it changes. No stutter, no
    /// doubled beat.
    private var tempoSlider: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { controller.bpm },
                    set: { controller.setTempo($0.rounded()) }
                ),
                in: Song.minBPM...Song.maxBPM
            )
            .tint(Theme.accent)

            HStack {
                Text("\(Int(Song.minBPM))")
                Spacer()
                Text("\(Int(Song.maxBPM))")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.secondaryText.opacity(0.7))
        }
        .padding(.horizontal, 4)
    }

    /// Capture whatever is currently dialled in — tapped out by ear, most
    /// likely — as a song, without retyping the tempo you just found.
    private var saveAsSongButton: some View {
        Button {
            savingSong = Song(
                title: "",
                defaultBPM: controller.bpm,
                defaultTimeSignature: controller.timeSignature,
                defaultKey: controller.loadedItem?.key
            )
        } label: {
            Label("Save as Song", systemImage: "square.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .frame(height: Theme.minHitTarget)
                .background(Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var accentEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Accents")
                Spacer()
                Button("Reset") { controller.resetAccents() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Tap a dot to accent, soften or mute that beat.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            BeatDots(controller: controller, dotSize: 22, interactive: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

            HStack(spacing: 14) {
                TimeSignaturePicker(controller: controller)
                SubdivisionPicker(controller: controller)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var soundBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Click sound")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(ClickTimbre.allCases) { timbre in
                    Button {
                        controller.previewTimbre(timbre)
                        model.persistSettingsFromMetronome()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(timbre.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(timbre.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(controller.timbre == timbre ? Theme.accentDim : Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(controller.timbre == timbre ? Theme.accent : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Click volume")
                Spacer()
                Text("\(Int(controller.masterGain / 1.5 * 100))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Slider(value: Bindable(controller).masterGain, in: 0...1.5) { editing in
                    if !editing { model.persistSettingsFromMetronome() }
                }
                .tint(Theme.accent)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Theme.primaryText)
    }
}
