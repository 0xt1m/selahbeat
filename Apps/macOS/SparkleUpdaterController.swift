import SwiftUI

#if canImport(Sparkle)
import Sparkle

/// Update checking, isolated to the macOS target.
///
/// Sparkle checks the appcast on every launch and silently does nothing when
/// offline, which is exactly the required behaviour: the metronome never
/// depends on the network, it just picks up releases when it can reach them.
@MainActor
final class SparkleUpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: SparkleUpdaterController

    var body: some View {
        Button("Check for Updates\u{2026}") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

#else

/// Sparkle not linked (e.g. a dependency-free local build). The app is fully
/// functional; it simply cannot self-update.
@MainActor
final class SparkleUpdaterController: ObservableObject {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: SparkleUpdaterController
    var body: some View {
        Button("Check for Updates\u{2026}") {}.disabled(true)
    }
}

#endif
