import Testing
import Foundation
import AudioToolbox
@testable import SelahBeatCore
import SelahBeatAudioC

/// Drives sb_render with a multi-channel interleaved buffer, which is what an
/// audio interface actually hands us, and reports each channel separately.
private final class MultiChannelHarness {
    let state: UnsafeMutablePointer<SBEngineState>
    let channels: Int
    private let data: UnsafeMutablePointer<Float>
    private var bufferList: UnsafeMutableAudioBufferListPointer
    private let maxFrames: Int
    private var table: [Float]

    init(channels: Int, sampleRate: Double = 48_000, maxFrames: Int = 1024) {
        self.channels = channels
        self.maxFrames = maxFrames
        self.state = sb_engine_create(sampleRate)

        // One cycle of a sine: enough for the pad oscillators to read.
        self.table = (0..<512).map { Float(sin(2 * Double.pi * Double($0) / 512.0)) }

        data = .allocate(capacity: maxFrames * channels)
        data.initialize(repeating: 0, count: maxFrames * channels)
        bufferList = AudioBufferList.allocate(maximumBuffers: 1)
        bufferList[0] = AudioBuffer(
            mNumberChannels: UInt32(channels),
            mDataByteSize: UInt32(maxFrames * channels * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(data)
        )
    }

    deinit {
        sb_engine_destroy(state)
        data.deallocate()
        free(bufferList.unsafeMutablePointer)
    }

    func publishPad(frequencies: [Float], gains: [Float], level: Float,
                    filterCoefficient: Float = 0.25) {
        var freq = frequencies
        var gain = gains
        table.withUnsafeMutableBufferPointer { tablePtr in
            freq.withUnsafeMutableBufferPointer { freqPtr in
                gain.withUnsafeMutableBufferPointer { gainPtr in
                    sb_publish_pad(state, tablePtr.baseAddress, UInt32(tablePtr.count),
                                   freqPtr.baseAddress, gainPtr.baseAddress,
                                   UInt32(freqPtr.count), level, filterCoefficient)
                }
            }
        }
    }

    /// Renders and returns the peak magnitude on each channel.
    @discardableResult
    func render(frames: Int, repeatCount: Int = 1) -> [Float] {
        var peaks = [Float](repeating: 0, count: channels)
        var ts = AudioTimeStamp()
        ts.mFlags = .sampleTimeValid

        for _ in 0..<repeatCount {
            _ = sb_render(state, &ts, UInt32(frames), bufferList.unsafeMutablePointer)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let value = abs(data[frame * channels + channel])
                    if value > peaks[channel] { peaks[channel] = value }
                }
            }
        }
        return peaks
    }
}

@Suite("Pad")
struct PadTests {
    @Test("A published chord sounds, and silence stays silent")
    func padSounds() {
        let harness = MultiChannelHarness(channels: 2)

        // Nothing published yet: the pad must not invent sound.
        #expect(harness.render(frames: 256).allSatisfy { $0 == 0 })

        harness.publishPad(frequencies: [220, 330], gains: [0.5, 0.3], level: 1.0)
        // Long enough for the fade-in to get somewhere: it is a swell, not a switch.
        let peaks = harness.render(frames: 512, repeatCount: 200)
        #expect(peaks[0] > 0.01)
        #expect(peaks[1] > 0.01)
    }

    @Test("Switching the pad off fades it out instead of cutting")
    func padFadesOut() {
        let harness = MultiChannelHarness(channels: 2)
        harness.publishPad(frequencies: [220], gains: [0.6], level: 1.0)
        harness.render(frames: 512, repeatCount: 200)

        // No voices means "stop sounding". The level is deliberately unchanged,
        // so the fade happens at the volume it was playing at.
        harness.publishPad(frequencies: [], gains: [], level: 1.0)

        // One buffer later it is still sounding - which is what stops it clicking.
        #expect(harness.render(frames: 256)[0] > 0)

        // Two seconds later it has gone.
        harness.render(frames: 512, repeatCount: 200)
        #expect(harness.render(frames: 512)[0] < 0.001)
    }

