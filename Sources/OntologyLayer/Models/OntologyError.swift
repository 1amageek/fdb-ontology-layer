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
}
