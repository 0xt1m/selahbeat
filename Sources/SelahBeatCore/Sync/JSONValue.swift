import Foundation

/// Arbitrary JSON, for document bodies the server stores without reading.
///
/// The app owns the shape of a song or a service; the server only keeps the
/// bytes. That means a phone on an older build can never have its documents
/// rewritten into a shape it cannot read - but it also means the client needs
/// a way to carry JSON it has not been taught about.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Round-trips a model through JSON. Used to put a Song or a Service into
    /// a document body without the sync layer knowing anything about either.
    public static func encoding<T: Encodable>(_ value: T, using encoder: JSONEncoder) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func decoded<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try decoder.decode(type, from: data)
    }
}
