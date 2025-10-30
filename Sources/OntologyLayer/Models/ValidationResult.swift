import Foundation

/// Result of validating a triple against the ontology
public struct ValidationResult: Sendable {
    /// Whether the triple is valid
    public let isValid: Bool

    /// List of validation errors (empty if valid)
    public let errors: [ValidationError]

    /// List of warnings (non-fatal issues)
    public let warnings: [String]

    public init(
        isValid: Bool,
        errors: [ValidationError] = [],
        warnings: [String] = []
    ) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// A validation error with details
public struct ValidationError: Sendable {
    /// Human-readable error message
    public let message: String

    /// Type of error
    public let errorType: ErrorType

    public init(message: String, errorType: ErrorType) {
        self.message = message
        self.errorType = errorType
    }

    public enum ErrorType: String, Sendable {
        case predicateNotFound
        case domainMismatch
        case rangeMismatch
        case constraintViolation
    }
}

/// Represents a constraint violation
public struct ConstraintViolation: Sendable {
    /// The constraint that was violated
    public let constraint: OntologyConstraint

    /// Human-readable message
    public let message: String

    /// Triples affected by this violation
    public let affectedTriples: [(subject: String, object: String)]

    public init(
        constraint: OntologyConstraint,
        message: String,
        affectedTriples: [(subject: String, object: String)]
    ) {
        self.constraint = constraint
        self.message = message
        self.affectedTriples = affectedTriples
    }
}
