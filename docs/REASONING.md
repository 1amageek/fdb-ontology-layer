# fdb-ontology-layer Reasoning Logic

## Overview

This document describes the reasoning capabilities of `fdb-ontology-layer`. The ontology layer implements **minimal reasoning** focused on practical knowledge management use cases, not full OWL/RDF reasoning.

## Reasoning Scope

### Supported Reasoning

| Type | Description | Complexity |
|------|-------------|------------|
| **Subsumption** | Class hierarchy inference (A ⊆ B) | O(depth) |
| **Domain/Range** | Type checking for predicates | O(1) |
| **Symmetric** | Bidirectional relations | O(1) |
| **Transitive** | Relation closure | O(n²) |
| **Functional** | Uniqueness constraints | O(n) |
| **Inverse** | Reverse predicates | O(1) |

### Explicitly NOT Supported

- Owl:sameAs / equivalence reasoning
- Complex class expressions (union, intersection, complement)
- SWRL rules
- Probabilistic reasoning
- Temporal reasoning

---

## 1. Subsumption Reasoning

### Class Hierarchy Inference

**Rule**: If `A ⊆ B` and `B ⊆ C`, then `A ⊆ C` (transitive).

```swift
actor OntologyReasoner {
    /// Check if childClass is a subclass of parentClass (transitive)
    public func isSubclassOf(
        _ childClass: String,
        of parentClass: String
    ) async throws -> Bool {
        // Base case: same class
        if childClass == parentClass {
            return true
        }

        // Get child class definition
        guard let child = try await store.getClass(named: childClass) else {
            return false
        }

        // Check parent
        guard let parent = child.parent else {
            return false  // Reached root
        }

        // Recursive check
        return try await isSubclassOf(parent, of: parentClass)
    }
}
```

**Example**:
```
Given:
  Employee.parent = Person
  Person.parent = Entity

Query: isSubclassOf("Employee", of: "Entity")

Steps:
  1. Employee != Entity
  2. Employee.parent = Person
  3. isSubclassOf("Person", of: "Entity")
     - Person != Entity
     - Person.parent = Entity
     - isSubclassOf("Entity", of: "Entity")
       - Entity == Entity → true
  → Result: true
```

### Instance Type Inference

**Rule**: If `entity` is instance of `A` and `A ⊆ B`, then `entity` is instance of `B`.

```swift
/// Get all types (including ancestors) for an entity
public func getAllTypes(of entityType: String) async throws -> [String] {
    var types: [String] = [entityType]
    var current = entityType

    while let cls = try await store.getClass(named: current),
          let parent = cls.parent {
        types.append(parent)
        current = parent
    }

    return types
}
```

**Example**:
```
Given:
  Alice is-a Employee
  Employee ⊆ Person ⊆ Entity

Inferred:
  Alice is-a Employee
  Alice is-a Person
  Alice is-a Entity
```

### Lowest Common Ancestor (LCA)

**Rule**: Find the first common ancestor in two class hierarchies.

```swift
public func lowestCommonAncestor(
    _ class1: String,
    _ class2: String
) async throws -> String? {
    // Get ancestor paths
    let ancestors1 = try await getSuperclasses(of: class1)
    let ancestors2 = try await getSuperclasses(of: class2)

    // Find first common ancestor
    for ancestor1 in ancestors1 {
        if ancestors2.contains(ancestor1) {
            return ancestor1
        }
    }

    return nil
}
```

**Example**:
```
Given:
  Employee ⊆ Person ⊆ Entity
  Student ⊆ Person ⊆ Entity

Query: lowestCommonAncestor("Employee", "Student")
  → Result: "Person"
```

---

## 2. Domain and Range Validation

### Predicate Type Checking

**Rule**: For triple `(s, p, o)`:
- Subject `s` must be instance of (or subclass of) `domain(p)`
- Object `o` must be instance of (or subclass of) `range(p)`

```swift
public func validateDomain(
    subject: String,
    predicate: String
) async throws -> Bool {
    guard let pred = try await store.getPredicate(named: predicate) else {
        return false
    }

    return try await isSubclassOf(subject, of: pred.domain)
}

public func validateRange(
    predicate: String,
    object: String
) async throws -> Bool {
    guard let pred = try await store.getPredicate(named: predicate) else {
        return false
    }

    return try await isSubclassOf(object, of: pred.range)
}
```

**Example**:
```
Given:
  Predicate "worksFor": domain=Person, range=Organization
  Triple: (Employee, worksFor, Company)

Validation:
  1. Check domain: Employee ⊆ Person? → YES
  2. Check range: Company ⊆ Organization? → YES
  → Result: VALID

Given:
  Triple: (Employee, worksFor, Person)

Validation:
  1. Check domain: Employee ⊆ Person? → YES
  2. Check range: Person ⊆ Organization? → NO
  → Result: INVALID (range mismatch)
```

