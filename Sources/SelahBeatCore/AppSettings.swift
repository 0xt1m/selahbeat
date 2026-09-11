import Foundation
import Observation

/// User preferences. Small enough for UserDefaults; kept separate from the
/// library so a settings change never rewrites the song files.
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults
    private static let key = "app.selahbeat.settings.v1"

    public struct Values: Codable, Sendable, Equatable {
        public var timbre: ClickTimbre = .woodblock
        public var subdivision: Subdivision = .quarter
        public var masterGain: Double = 0.8
        public var accentGain: Double = 1.0
        public var quarterGain: Double = 1.0
        // Off by default: a metronome should start as a plain pulse. Unmuting
        // a bus adds that layer between the notes above it.
        public var eighthGain: Double = 0.0
        public var sixteenthGain: Double = 0.0
        public var countInBars: Int = 0
        public var bpmRoundsToWhole: Bool = true
        public var allowsOtherAudio: Bool = false
        public var serverURL: String = "https://selahbeat.com"
        public var tapStartsPlayback: Bool = false

        public init() {}
    }

    public var values: Values {
        didSet {
            guard values != oldValue else { return }
            persist()
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Values.self, from: data) {
            self.values = decoded
        } else {
            self.values = Values()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public var serverBaseURL: URL? {
        URL(string: values.serverURL)
    }
}
