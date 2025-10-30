# fdb-ontology-layer API Design

## Overview

This document defines the public API for `fdb-ontology-layer`. The API is designed to be:
- **Type-safe**: Leverage Swift's type system
- **Async/await**: Modern Swift concurrency
- **Actor-isolated**: Thread-safe by design
- **Composable**: Easy integration with other layers

## API Structure

```
OntologyLayer (namespace)
├── OntologyStore (actor)         → Core storage and retrieval
├── OntologyValidator (actor)     → Validation logic
├── OntologyReasoner (actor)      → Basic reasoning
└── Models (structs/enums)        → Data types
```

## 1. OntologyStore

Primary interface for ontology management.

### Actor Definition

```swift
public actor OntologyStore {
    // Internal dependencies
    private let database: any DatabaseProtocol
    private let rootPrefix: String
    private let logger: Logger

    // Caching
    private var classCache: [String: OntologyClass] = [:]
    private var predicateCache: [String: OntologyPredicate] = [:]

    public init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        logger: Logger? = nil
    ) {
        self.database = database
        self.rootPrefix = rootPrefix
        self.logger = logger ?? Logger(label: "com.ontology.store")
    }
}
```

### Class Management

#### defineClass

Define or update an ontology class.

```swift
public func defineClass(_ cls: OntologyClass) async throws
```

**Parameters**:
- `cls`: The class definition to store

**Throws**:
- `OntologyError.invalidDefinition`: If class name is invalid
- `OntologyError.classNotFound`: If parent class doesn't exist
- `OntologyError.circularHierarchy`: If class creates circular inheritance

**Example**:
```swift
let person = OntologyClass(
    name: "Person",
    parent: "Entity",
    description: "A human being"
)
try await ontologyStore.defineClass(person)
```

**Side Effects**:
- Increments version counter
- Updates hierarchy indexes
- Invalidates snippet cache

#### getClass

Retrieve a class definition by name.

```swift
public func getClass(named name: String) async throws -> OntologyClass?
```

**Parameters**:
- `name`: Class name to retrieve

**Returns**: `OntologyClass` if found, `nil` otherwise

**Example**:
```swift
if let person = try await ontologyStore.getClass(named: "Person") {
    print("Found class: \(person.name)")
}
```

#### allClasses

Retrieve all defined classes.

```swift
public func allClasses() async throws -> [OntologyClass]
```

**Returns**: Array of all classes (sorted by name)

**Example**:
```swift
let classes = try await ontologyStore.allClasses()
for cls in classes {
    print("Class: \(cls.name)")
}
```

#### deleteClass

Delete a class definition.

```swift
public func deleteClass(named name: String) async throws
```

**Parameters**:
- `name`: Class name to delete

**Throws**:
- `OntologyError.classNotFound`: If class doesn't exist
- `OntologyError.dependencyExists`: If predicates reference this class

**Example**:
```swift
try await ontologyStore.deleteClass(named: "ObsoleteClass")
```

**Side Effects**:
- Removes hierarchy entries
- Increments version counter
- Deletes cached snippets

#### getSubclasses

Get all direct subclasses of a class.

```swift
public func getSubclasses(of className: String) async throws -> [String]
```

**Parameters**:
- `className`: Parent class name

**Returns**: Array of direct subclass names

**Example**:
```swift
let subclasses = try await ontologyStore.getSubclasses(of: "Entity")
// Returns: ["Person", "Organization", "Event"]
```

#### getSuperclasses

Get all ancestor classes (full hierarchy path).

```swift
public func getSuperclasses(of className: String) async throws -> [String]
```

**Parameters**:
- `className`: Child class name

**Returns**: Array of ancestor class names (ordered from parent to root)

**Example**:
```swift
let ancestors = try await ontologyStore.getSuperclasses(of: "Employee")
// Returns: ["Person", "Entity"]
```

### Predicate Management

#### definePredicate

Define or update an ontology predicate.

```swift
public func definePredicate(_ predicate: OntologyPredicate) async throws
```

**Parameters**:
- `predicate`: The predicate definition to store

**Throws**:
- `OntologyError.invalidDefinition`: If predicate name is invalid
- `OntologyError.classNotFound`: If domain or range class doesn't exist

