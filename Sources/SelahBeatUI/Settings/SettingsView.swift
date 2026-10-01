import SwiftUI
import SelahBeatCore

public struct SettingsView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            soundTab
                .tabItem { Label("Sound", systemImage: "waveform") }
            OutputRoutingView(model: model)
                .tabItem { Label("Outputs", systemImage: "point.3.connected.trianglepath.dotted") }
            BackupView(model: model)
                .tabItem { Label("Backup", systemImage: "externaldrive.badge.icloud") }
            DiagnosticsView(model: model)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .sheetSize(width: 520, height: 400)
        .preferredColorScheme(.dark)
    }

    private var aboutTab: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(AppInfo.displayVersion)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                #if os(macOS)
                HStack {
                    Button("Check for Updates\u{2026}") {
                        Task { await model.updates.check() }
                    }
                    .disabled(model.updates.isChecking)
                    if model.updates.isChecking {
                        ProgressView().controlSize(.small)
                    } else if model.updates.availableUpdate == nil, model.updates.lastCheck != nil {
                        Text("Up to date").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let release = model.updates.availableUpdate {
                    Text("Version \(release.version) is available.")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                #endif
            } header: {
                Text("SelahBeat")
            } footer: {
                Text("A metronome for worship drummers. selahbeat.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("Catalog") {
                LabeledTextField("Server", placeholder: "https://selahbeat.com",
                                 text: Bindable(model.settings).values.serverURL)
                    .textContentType(.URL)
                HStack {
                    Text("Songs cached")
                    Spacer()
                    Text("\(model.catalog.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(model.catalog.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                        .foregroundStyle(.secondary)
                }
                Button("Sync now") {
                    Task { await model.sync?.sync() }
                }
                .disabled(model.sync == nil || !model.network.isOnline)
                Text("The catalog is downloaded and kept on this device, so song lookup keeps working without a connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tempo") {
                Toggle("Round tapped tempos to whole numbers",
                       isOn: Bindable(model.settings).values.bpmRoundsToWhole)
            }
        }
        .formStyle(.grouped)
    }

    private var soundTab: some View {
        Form {
            Section("Click") {
                Picker("Sound", selection: Bindable(model.metronome).timbre) {
                    ForEach(ClickTimbre.allCases) { Text($0.name).tag($0) }
                }
                HStack {
                    Text("Level")
                    Slider(value: Bindable(model.metronome).masterGain, in: 0...1.5)
                }
                Button("Preview") { model.metronome.previewTimbre(model.metronome.timbre) }
            }

            Section("Pad") {
                HStack {
                    Text("Level")
                    Slider(value: Bindable(model.metronome).padLevel, in: 0...1.5)
                }
                Text("Switch the pad on from the Metronome screen, or per song in the song editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if os(iOS)
            Section("Other audio") {
                Toggle("Allow other apps to play at the same time",
                       isOn: Bindable(model.settings).values.allowsOtherAudio)
                Text("Turn this on if you run backing tracks from another app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .formStyle(.grouped)
        .onDisappear { model.persistSettingsFromMetronome() }
    }
}

/// Not hidden away — a drummer debugging why the click feels late needs to see
/// the buffer size, the route and the measured latency.
public struct DiagnosticsView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Audio output") {
                row("Route", model.metronome.diagnostics.route)
                row("Sample rate", "\(Int(model.metronome.diagnostics.sampleRate)) Hz")
                row("Buffer size", "\(model.metronome.diagnostics.bufferFrames) frames")
                row("Output latency", String(format: "%.1f ms", model.metronome.diagnostics.outputLatency * 1000))
                row("Estimated start latency",
                    String(format: "%.1f ms", model.metronome.diagnostics.startLatencyEstimate * 1000))
                if !model.metronome.diagnostics.isLowLatencyRoute {
                    Label("This route adds latency that cannot be compensated for.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                        .font(.caption)
                }
            }

            Section("Render thread") {
                row("Engine", model.metronome.diagnostics.engineRunning ? "Running" : "Stopped")
                row("Peak render time", String(format: "%.0f \u{00B5}s", model.metronome.diagnostics.maxRenderMicros))
                row("Render load", String(format: "%.1f%%", model.metronome.diagnostics.renderLoad * 100))
                Text("Render load well under 100% means no dropouts. The audio graph runs continuously so that pressing Start costs nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Refresh") { model.metronome.refreshDiagnostics() }
                Button("Reset peak") { model.metronome.resetRenderStats() }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.metronome.refreshDiagnostics() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
