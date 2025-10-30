import Foundation

/// Represents a relationship or property with domain and range constraints
public struct OntologyPredicate: Codable, Hashable, Sendable {
    /// Unique predicate name (e.g., "knows", "worksFor", "hasTitle")
    public let name: String

    /// Domain: class name for valid subjects (e.g., "Person")
    public let domain: String

    /// Range: class name for valid objects (e.g., "Organization")
    public let range: String

    /// Human-readable description
    public let description: String?

    /// Whether this predicate represents a data property (vs object property)
    /// Data properties have literal values (String, Int, etc.)
    /// Object properties have entity references
    public let isDataProperty: Bool

    /// Custom metadata
    public let metadata: [String: String]?

    public init(
        name: String,
        domain: String,
        range: String,
        description: String? = nil,
        isDataProperty: Bool = false,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.domain = domain
        self.range = range
        self.description = description
        self.isDataProperty = isDataProperty
        self.metadata = metadata
    }
}
