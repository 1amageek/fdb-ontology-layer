import Foundation

/// Represents additional semantic constraints on predicates
public struct OntologyConstraint: Codable, Hashable, Sendable {
    /// Predicate name this constraint applies to
    public let predicate: String

    /// Type of constraint
    public let constraintType: ConstraintType

    /// Additional parameters (e.g., cardinality values)
    public let parameters: [String: String]?

    /// Human-readable description
    public let description: String?

    public init(
        predicate: String,
        constraintType: ConstraintType,
        parameters: [String: String]? = nil,
        description: String? = nil
    ) {
        self.predicate = predicate
        self.constraintType = constraintType
        self.parameters = parameters
        self.description = description
    }
}

/// Types of constraints that can be applied to predicates
public enum ConstraintType: String, Codable, Sendable {
    /// Cardinality constraint: min/max number of values
    case cardinality

    /// Unique constraint: each subject can have at most one value
    case unique

    /// Symmetric: if (A, p, B) then (B, p, A)
    case symmetric

    /// Transitive: if (A, p, B) and (B, p, C) then (A, p, C)
    case transitive

    /// Inverse: if (A, p, B) then (B, inverseP, A)
    case inverse

    /// Functional: each subject has at most one value
    case functional

    /// Inverse functional: each object has at most one subject
    case inverseFunctional
}
