import Foundation

/// Tracks ontology changes over time
public struct OntologyVersion: Codable, Sendable {
    /// Version number (monotonically increasing)
    public let version: UInt64

    /// Timestamp when this version was created
    public let timestamp: Date

    /// List of changes in this version
    public let changes: [OntologyChange]

    /// Human-readable comment
    public let comment: String?

    public init(
        version: UInt64,
        timestamp: Date = Date(),
        changes: [OntologyChange],
        comment: String? = nil
    ) {
        self.version = version
        self.timestamp = timestamp
        self.changes = changes
        self.comment = comment
    }
}

/// Represents a single change in ontology
public struct OntologyChange: Codable, Sendable {
    /// Type of change
    public let changeType: ChangeType

    /// Entity affected (class, predicate, or constraint name)
    public let entity: String

    /// Previous value (for updates/deletes)
    public let oldValue: String?

    /// New value (for creates/updates)
    public let newValue: String?

    public init(
        changeType: ChangeType,
        entity: String,
        oldValue: String? = nil,
        newValue: String? = nil
    ) {
        self.changeType = changeType
        self.entity = entity
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

/// Types of changes that can occur in ontology
public enum ChangeType: String, Codable, Sendable {
    case addClass
    case updateClass
    case deleteClass
    case addPredicate
    case updatePredicate
    case deletePredicate
    case addConstraint
    case updateConstraint
    case deleteConstraint
}
