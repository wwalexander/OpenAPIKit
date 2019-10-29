//
//  Content.swift
//  OpenAPIKit
//
//  Created by Mathew Polzin on 7/4/19.
//

import Foundation
import Poly
import AnyCodable

extension OpenAPI {
    public enum ContentType: String, Codable, Equatable, Hashable {
        case json = "application/json"

        /// JSON:API
        case jsonapi = "application/vnd.api+json"

        case xml = "application/xml"

        case form = "application/x-www-form-urlencoded"

        /// RAR archive
        case rar = "application/x-rar-compressed"

        /// Tape Archive (TAR)
        case tar = "application/x-tar"

        case txt = "text/plain"

        /// ZIP archive
        case zip = "application/zip"
    }

    public struct Content: Equatable, VendorExtendable {
        public let schema: Either<JSONReference<Components, JSONSchema>, JSONSchema>
        public let example: AnyCodable?
        public let examples: Example.Map?
        public let encoding: [String: Encoding]?

        /// Dictionary of vendor extensions.
        ///
        /// These should be of the form:
        /// `[ "x-extensionKey": <anything>]`
        /// where the values are anything codable.
        public let vendorExtensions: [String: AnyCodable]

        public init(schema: Either<JSONReference<Components, JSONSchema>, JSONSchema>,
                    example: AnyCodable? = nil,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = schema
            self.example = example
            self.examples = nil
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }

        public init(schemaReference: JSONReference<Components, JSONSchema>,
                    example: AnyCodable? = nil,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = .init(schemaReference)
            self.example = example
            self.examples = nil
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }

        public init(schema: JSONSchema,
                    example: AnyCodable? = nil,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = .init(schema)
            self.example = example
            self.examples = nil
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }

        public init(schema: Either<JSONReference<Components, JSONSchema>, JSONSchema>,
                    examples: Example.Map?,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = schema
            self.examples = examples
            self.example = examples.flatMap(Self.firstExample(from:))
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }

        public init(schemaReference: JSONReference<Components, JSONSchema>,
                    examples: Example.Map?,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = .init(schemaReference)
            self.examples = examples
            self.example = examples.flatMap(Self.firstExample(from:))
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }

        public init(schema: JSONSchema,
                    examples: Example.Map?,
                    encoding: [String: Encoding]? = nil,
                    vendorExtensions: [String: AnyCodable] = [:]) {
            self.schema = .init(schema)
            self.examples = examples
            self.example = examples.flatMap(Self.firstExample(from:))
            self.encoding = encoding
            self.vendorExtensions = vendorExtensions
        }
    }
}

extension OpenAPI.Content {
    public typealias Map = [OpenAPI.ContentType: OpenAPI.Content]
}

extension OpenAPI.Content {
    public struct Encoding: Codable, Equatable {
        public let contentType: OpenAPI.ContentType?
        public let headers: OpenAPI.Header.Map?
//        public let style: String?
//        public let explode: Bool (defaults for this need to be tied to style making style a good candidate for abstraction)
        public let allowReserved: Bool

        public init(contentType: OpenAPI.ContentType? = nil,
                    headers: OpenAPI.Header.Map? = nil,
                    allowReserved: Bool = false) {
            self.contentType = contentType
            self.headers = headers
            self.allowReserved = allowReserved
        }
    }
}

extension OpenAPI.Content {
    private static func firstExample(from exampleDict: OpenAPI.Example.Map) -> AnyCodable? {
        return exampleDict
            .sorted { $0.key < $1.key }
            .compactMap { $0.value.a?.value.b }
            .first
    }
}

// MARK: - Codable

extension OpenAPI.Content: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(schema, forKey: .schema)

        // only encode `examples` if non-nil,
        // otherwise encode `example` if non-nil
        if examples != nil {
            try container.encode(examples, forKey: .examples)
        } else if example != nil {
            try container.encode(example, forKey: .example)
        }

        if encoding != nil {
            try container.encode(encoding, forKey: .encoding)
        }

        if vendorExtensions != [:] {
            for (key, value) in vendorExtensions {
                let xKey = key.starts(with: "x-") ? key : "x-\(key)"
                try container.encode(value, forKey: .extended(xKey))
            }
        }
    }
}

extension OpenAPI.Content: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard !(container.contains(.examples) && container.contains(.example)) else {
            throw Error.foundBothExampleAndExamples
        }

        schema = try container.decode(Either<JSONReference<OpenAPI.Components, JSONSchema>, JSONSchema>.self, forKey: .schema)
        encoding = try container.decodeIfPresent([String: Encoding].self, forKey: .encoding)

        if container.contains(.example) {
            example = try container.decode(AnyCodable.self, forKey: .example)
            examples = nil
        } else {
            let examplesMap = try container.decodeIfPresent(OpenAPI.Example.Map.self, forKey: .examples)
            examples = examplesMap
            example = examplesMap.flatMap(Self.firstExample(from:))
        }

        vendorExtensions = try Self.extensions(from: decoder)
    }

    public enum Error: Swift.Error {
        case foundBothExampleAndExamples
    }
}

extension OpenAPI.Content {
    enum CodingKeys: ExtendableCodingKey {
        case schema
        case example
        case examples // `example` and `examples` are mutually exclusive
        case encoding
        case extended(String)

        static var allBuiltinKeys: [CodingKeys] {
            return [.schema, .example, .examples, .encoding]
        }

        static func extendedKey(for value: String) -> CodingKeys {
            return .extended(value)
        }

        init?(stringValue: String) {
            switch stringValue {
            case "schema":
                self = .schema
            case "example":
                self = .example
            case "examples":
                self = .examples
            case "encoding":
                self = .encoding
            default:
                self = .extended(stringValue)
            }
        }

        init?(intValue: Int) {
            return nil
        }

        var stringValue: String {
            switch self {
            case .schema:
                return "schema"
            case .example:
                return "example"
            case .examples:
                return "examples"
            case .encoding:
                return "encoding"
            case .extended(let key):
                return key
            }
        }

        var intValue: Int? {
            return nil
        }
    }
}