**Example**:
```swift
let knows = OntologyPredicate(
    name: "knows",
    domain: "Person",
    range: "Person",
    description: "A person knows another person"
)
try await ontologyStore.definePredicate(knows)
```

#### getPredicate

Retrieve a predicate definition by name.

```swift
public func getPredicate(named name: String) async throws -> OntologyPredicate?
```

**Parameters**:
- `name`: Predicate name to retrieve

**Returns**: `OntologyPredicate` if found, `nil` otherwise

**Example**:
```swift
if let knows = try await ontologyStore.getPredicate(named: "knows") {
    print("Domain: \(knows.domain), Range: \(knows.range)")
}
```

#### allPredicates

Retrieve all defined predicates.

```swift
public func allPredicates() async throws -> [OntologyPredicate]
```

**Returns**: Array of all predicates (sorted by name)

**Example**:
```swift
let predicates = try await ontologyStore.allPredicates()
for pred in predicates {
    print("Predicate: \(pred.name) (\(pred.domain) → \(pred.range))")
}
```

#### getPredicatesByDomain

Retrieve all predicates applicable to a class.

```swift
public func getPredicatesByDomain(_ domain: String) async throws -> [OntologyPredicate]
```

**Parameters**:
- `domain`: Class name to filter by

**Returns**: Array of predicates with matching domain

**Example**:
```swift
let personPredicates = try await ontologyStore.getPredicatesByDomain("Person")
// Returns: [knows, worksFor, hasName, birthDate, ...]
```

#### deletePredicate

Delete a predicate definition.

```swift
public func deletePredicate(named name: String) async throws
```

**Parameters**:
- `name`: Predicate name to delete

**Throws**:
- `OntologyError.predicateNotFound`: If predicate doesn't exist

**Example**:
```swift
try await ontologyStore.deletePredicate(named: "obsoleteRelation")
```

### Constraint Management

#### defineConstraint

Define a constraint on a predicate.

```swift
public func defineConstraint(_ constraint: OntologyConstraint) async throws
```

**Parameters**:
- `constraint`: The constraint definition to store

**Throws**:
- `OntologyError.predicateNotFound`: If predicate doesn't exist
- `OntologyError.invalidDefinition`: If constraint parameters are invalid

**Example**:
```swift
let symmetric = OntologyConstraint(
    predicate: "knows",
    constraintType: .symmetric,
    description: "If A knows B, then B knows A"
)
try await ontologyStore.defineConstraint(symmetric)
```

#### getConstraints

Retrieve all constraints for a predicate.

```swift
public func getConstraints(for predicateName: String) async throws -> [OntologyConstraint]
```

**Parameters**:
- `predicateName`: Predicate name to filter by

**Returns**: Array of constraints for the predicate

**Example**:
```swift
let constraints = try await ontologyStore.getConstraints(for: "knows")
// Returns: [symmetric constraint]
```

#### deleteConstraint

Delete a constraint.

```swift
public func deleteConstraint(predicate: String, type: ConstraintType) async throws
```

**Parameters**:
- `predicate`: Predicate name
- `type`: Constraint type to delete

**Throws**:
- `OntologyError.constraintNotFound`: If constraint doesn't exist

**Example**:
```swift
try await ontologyStore.deleteConstraint(predicate: "knows", type: .symmetric)
```

### Snippet Generation

#### snippet

Generate a lightweight ontology representation for LLM prompts.

```swift
public func snippet(for className: String) async throws -> String
```

**Parameters**:
- `className`: Class name to generate snippet for

**Returns**: Formatted text snippet

**Throws**:
- `OntologyError.classNotFound`: If class doesn't exist

**Example**:
```swift
let snippet = try await ontologyStore.snippet(for: "Person")
print(snippet)
```

Output:
```
Class: Person
Inherits from: Entity
Description: A human being

Predicates:
  - birthDate: The person's date of birth
  - knows: Another person this person knows
  - name: The person's full name
  - worksFor: The organization this person works for
```

#### fullSnippet

Generate an extended snippet including examples and hierarchy.