---

## 3. Symmetric Property Reasoning

### Symmetric Inference

**Rule**: If `symmetric(p)` and `(A, p, B)`, then infer `(B, p, A)`.

```swift
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
```

**Example**:
```
Given:
  Constraint: symmetric("knows")
  Triple: (Alice, knows, Bob)

Inferred:
  (Bob, knows, Alice)
```

**Application in Knowledge Layer**:
```swift
func insert(_ triple: Triple, infer: Bool = true) async throws {
    // Insert original triple
    try await tripleStore.insert(triple)

    // Infer symmetric triple if applicable
    if infer, let reversed = try await reasoner.inferSymmetric(triple) {
        try await tripleStore.insert(reversed)
    }
}
```

---

## 4. Transitive Property Reasoning

### Transitive Closure

**Rule**: If `transitive(p)` and `(A, p, B)` and `(B, p, C)`, then infer `(A, p, C)`.

```swift
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

    // Compute transitive closure using Floyd-Warshall
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
                        closure.append((source, neighbor))
                        queue.append(neighbor)
                    }
                }
            }
        }
    }

    return closure
}
```

**Example**:
```
Given:
  Constraint: transitive("ancestor")
  Triples:
    (Alice, ancestor, Bob)
    (Bob, ancestor, Charlie)
    (Charlie, ancestor, Dave)

Inferred:
    (Alice, ancestor, Charlie)  // Alice → Bob → Charlie
    (Alice, ancestor, Dave)     // Alice → Bob → Charlie → Dave
    (Bob, ancestor, Dave)       // Bob → Charlie → Dave
```

**Performance Note**: Transitive closure is **O(n³)** in worst case. For large graphs, consider:
- Lazy evaluation (compute on-demand)
- Caching
- Incremental updates

---

## 5. Functional Property Validation

### Uniqueness Checking

**Rule**: If `functional(p)`, then each subject has **at most one** value for `p`.

```swift
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
        violations.append(ConstraintViolation(
            constraint: ...,
            message: "Functional property '\(predicate)' violated: subject '\(subject)' has \(objects.count) values",
            affectedTriples: objects.map { (subject, $0) }
        ))
    }

    return violations
}
```

**Example**:
```
Given:
  Constraint: functional("birthDate")
  Triples:
    (Alice, birthDate, "1990-01-01")
    (Alice, birthDate, "1991-01-01")  // VIOLATION!

Violation:
  "Functional property 'birthDate' violated: subject 'Alice' has 2 values"
```

---

## 6. Inverse Property Reasoning

### Inverse Inference

**Rule**: If `inverse(p1, p2)` and `(A, p1, B)`, then infer `(B, p2, A)`.

```swift
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
```

**Example**:
```
Given:
  Constraint: inverse("worksFor", "employs")
  Triple: (Alice, worksFor, Acme)

Inferred:
  (Acme, employs, Alice)
```

---

## 7. Reasoning Strategies

### Eager vs. Lazy Reasoning

#### Eager Reasoning (Materialization)

**Approach**: Infer and store all derived triples immediately.

**Pros**:
- Fast query time (all triples pre-computed)
- Simple query logic

**Cons**:
- Slow insertion time
- Increased storage
- Complex update logic

```swift
func insertWithEagerReasoning(_ triple: Triple) async throws {
    // 1. Insert original triple
    try await tripleStore.insert(triple)

    // 2. Compute all inferences
    let inferred = try await reasoner.inferAll(from: triple)

    // 3. Insert all inferred triples
    try await tripleStore.insertBatch(inferred)
}
```

#### Lazy Reasoning (Query-Time Inference)

**Approach**: Compute inferences on-demand during queries.

**Pros**:
- Fast insertion
- Minimal storage
- Automatic consistency

**Cons**:
- Slower query time
- Complex query logic

```swift
func queryWithLazyReasoning(
    subject: Value?,
    predicate: Value?
) async throws -> [Triple] {
    // 1. Query stored triples
    var results = try await tripleStore.query(subject: subject, predicate: predicate)

    // 2. Infer additional triples
    if let predName = extractPredicateName(predicate) {
        let constraints = try await ontologyStore.getConstraints(for: predName)

        // Add symmetric triples
        if constraints.contains(where: { $0.constraintType == .symmetric }) {
            let reversed = results.map { reverseTriple($0) }
            results.append(contentsOf: reversed)
        }

        // Add transitive triples (if needed)
        // ...
    }

    return results
}
```

### Hybrid Approach (Recommended)

**Strategy**: Materialize simple inferences (symmetric, inverse), compute complex inferences on-demand (transitive).

