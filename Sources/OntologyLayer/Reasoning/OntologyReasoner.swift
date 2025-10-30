import Foundation
import Logging

/// Performs basic reasoning tasks (subsumption, property propagation)
public actor OntologyReasoner {

    // MARK: - Properties

    private let store: OntologyStore
    private let logger: Logger

    // Cache for hierarchy checks
    private var subsumptionCache: [String: [String]] = [:]

    // MARK: - Initialization

    public init(
        store: OntologyStore,
        logger: Logger? = nil
    ) {
        self.store = store
        self.logger = logger ?? Logger(label: "com.ontology.reasoner")
    }

    // MARK: - Class Hierarchy Reasoning

    /// Check if one class is a subclass of another (supports transitivity)
    public func isSubclassOf(
        _ childClass: String,
        of parentClass: String
    ) async throws -> Bool {
        // Base case: same class
        if childClass == parentClass {
            return true
        }

        // Check cache
        if let cached = subsumptionCache[childClass] {
            return cached.contains(parentClass)
        }

        // Get ancestor path
        let ancestors = try await store.getSuperclasses(of: childClass)

        // Update cache
        subsumptionCache[childClass] = ancestors

        return ancestors.contains(parentClass)
    }

    /// Get all types (including ancestors) for an entity
    public func getAllTypes(of entityType: String) async throws -> [String] {
        var types: [String] = [entityType]
        let ancestors = try await store.getSuperclasses(of: entityType)
        types.append(contentsOf: ancestors)
        return types
    }

    /// Find the lowest common ancestor of two classes
    public func lowestCommonAncestor(
        _ class1: String,
        _ class2: String
    ) async throws -> String? {
        // Get ancestor paths
        let ancestors1 = try await store.getSuperclasses(of: class1)
        let ancestors2 = try await store.getSuperclasses(of: class2)

        // Find first common ancestor
        for ancestor1 in ancestors1 {
            if ancestors2.contains(ancestor1) {
                return ancestor1
            }
        }

        return nil
    }

    // MARK: - Property Reasoning

    /// Infer the type of an entity based on predicate usage
    public func inferType(
        from predicates: [String]
    ) async throws -> [String] {
        var possibleTypes: Set<String> = []

        for predicateName in predicates {
            guard let predicate = try await store.getPredicate(named: predicateName) else {
                continue
            }

            // Entity could be of the domain type
            possibleTypes.insert(predicate.domain)

            // Also include subclasses of the domain
            let subclasses = try await store.getSubclasses(of: predicate.domain)
            possibleTypes.formUnion(subclasses)
        }

        return Array(possibleTypes).sorted()
    }

    /// Apply symmetric property inference
    public func inferSymmetric(
        _ triple: (subject: String, predicate: String, object: String)
    ) async throws -> (subject: String, predicate: String, object: String)? {
        // Check if predicate has symmetric constraint
        let constraints = try await store.getConstraints(for: triple.predicate)
        let isSymmetric = constraints.contains { $0.constraintType == .symmetric }

        guard isSymmetric else {
            return nil
        }

        // Return reverse triple
        return (subject: triple.object, predicate: triple.predicate, object: triple.subject)
    }

    /// Apply inverse property inference
    public func inferInverse(
        _ triple: (subject: String, predicate: String, object: String)
    ) async throws -> (subject: String, predicate: String, object: String)? {
        // Check if predicate has inverse constraint
        let constraints = try await store.getConstraints(for: triple.predicate)

        guard let inverseConstraint = constraints.first(where: { $0.constraintType == .inverse }),
              let inversePredicate = inverseConstraint.parameters?["inversePredicate"] else {
            return nil
        }

        // Return inverse triple
        return (subject: triple.object, predicate: inversePredicate, object: triple.subject)
    }

    /// Apply transitive property closure
    public func computeTransitiveClosure(
        predicate: String,
        triples: [(subject: String, object: String)]
    ) async throws -> [(subject: String, object: String)] {
        // Check if predicate is transitive
        let constraints = try await store.getConstraints(for: predicate)
        let isTransitive = constraints.contains { $0.constraintType == .transitive }

        guard isTransitive else {
            return []
        }

        // Build adjacency map
        var graph: [String: Set<String>] = [:]
        for (subject, object) in triples {
            graph[subject, default: []].insert(object)
        }

        // Compute transitive closure using BFS
        var closure: [(String, String)] = []

        for (source, _) in graph {
            var visited = Set<String>()
            var queue = [source]

            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard !visited.contains(current) else { continue }
                visited.insert(current)

                if let neighbors = graph[current] {
                    for neighbor in neighbors {
                        if !visited.contains(neighbor) {
                            // Add inferred triple (skip if already in input)
                            let triple = (source, neighbor)
                            if !triples.contains(where: { $0.subject == source && $0.object == neighbor }) {
                                closure.append(triple)
                            }
                            queue.append(neighbor)
                        }
                    }
                }
            }
        }

        return closure
    }

    /// Validate functional property
    public func validateFunctional(
        predicate: String,
        existingTriples: [(subject: String, object: String)]
    ) async throws -> [ConstraintViolation] {
        // Check if predicate is functional
        let constraints = try await store.getConstraints(for: predicate)
        let isFunctional = constraints.contains { $0.constraintType == .functional }

        guard isFunctional else {
            return []  // No violations
        }

        // Group by subject
        var subjectMap: [String: Set<String>] = [:]
        for (subject, object) in existingTriples {
            subjectMap[subject, default: []].insert(object)
        }

        // Check for violations
        var violations: [ConstraintViolation] = []
        for (subject, objects) in subjectMap where objects.count > 1 {
            if let constraint = constraints.first(where: { $0.constraintType == .functional }) {
                violations.append(ConstraintViolation(
                    constraint: constraint,
                    message: "Functional property '\(predicate)' violated: subject '\(subject)' has \(objects.count) values",
                    affectedTriples: objects.map { (subject, $0) }
                ))
            }
        }

        return violations
    }

    // MARK: - Inference Helpers

    /// Infer all triples from a given triple (symmetric, inverse, transitive)
    public func inferAll(
        from triple: (subject: String, predicate: String, object: String)
    ) async throws -> [(subject: String, predicate: String, object: String)] {
        var inferred: [(String, String, String)] = []

        // Check symmetric
        if let symmetric = try await inferSymmetric(triple) {
            inferred.append(symmetric)
        }

        // Check inverse
        if let inverse = try await inferInverse(triple) {
            inferred.append(inverse)
        }

        // Transitive inference requires multiple triples, handled separately

        return inferred
    }
}