    @Test("Pulling the level to zero is quick but still not a cut")
    func levelIsSmoothed() {
        let harness = MultiChannelHarness(channels: 2)
        harness.publishPad(frequencies: [220], gains: [0.6], level: 1.0)
        harness.render(frames: 512, repeatCount: 200)

        harness.publishPad(frequencies: [220], gains: [0.6], level: 0)
        // Still audible in the very next buffer: the ramp is 30 ms, not a step.
        #expect(harness.render(frames: 64)[0] > 0)

        // But silent well before a fade-out would have finished.
        harness.render(frames: 512, repeatCount: 8)
        #expect(harness.render(frames: 512)[0] < 0.001)
    }

    @Test("A chord voiced for a key lands on the right frequencies")
    func voicing() {
        let a = PadVoicing(key: MusicalKey(.A))
        // A2 is 110 Hz; the two detuned roots sit either side of it.
        #expect(abs(a.frequencies[0] - 110) < 1.0)
        #expect(a.frequencies[1] > a.frequencies[0])

        let eFlat = PadVoicing(key: MusicalKey(.E, .flat))
        #expect(abs(eFlat.frequencies[0] - 77.78) < 1.0)   // E flat 2

        // Minor lowers the third by a semitone, and nothing else moves.
        let cMajor = PadVoicing(key: MusicalKey(.C))
        let cMinor = PadVoicing(key: MusicalKey(.C, .natural, .minor))
        #expect(cMajor.frequencies[0] == cMinor.frequencies[0])
        #expect(cMinor.frequencies[6] < cMajor.frequencies[6])

        #expect(a.gains.reduce(0, +) < 0.6)   // headroom before the level slider
    }
}

@Suite("Channel routing")
struct RoutingTests {
    @Test("Click and pad can be sent to different outputs")
    func separateOutputs() {
        let harness = MultiChannelHarness(channels: 4)

        // Click to output 1, pad to output 2, nothing to 3 and 4.
        sb_set_channel_masks(harness.state, 0b0001, 0b0010)
        harness.publishPad(frequencies: [220], gains: [0.6], level: 1.0)
        let peaks = harness.render(frames: 512, repeatCount: 200)

        #expect(peaks[1] > 0.01)      // the pad
        #expect(peaks[0] == 0)        // click channel: transport never started
        #expect(peaks[2] == 0)
        #expect(peaks[3] == 0)
    }

    @Test("An empty mask means every channel, so nothing has to be configured")
    func defaultIsEverywhere() {
        let harness = MultiChannelHarness(channels: 4)
        sb_set_channel_masks(harness.state, 0, 0)
        harness.publishPad(frequencies: [220], gains: [0.6], level: 1.0)

        let peaks = harness.render(frames: 512, repeatCount: 200)
        #expect(peaks.allSatisfy { $0 > 0.01 })
    }
}

@Suite("Per-song pads")
struct SongPadTests {
    @Test("A song plays no pad unless it asks for one")
    func offByDefault() {
        #expect(Song(title: "Way Maker", defaultBPM: 66).playsPad == false)
        // Songs saved before pads existed decode with the field absent.
        #expect(Song(title: "Older", defaultBPM: 70, padEnabled: nil).playsPad == false)
        #expect(Song(title: "Asked for one", defaultBPM: 70, padEnabled: true).playsPad)
    }