```swift
func insertWithHybridReasoning(_ triple: Triple) async throws {
    // 1. Insert original triple
    try await tripleStore.insert(triple)

    // 2. Materialize simple inferences (symmetric, inverse)
    if let symmetric = try await reasoner.inferSymmetric(triple) {
        try await tripleStore.insert(symmetric)
    }

    if let inverse = try await reasoner.inferInverse(triple) {
        try await tripleStore.insert(inverse)
    }

    // 3. Lazy transitive inference (query-time only)
}
```

---

## 8. Reasoning Performance

### Complexity Analysis

| Reasoning Type | Time Complexity | Space Complexity | Notes |
|----------------|-----------------|------------------|-------|
| Subsumption | O(depth) | O(1) | Depth typically < 10 |
| Domain/Range | O(depth) | O(1) | Same as subsumption |
| Symmetric | O(1) | O(n) | Doubles triple count |
| Transitive | O(n³) | O(n²) | Expensive for large graphs |
| Functional | O(n) | O(1) | Linear scan |
| Inverse | O(1) | O(n) | Doubles triple count |

### Optimization Techniques

#### 1. Cache Ancestor Paths

**Problem**: Repeated subsumption checks traverse hierarchy multiple times.

**Solution**: Cache full ancestor paths.

```swift
actor HierarchyCache {
    private var ancestorCache: [String: [String]] = [:]

    func getAncestors(of className: String) async throws -> [String] {
        if let cached = ancestorCache[className] {
            return cached
        }

        var ancestors: [String] = []
        var current = className

        while let cls = try await store.getClass(named: current),
              let parent = cls.parent {
            ancestors.append(parent)
            current = parent
        }

        ancestorCache[className] = ancestors
        return ancestors
    }
}
```

#### 2. Incremental Transitive Closure

**Problem**: Full transitive closure recomputation is expensive.

**Solution**: Update closure incrementally on triple insertion.

```swift
func insertWithIncrementalClosure(
    _ triple: (subject: String, predicate: String, object: String)
) async throws {
    // 1. Insert triple
    try await tripleStore.insert(triple)

    // 2. Check if predicate is transitive
    guard isTransitive(triple.predicate) else { return }

    // 3. Find all X where (X, p, subject)
    let predecessors = try await findPredecessors(of: triple.subject, via: triple.predicate)

    // 4. Find all Y where (object, p, Y)
    let successors = try await findSuccessors(of: triple.object, via: triple.predicate)

    // 5. Insert (X, p, Y) for all combinations
    for pred in predecessors {
        for succ in successors {
            try await tripleStore.insert((pred, triple.predicate, succ))
        }
    }
}
```

#### 3. Constraint Indexing

**Problem**: Checking constraints requires scanning all constraints.

**Solution**: Index constraints by predicate.

```
Key: (rootPrefix, "ontology", "constraint_by_predicate", <predicate>, <constraintType>)
Value: OntologyConstraint JSON
```

---

## 9. Reasoning Correctness

### Soundness

**Definition**: All inferred triples are logically correct.

**Guarantee**: Yes, for all implemented reasoning types.

### Completeness

**Definition**: All logically derivable triples are inferred.

**Guarantee**: No, only supported reasoning types are applied.

**Example of Incomplete Reasoning**:
```
Given:
  (Alice, knows, Bob)
  (Bob, knows, Charlie)
  knows is transitive

Supported Inference:
  (Alice, knows, Charlie)

Unsupported Inference:
  (Alice, friendOf, Charlie)  // Requires additional rules not supported
```

---

## 10. Testing Reasoning

### Unit Tests

```swift
@Test("Subsumption reasoning")
func testSubsumption() async throws {
    let reasoner = OntologyReasoner(store: store)

    // Setup hierarchy: Employee → Person → Entity
    try await store.defineClass(OntologyClass(name: "Entity"))
    try await store.defineClass(OntologyClass(name: "Person", parent: "Entity"))
    try await store.defineClass(OntologyClass(name: "Employee", parent: "Person"))

    // Test
    #expect(try await reasoner.isSubclassOf("Employee", of: "Person"))
    #expect(try await reasoner.isSubclassOf("Employee", of: "Entity"))
    #expect(!(try await reasoner.isSubclassOf("Person", of: "Employee")))
}

@Test("Symmetric reasoning")
func testSymmetric() async throws {
    let reasoner = OntologyReasoner(store: store)

    // Setup
    try await store.definePredicate(OntologyPredicate(name: "knows", domain: "Person", range: "Person"))
    try await store.defineConstraint(OntologyConstraint(predicate: "knows", constraintType: .symmetric))

    // Test
    let reversed = try await reasoner.inferSymmetric((subject: "Alice", predicate: "knows", object: "Bob"))
    #expect(reversed?.subject == "Bob")
    #expect(reversed?.object == "Alice")
}
```

---

## References

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [DATA_MODEL.md](DATA_MODEL.md) - Data models
- [API_DESIGN.md](API_DESIGN.md) - API specifications
- [OWL 2 Web Ontology Language](https://www.w3.org/TR/owl2-overview/)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
