import Foundation
import Logging

/// Validates triples and knowledge records against the ontology
public actor OntologyValidator {

    // MARK: - Properties

    private let store: OntologyStore
    private let logger: Logger

    // MARK: - Initialization

    public init(
        store: OntologyStore,
        logger: Logger? = nil
    ) {
        self.store = store
        self.logger = logger ?? Logger(label: "com.ontology.validator")
    }

    // MARK: - Triple Validation

    /// Validate a complete triple against the ontology
    public func validate(
        _ triple: (subject: String, predicate: String, object: String)
    ) async throws -> ValidationResult {
        logger.debug("Validating triple: (\(triple.subject), \(triple.predicate), \(triple.object))")

        var errors: [ValidationError] = []
        var warnings: [String] = []

        // 1. Check if predicate exists
        guard let predicate = try await store.getPredicate(named: triple.predicate) else {
            errors.append(ValidationError(
                message: "Predicate '\(triple.predicate)' not found in ontology",
                errorType: .predicateNotFound
            ))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // 2. Validate domain
        let domainValid = try await validateDomain(subject: triple.subject, predicate: triple.predicate)
        if !domainValid {
            errors.append(ValidationError(
                message: "Subject type '\(triple.subject)' does not match predicate domain '\(predicate.domain)'",
                errorType: .domainMismatch
            ))
        }

        // 3. Validate range
        let rangeValid = try await validateRange(predicate: triple.predicate, object: triple.object)
        if !rangeValid {
            errors.append(ValidationError(
                message: "Object type '\(triple.object)' does not match predicate range '\(predicate.range)'",
                errorType: .rangeMismatch
            ))
        }

        // 4. Check constraints
        let constraints = try await store.getConstraints(for: triple.predicate)
        for constraint in constraints {
            if constraint.constraintType == .functional ||
               constraint.constraintType == .inverseFunctional {
                warnings.append("Constraint '\(constraint.constraintType)' requires additional validation at insertion time")
            }
        }

        let isValid = errors.isEmpty
        return ValidationResult(isValid: isValid, errors: errors, warnings: warnings)
    }

    /// Check if a subject class matches the predicate's domain
    public func validateDomain(
        subject: String,
        predicate: String
    ) async throws -> Bool {
        guard let pred = try await store.getPredicate(named: predicate) else {
            return false
        }

        // Use reasoner to check if subject is subclass of domain
        let reasoner = OntologyReasoner(store: store, logger: logger)
        return try await reasoner.isSubclassOf(subject, of: pred.domain)
    }

    /// Check if an object class matches the predicate's range
    public func validateRange(
        predicate: String,
        object: String
    ) async throws -> Bool {
        guard let pred = try await store.getPredicate(named: predicate) else {
            return false
        }

        // For data properties, range is a literal type (e.g., "String", "Int")
        // For object properties, use reasoner to check subclass relationship
        if pred.isDataProperty {
            return true  // Assume literal types are valid
        }

        let reasoner = OntologyReasoner(store: store, logger: logger)
        return try await reasoner.isSubclassOf(object, of: pred.range)
    }

    /// Validate all constraints for a given triple pattern
    public func validateConstraints(
        predicate: String,
        existingTriples: [(subject: String, object: String)]
    ) async throws -> [ConstraintViolation] {
        let constraints = try await store.getConstraints(for: predicate)
        var violations: [ConstraintViolation] = []

        for constraint in constraints {
            switch constraint.constraintType {
            case .functional:
                // Check functional constraint: each subject has at most one value
                var subjectMap: [String: Set<String>] = [:]
                for (subject, object) in existingTriples {
                    subjectMap[subject, default: []].insert(object)
                }

                for (subject, objects) in subjectMap where objects.count > 1 {
                    violations.append(ConstraintViolation(
                        constraint: constraint,
                        message: "Functional property '\(predicate)' violated: subject '\(subject)' has \(objects.count) values",
                        affectedTriples: objects.map { (subject, $0) }
                    ))
                }

            case .inverseFunctional:
                // Check inverse functional constraint: each object has at most one subject
                var objectMap: [String: Set<String>] = [:]
                for (subject, object) in existingTriples {
                    objectMap[object, default: []].insert(subject)
                }

                for (object, subjects) in objectMap where subjects.count > 1 {
                    violations.append(ConstraintViolation(
                        constraint: constraint,
                        message: "Inverse functional property '\(predicate)' violated: object '\(object)' has \(subjects.count) subjects",
                        affectedTriples: subjects.map { ($0, object) }
                    ))
                }

            case .unique:
                // Check unique constraint: each subject-object pair appears at most once
                let tripleSet = Set(existingTriples.map { "\($0.subject):\($0.object)" })
                if tripleSet.count < existingTriples.count {
                    violations.append(ConstraintViolation(
                        constraint: constraint,
                        message: "Unique constraint violated: duplicate triples exist",
                        affectedTriples: existingTriples
                    ))
                }

            case .cardinality:
                // Check cardinality constraint
                guard let minStr = constraint.parameters?["min"],
                      let maxStr = constraint.parameters?["max"],
                      let min = Int(minStr) else {
                    continue
                }

                var subjectMap: [String: Int] = [:]
                for (subject, _) in existingTriples {
                    subjectMap[subject, default: 0] += 1
                }

                for (subject, count) in subjectMap {
                    if count < min {
                        violations.append(ConstraintViolation(
                            constraint: constraint,
                            message: "Cardinality minimum violated: subject '\(subject)' has \(count) values (min: \(min))",
                            affectedTriples: existingTriples.filter { $0.subject == subject }
                        ))
                    }

                    if maxStr != "unbounded", let max = Int(maxStr), count > max {
                        violations.append(ConstraintViolation(
                            constraint: constraint,
                            message: "Cardinality maximum violated: subject '\(subject)' has \(count) values (max: \(max))",
                            affectedTriples: existingTriples.filter { $0.subject == subject }
                        ))
                    }
                }

            case .symmetric, .transitive, .inverse:
                // These constraints are handled by the reasoner, not validation
                break
            }
        }

        return violations
    }

    // MARK: - Batch Validation

    /// Validate multiple triples at once
    public func validateBatch(
        _ triples: [(subject: String, predicate: String, object: String)]
    ) async throws -> [ValidationResult] {
        var results: [ValidationResult] = []

        for triple in triples {
            let result = try await validate(triple)
            results.append(result)
        }

        return results
    }
}