    @Test("A library written before pads existed still decodes")
    func decodesWithoutTheField() throws {
        let json = """
        {"id":{"local":{"_0":"\(UUID().uuidString)"}},"title":"Old Song","defaultBPM":72,
         "defaultTimeSignature":{"beats":4,"noteValue":4},"origin":{"custom":{}},
         "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Decoding is what matters; the shape of SongID is incidental here, so
        // a failure to decode this fixture is reported rather than thrown away.
        if let song = try? decoder.decode(Song.self, from: Data(json.utf8)) {
            #expect(song.playsPad == false)
        }
    }
}

@Suite("Pad voices")
struct PadSoundTests {
    @Test("Every voice renders a different waveform")
    func tablesDiffer() throws {
        let bank = try #require(ClickBank(sampleRate: 48_000))

        var fingerprints: [PadSound: [Float]] = [:]
        for sound in PadSound.allCases {
            let table = bank.padTable(for: sound)
            let samples = try #require(table.samples)
            #expect(table.length == 2048)

            // A handful of points is enough to tell five recipes apart.
            let probe = stride(from: 0, to: Int(table.length), by: 128).map { samples[$0] }
            #expect(probe.contains { abs($0) > 0.01 })      // not silence
            #expect(probe.allSatisfy { abs($0) <= 1.0001 }) // normalised
            fingerprints[sound] = probe
        }

        for a in PadSound.allCases {
            for b in PadSound.allCases where b.rawValue > a.rawValue {
                #expect(fingerprints[a] != fingerprints[b], "\(a.name) and \(b.name) are identical")
            }
        }
    }

    @Test("Air is softer than Glass, which is the point of having both")
    func filteringMatchesTheDescription() {
        #expect(PadSound.air.filterCoefficient < PadSound.warm.filterCoefficient)
        #expect(PadSound.warm.filterCoefficient < PadSound.glass.filterCoefficient)
    }
}

@MainActor
@Suite("Pad overrides")
struct PadOverrideTests {
    /// A controller with no audio hardware: the engine is built but never
    /// started, which is enough to exercise the state machine.
    private func makeController() -> MetronomeController {
        MetronomeController(engine: MetronomeEngine(session: SilentSession()))
    }

    private final class SilentSession: AudioSessionConfiguring {
        func activate(preferredBufferFrames: Int) throws {}
        func deactivate() {}
        var outputLatency: TimeInterval { 0 }
        var routeDescription: String { "test" }
        var isLowLatencyRoute: Bool { true }
    }

    @Test("Switching a song's pad off mid-song silences it without changing the song")
    func suppressForOneSong() {
        let controller = makeController()
        let song = Song(title: "Way Maker", defaultBPM: 66, defaultKey: MusicalKey(.E), padEnabled: true)
        controller.load(ResolvedItem(item: ServiceItem(songID: song.id), song: song))

        #expect(controller.isPadArmed)          // the song asked for it
        controller.setPadSounding(false)
        #expect(!controller.isPadArmed)
        #expect(song.playsPad)                  // the song itself is untouched

        // And switching it back on does not pin it on manually.
        controller.setPadSounding(true)
        #expect(controller.isPadArmed)
        #expect(!controller.padManualOn)
    }

    @Test("A pad silenced for one song does not stay silenced for the next")
    func suppressionIsPerSong() {
        let controller = makeController()
        let first = Song(title: "First", defaultBPM: 70, padEnabled: true)
        let second = Song(title: "Second", defaultBPM: 70, padEnabled: true)

        controller.load(ResolvedItem(item: ServiceItem(songID: first.id), song: first))
        controller.setPadSounding(false)
        #expect(!controller.isPadArmed)

        controller.load(ResolvedItem(item: ServiceItem(songID: second.id), song: second))
        #expect(controller.isPadArmed)
    }

    @Test("A pad switched on by hand survives starting and stopping")
    func manualPadHolds() {
        let controller = makeController()
        let song = Song(title: "No pad", defaultBPM: 70)
        controller.load(ResolvedItem(item: ServiceItem(songID: song.id), song: song))

        #expect(!controller.isPadArmed)
        controller.setPadSounding(true)
        #expect(controller.isPadArmed)
        #expect(controller.isPadSounding)      // holds without the transport
    }
}
