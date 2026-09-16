import SwiftUI
@preconcurrency import AppKit
import SelahBeatCore

/// Spacebar start/stop, from any focus state.
///
/// SwiftUI's `.onKeyPress` loses Space to List selection and to focused
/// controls, which on stage means the drummer's most important key silently
/// does nothing. A local NSEvent monitor is unfashionable but reliable: it sees
/// the key first and only declines when a text field genuinely needs it.
@MainActor
final class AppKitEventBridge {
    private var monitor: Any?
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        install()
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func install() {
        // The handler is invoked on the main thread by AppKit, so hopping is
        // unnecessary and would add latency to the one key that must be fast.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return event }
                return self.handle(event, model: model) ? nil : event
            }
        }
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent, model: AppModel) -> Bool {
        // Never steal keys from a text field.
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSText || responder is NSTextView {
            return false
        }
        // Let menu shortcuts through.
        if event.modifierFlags.contains(where: [.command, .control, .option]) {
            return false
        }

        switch event.keyCode {
        case 49:   // space
            model.metronome.toggle()
            return true
        case 17:   // t
            model.metronome.tap()
            return true
        case 14:   // e - edit the song that is loaded, i.e. the one just clicked
            return model.editLoadedSong()
        case 126:  // up arrow
            model.metronome.nudge(event.modifierFlags.contains(.shift) ? 5 : 1)
            return true
        case 125:  // down arrow
            model.metronome.nudge(event.modifierFlags.contains(.shift) ? -5 : -1)
            return true
        default:
            break
        }

        // 1-9 jump to that song in the open service, 0 to the tenth. Read from
        // the characters rather than key codes so it follows the keyboard
        // layout, and only consumed when the service actually has that song -
        // otherwise a stray key would swallow itself silently.
        if let character = event.charactersIgnoringModifiers?.first,
           let digit = character.wholeNumberValue,
           (0...9).contains(digit) {
            return model.loadSong(atServicePosition: digit == 0 ? 10 : digit)
        }

        return false
    }
}

private extension NSEvent.ModifierFlags {
    func contains(where options: [NSEvent.ModifierFlags]) -> Bool {
        options.contains { self.contains($0) }
    }
}
