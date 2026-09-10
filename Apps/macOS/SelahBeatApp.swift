import SwiftUI
import AppKit
import SelahBeatCore
import SelahBeatUI

@main
struct SelahBeatApp: App {
    @State private var model = AppModel.live()
    @StateObject private var updater = SparkleUpdaterController()
    @State private var eventBridge: AppKitEventBridge?
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    SelahBeatRootView(model: model)
                } else {
                    // Loading is ~5 ms; this only ever flashes on a cold disk.
                    Color(white: 0.11).ignoresSafeArea()
                }
            }
            .frame(minWidth: 940, minHeight: 660)
            .task {
                await model.bootstrap()
                eventBridge = AppKitEventBridge(model: model)
                isReady = true
            }
            .onDisappear {
                Task { await model.flush() }
            }
        }
        .defaultSize(width: 1240, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Service") {
                    let service = model.library.createService(name: "New Service")
                    model.selectedServiceID = service.id
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Transport") {
                Button(model.metronome.isRunning ? "Stop" : "Start") {
                    model.metronome.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Tap Tempo") { model.metronome.tap() }
                    .keyboardShortcut("t", modifiers: [])

                Divider()

                Button("Previous Song") { model.step(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!model.canStepBackward)

                Button("Next Song") { model.step(1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!model.canStepForward)

                Divider()

                Button(model.isStageMode ? "Exit Stage Mode" : "Stage Mode") {
                    model.isStageMode.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
