import Foundation
import SelahBeatCore
import SelahBeatAudioC

/// Verifies the whole audio path on real hardware: engine construction, the
/// always-on graph, parameter publishing, and that ticks actually fire.
@MainActor
func run() async {
    // Unbuffered, so a crash never swallows the diagnostics that explain it.
    setvbuf(stdout, nil, _IONBF, 0)
    print("SelahBeat audio check")
    print(String(repeating: "-", count: 46))

    let controller = MetronomeController.live()
    // Give CoreAudio a moment to hand us the device.
    try? await Task.sleep(for: .milliseconds(600))
    controller.refreshDiagnostics()

    let d = controller.diagnostics
    print("engine running     : \(d.engineRunning)")
    print("sample rate        : \(Int(d.sampleRate)) Hz")
    print("buffer size        : \(d.bufferFrames) frames")
    print("output latency     : \(String(format: "%.2f", d.outputLatency * 1000)) ms")
    print("route              : \(d.route)")
    print("est. start latency : \(String(format: "%.2f", d.startLatencyEstimate * 1000)) ms")

    guard d.engineRunning else {
        print("\nFAIL: audio engine is not running")
        exit(1)
    }

    // Measure how long after Start the first tick is actually emitted.
    controller.setTempo(120)
    controller.timeSignature = .fourFour

    let before = sb_last_tick_index(controller)
    let t0 = CFAbsoluteTimeGetCurrent()
    controller.start()

    var firstTickAt: CFAbsoluteTime?
    while CFAbsoluteTimeGetCurrent() - t0 < 1.0 {
        if sb_last_tick_index(controller) > before {
            firstTickAt = CFAbsoluteTimeGetCurrent()
            break
        }
        try? await Task.sleep(for: .microseconds(200))
    }

    guard let firstTickAt else {
        print("\nFAIL: no tick was emitted within 1 s of Start")
        controller.stop()
        exit(1)
    }

    let startLatency = (firstTickAt - t0) * 1000
    print("first tick after Start: \(String(format: "%.2f", startLatency)) ms (polling resolution ~0.2 ms)")

    // Two seconds at 120 BPM is four beats. The click grid is sixteenths, so
    // that is four ticks per beat - most of them silent, because the eighth and
    // sixteenth mix busses start muted. Scheduling is what is being checked
    // here, not audibility.
    let ticksPerBeat = controller.pattern.ticksPerBeat
    let expectedTicks = 4 * ticksPerBeat
    let countBefore = sb_last_tick_index(controller)
    try? await Task.sleep(for: .seconds(2))
    let countAfter = sb_last_tick_index(controller)
    let ticks = Int(countAfter - countBefore)
    controller.stop()

    print("grid               : \(ticksPerBeat) ticks per beat")
    print("ticks in 2 s @120  : \(ticks) (expected ~\(expectedTicks))")

    controller.refreshDiagnostics()
    print("peak render time   : \(String(format: "%.0f", controller.diagnostics.maxRenderMicros)) \u{00B5}s")
    print("render load        : \(String(format: "%.2f", controller.diagnostics.renderLoad * 100))%")

    let ok = abs(ticks - expectedTicks) <= 1 && startLatency < 60
    print(String(repeating: "-", count: 46))
    print(ok ? "PASS" : "FAIL")
    exit(ok ? 0 : 1)
}

@MainActor
func sb_last_tick_index(_ controller: MetronomeController) -> UInt64 {
    controller.lastTickIndexForDiagnostics
}

await run()