```swift
public func fullSnippet(for className: String, includeSubclasses: Bool = false) async throws -> String
```

**Parameters**:
- `className`: Class name to generate snippet for
- `includeSubclasses`: Whether to include subclass information

**Returns**: Extended formatted text snippet

**Example**:
```swift
let snippet = try await ontologyStore.fullSnippet(for: "Entity", includeSubclasses: true)
```

Output:
```
Class: Entity
Description: The root of all entities

Subclasses:
  - Person: A human being
  - Organization: A formal organization
  - Event: A temporal event

Predicates:
  (inherited by all subclasses)
```

### Versioning

#### currentVersion

Get the current ontology version number.

```swift
public func currentVersion() async throws -> UInt64
```

**Returns**: Current version number

**Example**:
```swift
let version = try await ontologyStore.currentVersion()
print("Ontology version: \(version)")
```

#### getVersion

Get version metadata for a specific version.

```swift
public func getVersion(_ version: UInt64) async throws -> OntologyVersion?
```

**Parameters**:
- `version`: Version number to retrieve

**Returns**: `OntologyVersion` if found, `nil` otherwise

**Example**:
```swift
if let v1 = try await ontologyStore.getVersion(1) {
    print("Changes in v1: \(v1.changes.count)")
}
```

#### allVersions

Get all version records.

```swift
public func allVersions() async throws -> [OntologyVersion]
```

**Returns**: Array of all versions (sorted by version number)

**Example**:
```swift
let versions = try await ontologyStore.allVersions()
for ver in versions {
    print("Version \(ver.version): \(ver.comment ?? "No comment")")
}
```

### Statistics

#### statistics

Get ontology statistics.

```swift
public func statistics() async throws -> OntologyStatistics
```

**Returns**: Statistics struct with counts and metadata

**Example**:
```swift
let stats = try await ontologyStore.statistics()
print("Classes: \(stats.classCount)")
print("Predicates: \(stats.predicateCount)")
print("Constraints: \(stats.constraintCount)")
```

```swift
public struct OntologyStatistics: Codable {
    public let classCount: UInt64
    public let predicateCount: UInt64
    public let constraintCount: UInt64
    public let currentVersion: UInt64
    public let createdAt: Date?
    public let lastUpdated: Date?
}
```

---

## 2. OntologyValidator

Validates triples and knowledge records against the ontology.

### Actor Definition

```swift
public actor OntologyValidator {
    private let store: OntologyStore
    private let logger: Logger

    public init(
        store: OntologyStore,
        logger: Logger? = nil
    ) {
        self.store = store
        self.logger = logger ?? Logger(label: "com.ontology.validator")
    }
}
```

### Triple Validation

#### validate (Triple)

Validate a complete triple against the ontology.

```swift
public func validate(_ triple: (subject: String, predicate: String, object: String)) async throws -> ValidationResult
```

**Parameters**:
- `triple`: Tuple of (subject class, predicate name, object class)

**Returns**: `ValidationResult` with success status and details

**Example**:
```swift
let result = try await validator.validate(
    (subject: "Person", predicate: "knows", object: "Person")
)

if result.isValid {
    print("Valid triple")
} else {
    print("Errors: \(result.errors)")
}
```

```swift
public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [ValidationError]
    public let warnings: [String]
}

public struct ValidationError: Sendable {
    public let message: String
    public let errorType: ErrorType

    public enum ErrorType: String, Sendable {
        case predicateNotFound
        case domainMismatch
        case rangeMismatch
        case constraintViolation
    }
}
```

#### validateDomain

Check if a subject class matches the predicate's domain.

```swift
public func validateDomain(
    subject: String,
    predicate: String
) async throws -> Bool
```

**Parameters**:
- `subject`: Subject class name
- `predicate`: Predicate name

**Returns**: `true` if subject is compatible with predicate domain

**Example**:
```swift
let valid = try await validator.validateDomain(
    subject: "Employee",  // subclass of Person
    predicate: "knows"    // domain: Person
)
// Returns: true (Employee ⊆ Person)
```

#### validateRange

Check if an object class matches the predicate's range.

```swift
public func validateRange(
    predicate: String,
    object: String
) async throws -> Bool
```

