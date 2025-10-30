import Foundation

/// Errors that can occur in ontology operations
public enum OntologyError: Error, Sendable {
    case classNotFound(String)
    case predicateNotFound(String)
    case constraintNotFound(String)
    case invalidDefinition(String)
    case circularHierarchy(String)
    case dependencyExists(String)
    case validationFailed(String)
    case encodingError(String)
    case decodingError(String)
    case transactionFailed(String)
}

extension OntologyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .classNotFound(let name):
            return "Class not found: \(name)"
        case .predicateNotFound(let name):
            return "Predicate not found: \(name)"
        case .constraintNotFound(let desc):
            return "Constraint not found: \(desc)"
        case .invalidDefinition(let message):
            return "Invalid definition: \(message)"
        case .circularHierarchy(let message):
            return "Circular hierarchy detected: \(message)"
        case .dependencyExists(let message):
            return "Dependency exists: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .classNotFound:
            return "Verify the class name is correct, or define the class using defineClass() before referencing it."
        case .predicateNotFound:
            return "Verify the predicate name is correct, or define the predicate using definePredicate() before referencing it."
        case .constraintNotFound:
            return "Check that the constraint type is valid and has been defined for this predicate."
        case .invalidDefinition:
            return "Review the ontology definition syntax and ensure all required fields are properly formatted."
        case .circularHierarchy:
            return "Review the class hierarchy to remove circular inheritance. A class cannot inherit from itself directly or indirectly."
        case .dependencyExists:
            return "Remove or update dependent predicates or subclasses before deleting this ontology element."
        case .validationFailed:
            return "Check that the triple conforms to domain/range constraints defined in your ontology."
        case .encodingError:
            return "This is an internal encoding error. Verify that ontology definitions contain valid JSON-serializable data."
        case .decodingError:
            return "The stored ontology data may be corrupted. Try redefining the ontology element."
        case .transactionFailed:
            return "Check FoundationDB connectivity and transaction size limits. Retry the operation if it's transient."
        }
    }
}

// MARK: - CustomStringConvertible

extension OntologyError: CustomStringConvertible {
    public var description: String {
        return errorDescription ?? "Unknown ontology error"
    }
}
