import SwiftUI
import SelahBeatCore

#if canImport(Sparkle)
import Sparkle

/// Update checking, isolated to the macOS target.
///
/// Sparkle checks the appcast on every launch and silently does nothing when
/// offline, which is exactly the required behaviour: the metronome never
/// depends on the network, it just picks up releases when it can reach them.
@MainActor
final class SparkleUpdaterController: ObservableObject, AppUpdating {
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

    // MARK: - AppUpdating

    var canInstallUpdates: Bool { controller.updater.canCheckForUpdates }

    /// Hands over to Sparkle, which downloads, verifies the EdDSA signature and
    /// relaunches. Deliberately the same entry point as the menu item, so there
    /// is one update path rather than two.
    func installUpdate() {
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
final class SparkleUpdaterController: ObservableObject, AppUpdating {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}

    var canInstallUpdates: Bool { false }
    func installUpdate() {}
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: SparkleUpdaterController
    var body: some View {
        Button("Check for Updates\u{2026}") {}.disabled(true)
    }
}

#endif