**Parameters**:
- `predicate`: Predicate name
- `object`: Object class name

**Returns**: `true` if object is compatible with predicate range

**Example**:
```swift
let valid = try await validator.validateRange(
    predicate: "worksFor",    // range: Organization
    object: "Company"         // subclass of Organization
)
// Returns: true (Company ⊆ Organization)
```

### Constraint Validation

#### validateConstraints

Validate all constraints for a given triple pattern.

```swift
public func validateConstraints(
    predicate: String,
    existingTriples: [(subject: String, object: String)]
) async throws -> [ConstraintViolation]
```

**Parameters**:
- `predicate`: Predicate name
- `existingTriples`: Existing triples with this predicate

**Returns**: Array of constraint violations (empty if all valid)

**Example**:
```swift
let violations = try await validator.validateConstraints(
    predicate: "birthDate",
    existingTriples: [
        (subject: "Alice", object: "1990-01-01"),
        (subject: "Alice", object: "1991-01-01")  // Duplicate!
    ]
)

if !violations.isEmpty {
    print("Constraint violations:")
    for violation in violations {
        print("  - \(violation.message)")
    }
}
```

```swift
public struct ConstraintViolation: Sendable {
    public let constraint: OntologyConstraint
    public let message: String
    public let affectedTriples: [(subject: String, object: String)]
}
```

### Batch Validation

#### validateBatch

Validate multiple triples at once (more efficient than individual validation).

```swift
public func validateBatch(
    _ triples: [(subject: String, predicate: String, object: String)]
) async throws -> [ValidationResult]
```

**Parameters**:
- `triples`: Array of triples to validate

**Returns**: Array of validation results (one per triple)

**Example**:
```swift
let triples = [
    (subject: "Person", predicate: "knows", object: "Person"),
    (subject: "Person", predicate: "worksFor", object: "Organization"),
    (subject: "Person", predicate: "invalid", object: "Thing")
]

let results = try await validator.validateBatch(triples)
for (i, result) in results.enumerated() {
    print("Triple \(i): \(result.isValid ? "✓" : "✗")")
}
```

---

## 3. OntologyReasoner

Performs basic reasoning tasks (subsumption, property propagation).

### Actor Definition

```swift
public actor OntologyReasoner {
    private let store: OntologyStore
    private let logger: Logger

    public init(
        store: OntologyStore,
        logger: Logger? = nil
    ) {
        self.store = store
        self.logger = logger ?? Logger(label: "com.ontology.reasoner")
    }
}
```

### Class Hierarchy Reasoning

#### isSubclassOf

Check if one class is a subclass of another (supports transitivity).

```swift
public func isSubclassOf(
    _ childClass: String,
    of parentClass: String
) async throws -> Bool
```

**Parameters**:
- `childClass`: Potential subclass name
- `parentClass`: Potential superclass name

**Returns**: `true` if childClass ⊆ parentClass

**Example**:
```swift
let result = try await reasoner.isSubclassOf("Employee", of: "Entity")
// Returns: true (Employee → Person → Entity)
```

#### lowestCommonAncestor

Find the lowest common ancestor of two classes.

```swift
public func lowestCommonAncestor(
    _ class1: String,
    _ class2: String
) async throws -> String?
```

**Parameters**:
- `class1`: First class name
- `class2`: Second class name

**Returns**: Name of lowest common ancestor, or `nil` if no common ancestor

**Example**:
```swift
let lca = try await reasoner.lowestCommonAncestor("Employee", "Student")
// Returns: "Person"
```

### Property Reasoning

#### inferType

Infer the type of an entity based on predicate usage.

```swift
public func inferType(
    from predicates: [String]
) async throws -> [String]
```

**Parameters**:
- `predicates`: List of predicates used by an entity

**Returns**: Possible class names that have these predicates

**Example**:
```swift
let types = try await reasoner.inferType(from: ["name", "worksFor", "knows"])
// Returns: ["Person", "Employee"]
```

#### propagateSymmetry

Apply symmetric property inference.

```swift
public func propagateSymmetry(
    _ triple: (subject: String, predicate: String, object: String)
) async throws -> (subject: String, predicate: String, object: String)?
```

