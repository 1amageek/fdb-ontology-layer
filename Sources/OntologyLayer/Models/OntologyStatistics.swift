import Foundation

/// Statistics about the ontology
public struct OntologyStatistics: Codable, Sendable {
    /// Total number of classes
    public let classCount: UInt64

    /// Total number of predicates
    public let predicateCount: UInt64

    /// Total number of constraints
    public let constraintCount: UInt64

    /// Current ontology version
    public let currentVersion: UInt64

    /// When the ontology was created
    public let createdAt: Date?

    /// Last modification time
    public let lastUpdated: Date?

    public init(
        classCount: UInt64,
        predicateCount: UInt64,
        constraintCount: UInt64,
        currentVersion: UInt64,
        createdAt: Date? = nil,
        lastUpdated: Date? = nil
    ) {
        self.classCount = classCount
        self.predicateCount = predicateCount
        self.constraintCount = constraintCount
        self.currentVersion = currentVersion
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
}
