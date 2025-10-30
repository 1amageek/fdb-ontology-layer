import Foundation

/// Represents a semantic class (entity type) in the ontology
public struct OntologyClass: Codable, Hashable, Sendable {
    /// Unique class name (e.g., "Person", "Organization", "Event")
    public let name: String

    /// Parent class name for inheritance (nil for root classes)
    public let parent: String?

    /// Human-readable description of this class
    public let description: String?

    /// List of predicate names applicable to instances of this class
    public let properties: [String]?

    /// Custom metadata (extensible)
    public let metadata: [String: String]?

    public init(
        name: String,
        parent: String? = nil,
        description: String? = nil,
        properties: [String]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.parent = parent
        self.description = description
        self.properties = properties
        self.metadata = metadata
    }
}