**Parameters**:
- `triple`: Original triple

**Returns**: Inferred reverse triple if predicate is symmetric, `nil` otherwise

**Example**:
```swift
let reversed = try await reasoner.propagateSymmetry(
    (subject: "Alice", predicate: "knows", object: "Bob")
)
// Returns: (subject: "Bob", predicate: "knows", object: "Alice")
```

#### propagateTransitivity

Apply transitive property closure.

```swift
public func propagateTransitivity(
    predicate: String,
    triples: [(subject: String, object: String)]
) async throws -> [(subject: String, object: String)]
```

**Parameters**:
- `predicate`: Transitive predicate name
- `triples`: Existing triples

**Returns**: Additional triples inferred by transitivity

**Example**:
```swift
let existing = [
    (subject: "Alice", object: "Bob"),
    (subject: "Bob", object: "Charlie")
]

let inferred = try await reasoner.propagateTransitivity(
    predicate: "ancestor",
    triples: existing
)
// Returns: [(subject: "Alice", object: "Charlie")]
```

---

## 4. Error Types

All ontology operations may throw the following errors:

```swift
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
```

---

## 5. Usage Examples

### Complete Workflow Example

```swift
import OntologyLayer
import FoundationDB

// 1. Initialize FoundationDB
try await FDBClient.initialize()
let database = try FDBClient.openDatabase()

// 2. Create ontology store
let ontologyStore = OntologyStore(
    database: database,
    rootPrefix: "myapp"
)

// 3. Define ontology
let entity = OntologyClass(name: "Entity", description: "Root class")
try await ontologyStore.defineClass(entity)

let person = OntologyClass(
    name: "Person",
    parent: "Entity",
    description: "A human being",
    properties: ["name", "birthDate", "knows", "worksFor"]
)
try await ontologyStore.defineClass(person)

let organization = OntologyClass(
    name: "Organization",
    parent: "Entity",
    description: "A formal organization"
)
try await ontologyStore.defineClass(organization)

// 4. Define predicates
let knows = OntologyPredicate(
    name: "knows",
    domain: "Person",
    range: "Person",
    description: "A person knows another person"
)
try await ontologyStore.definePredicate(knows)

let worksFor = OntologyPredicate(
    name: "worksFor",
    domain: "Person",
    range: "Organization",
    description: "A person works for an organization"
)
try await ontologyStore.definePredicate(worksFor)

// 5. Define constraints
let knowsSymmetric = OntologyConstraint(
    predicate: "knows",
    constraintType: .symmetric
)
try await ontologyStore.defineConstraint(knowsSymmetric)

// 6. Validate triples
let validator = OntologyValidator(store: ontologyStore)

let result1 = try await validator.validate(
    (subject: "Person", predicate: "knows", object: "Person")
)
print("Valid: \(result1.isValid)")  // true

let result2 = try await validator.validate(
    (subject: "Person", predicate: "worksFor", object: "Person")
)
print("Valid: \(result2.isValid)")  // false (range mismatch)

// 7. Generate LLM snippet
let snippet = try await ontologyStore.snippet(for: "Person")
print(snippet)

// 8. Check statistics
let stats = try await ontologyStore.statistics()
print("Total classes: \(stats.classCount)")
print("Total predicates: \(stats.predicateCount)")
```

---

## 6. Performance Considerations

### Caching Strategy

All read operations leverage in-memory caching:
- **Classes**: 1,000 entry LRU cache
- **Predicates**: 5,000 entry LRU cache
- **Constraints**: 2,000 entry LRU cache

### Batch Operations

Always prefer batch operations for multiple entities:

```swift
// ❌ Slow: Individual validation
for triple in triples {
    let result = try await validator.validate(triple)
}

// ✓ Fast: Batch validation
let results = try await validator.validateBatch(triples)
```

### Snapshot Reads

All read-only operations use FDB snapshot isolation for consistency without conflicts.

---

## 7. References

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [DATA_MODEL.md](DATA_MODEL.md) - Data model specifications
- [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md) - FoundationDB key structure
- [REASONING.md](REASONING.md) - Reasoning logic details

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
