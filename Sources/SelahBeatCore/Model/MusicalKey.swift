import Foundation

/// A key as it appears on a chart. Deliberately NOT a pitch class — a worship
/// chart says "Bb", never "A#", and round-tripping through a pitch class
/// destroys that spelling.
public struct MusicalKey: Hashable, Codable, Sendable, Identifiable {
    public enum Letter: String, Codable, Sendable, CaseIterable {
        case C, D, E, F, G, A, B
    }

    public enum Accidental: String, Codable, Sendable, CaseIterable {
        case flat, natural, sharp

        public var symbol: String {
            switch self {
            case .flat: return "\u{266D}"
            case .natural: return ""
            case .sharp: return "\u{266F}"
            }
        }
    }

    public enum Mode: String, Codable, Sendable, CaseIterable {
        case major, minor
        public var suffix: String { self == .minor ? "m" : "" }
    }

    public var letter: Letter
    public var accidental: Accidental
    public var mode: Mode

    public init(_ letter: Letter, _ accidental: Accidental = .natural, _ mode: Mode = .major) {
        self.letter = letter
        self.accidental = accidental
        self.mode = mode
    }

    public var id: String { display }

    public var display: String {
        "\(letter.rawValue)\(accidental.symbol)\(mode.suffix)"
    }

    /// Plain-ASCII form for search and storage ("Bb", "F#m").
    public var asciiDisplay: String {
        let acc: String
        switch accidental {
        case .flat: acc = "b"
        case .sharp: acc = "#"
        case .natural: acc = ""
        }
        return "\(letter.rawValue)\(acc)\(mode.suffix)"
    }

    /// Keys a worship team actually plays, in circle-of-fifths-ish order.
    public static let common: [MusicalKey] = {
        let majors: [MusicalKey] = [
            .init(.G), .init(.A), .init(.B, .flat), .init(.C), .init(.D),
            .init(.E, .flat), .init(.E), .init(.F), .init(.A, .flat),
            .init(.B), .init(.D, .flat), .init(.F, .sharp),
        ]
        let minors: [MusicalKey] = [
            .init(.A, .natural, .minor), .init(.B, .natural, .minor),
            .init(.C, .sharp, .minor), .init(.D, .natural, .minor),
            .init(.E, .natural, .minor), .init(.F, .sharp, .minor),
            .init(.G, .natural, .minor),
        ]
        return majors + minors
    }()

    /// Parses "Bb", "F#m", "Ab major", "c# minor".
    public static func parse(_ raw: String) -> MusicalKey? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first, let letter = Letter(rawValue: String(first).uppercased()) else {
            return nil
        }
        var rest = s.dropFirst()
        var accidental = Accidental.natural
        if let c = rest.first {
            if c == "b" || c == "\u{266D}" {
                accidental = .flat
                rest = rest.dropFirst()
            } else if c == "#" || c == "\u{266F}" {
                accidental = .sharp
                rest = rest.dropFirst()
            }
        }
        let tail = rest.lowercased().trimmingCharacters(in: .whitespaces)
        let mode: Mode = (tail.hasPrefix("m") && !tail.hasPrefix("maj")) ? .minor : .major
        return MusicalKey(letter, accidental, mode)
    }
}
