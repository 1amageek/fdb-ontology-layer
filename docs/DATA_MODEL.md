# fdb-ontology-layer Data Model

## Overview

This document defines the core data structures used in `fdb-ontology-layer`. All models are designed to be:
- **Codable**: JSON serialization for FoundationDB storage
- **Hashable**: Efficient caching and deduplication
- **Sendable**: Safe concurrent access across actors

## Core Models

### 1. OntologyClass

Represents a semantic class (entity type) in the ontology.

```swift
public struct OntologyClass: Codable, Hashable, Sendable {
    /// Unique class name (e.g., "Person", "Organization", "Event")
    public let name: String

    /// Parent class name for inheritance (nil for root classes)
    public let parent: String?

    /// Human-readable description of this class
    public let description: String?

    /// List of predicate names applicable to instances of this class
    public let properties: [String]?

    /// Custom metadata (extensible)
    public let metadata: [String: String]?

    public init(
        name: String,
        parent: String? = nil,
        description: String? = nil,
        properties: [String]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.parent = parent
        self.description = description
        self.properties = properties
        self.metadata = metadata
    }
}
```

#### Examples

```swift
// Root class
let entity = OntologyClass(
    name: "Entity",
    description: "The root of all entities"
)

// Person inherits from Entity
let person = OntologyClass(
    name: "Person",
    parent: "Entity",
    description: "A human being",
    properties: ["name", "birthDate", "knows", "worksFor"]
)

// Organization inherits from Entity
let organization = OntologyClass(
    name: "Organization",
    parent: "Entity",
    description: "A formal organization",
    properties: ["name", "foundedDate", "industry"]
)
```

#### Class Hierarchy Example

```
Entity
  ├─ Person
  │   ├─ Student
  │   └─ Employee
  ├─ Organization
  │   ├─ Company
  │   └─ University
  └─ Event
      ├─ Meeting
      └─ Conference
```

### 2. OntologyPredicate

Represents a relationship or property with domain and range constraints.

```swift
public struct OntologyPredicate: Codable, Hashable, Sendable {
    /// Unique predicate name (e.g., "knows", "worksFor", "hasTitle")
    public let name: String

    /// Domain: class name for valid subjects (e.g., "Person")
    public let domain: String

    /// Range: class name for valid objects (e.g., "Organization")
    public let range: String

    /// Human-readable description
    public let description: String?

    /// Whether this predicate represents a data property (vs object property)
    /// Data properties have literal values (String, Int, etc.)
    /// Object properties have entity references
    public let isDataProperty: Bool

    /// Custom metadata
    public let metadata: [String: String]?

    public init(
        name: String,
        domain: String,
        range: String,
        description: String? = nil,
        isDataProperty: Bool = false,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.domain = domain
        self.range = range
        self.description = description
        self.isDataProperty = isDataProperty
        self.metadata = metadata
    }
}
```

#### Examples

```swift
// Object property: Person knows Person
let knows = OntologyPredicate(
    name: "knows",
    domain: "Person",
    range: "Person",
    description: "A person knows another person",
    isDataProperty: false
)

// Object property: Person worksFor Organization
let worksFor = OntologyPredicate(
    name: "worksFor",
    domain: "Person",
    range: "Organization",
    description: "A person works for an organization",
    isDataProperty: false
)

// Data property: Person has name (String)
let hasName = OntologyPredicate(
    name: "name",
    domain: "Person",
    range: "String",
    description: "The name of a person",
    isDataProperty: true
)

// Data property: Person has birthDate (Date)
let hasBirthDate = OntologyPredicate(
    name: "birthDate",
    domain: "Person",
    range: "Date",
    description: "The birth date of a person",
    isDataProperty: true
)
```

### 3. OntologyConstraint

Represents additional semantic constraints on predicates (OWL-like property characteristics).

```swift
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
```

#### Examples

```swift
// Symmetric: knows
let knowsSymmetric = OntologyConstraint(
    predicate: "knows",
    constraintType: .symmetric,
    description: "If A knows B, then B knows A"
)

// Transitive: ancestor
let ancestorTransitive = OntologyConstraint(
    predicate: "ancestor",
    constraintType: .transitive,
    description: "If A is ancestor of B, and B is ancestor of C, then A is ancestor of C"
)

// Functional: birthDate (each person has exactly one birthDate)
let birthDateFunctional = OntologyConstraint(
    predicate: "birthDate",
    constraintType: .functional,
    description: "Each person has exactly one birth date"
)

// Cardinality: knows (each person knows at least 0 people)
let knowsCardinality = OntologyConstraint(
    predicate: "knows",
    constraintType: .cardinality,
    parameters: ["min": "0", "max": "unbounded"],
    description: "A person can know any number of people"
)

// Inverse: worksFor ↔ employs
let worksForInverse = OntologyConstraint(
    predicate: "worksFor",
    constraintType: .inverse,
    parameters: ["inversePredicate": "employs"],
    description: "If A worksFor B, then B employs A"
)
```

### 4. OntologySnippet

Lightweight text representation of ontology for LLM integration.

```swift
public struct OntologySnippet: Codable, Sendable {
    /// Class name
    public let className: String

    /// Class description
    public let description: String

    /// Parent class (if any)
    public let parent: String?

    /// Predicates with descriptions
    /// Key: predicate name, Value: description
    public let predicates: [String: String]

    /// Example instances (optional)
    public let examples: [String]?

    public init(
        className: String,
        description: String,
        parent: String? = nil,
        predicates: [String: String],
        examples: [String]? = nil
    ) {
        self.className = className
        self.description = description
        self.parent = parent
        self.predicates = predicates
        self.examples = examples
    }
}

extension OntologySnippet {
    /// Render snippet as formatted text for LLM prompts
    public func render() -> String {
        var text = "Class: \(className)\n"

        if let parent = parent {
            text += "Inherits from: \(parent)\n"
        }

        text += "Description: \(description)\n\n"

        text += "Predicates:\n"
        for (name, desc) in predicates.sorted(by: { $0.key < $1.key }) {
            text += "  - \(name): \(desc)\n"
        }

        if let examples = examples, !examples.isEmpty {
            text += "\nExamples:\n"
            for example in examples {
                text += "  - \(example)\n"
            }
        }

        return text
    }
}
```

#### Example

```swift
let personSnippet = OntologySnippet(
    className: "Person",
    description: "A human being with identity and relationships",
    parent: "Entity",
    predicates: [
        "name": "The person's full name",
        "birthDate": "The person's date of birth",
        "knows": "Another person this person knows",
        "worksFor": "The organization this person works for"
    ],
    examples: ["Alice", "Bob", "Charlie"]
)

print(personSnippet.render())
```

Output:
```
Class: Person
Inherits from: Entity
Description: A human being with identity and relationships

Predicates:
  - birthDate: The person's date of birth
  - knows: Another person this person knows
  - name: The person's full name
  - worksFor: The organization this person works for

Examples:
  - Alice
  - Bob
  - Charlie
```

### 5. OntologyVersion

Tracks ontology changes over time.

```swift
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
```

#### Example

```swift
let v1 = OntologyVersion(
    version: 1,
    timestamp: Date(),
    changes: [
        OntologyChange(changeType: .addClass, entity: "Entity"),
        OntologyChange(changeType: .addClass, entity: "Person"),
        OntologyChange(changeType: .addPredicate, entity: "knows")
    ],
    comment: "Initial ontology setup"
)
```

## Validation Rules

### Class Validation

```swift
func validateClass(_ cls: OntologyClass) throws {
    // 1. Name must be non-empty
    guard !cls.name.isEmpty else {
        throw OntologyError.invalidDefinition("Class name cannot be empty")
    }

    // 2. Name must be alphanumeric (allow underscores)
    let nameRegex = /^[A-Za-z][A-Za-z0-9_]*$/
    guard cls.name.wholeMatch(of: nameRegex) != nil else {
        throw OntologyError.invalidDefinition("Class name must be alphanumeric")
    }

    // 3. If parent exists, it must be defined
    if let parent = cls.parent {
        guard try await classExists(parent) else {
            throw OntologyError.classNotFound(parent)
        }

        // 4. Check for circular inheritance
        guard try await !hasCircularInheritance(cls.name, parent: parent) else {
            throw OntologyError.circularHierarchy("Class \(cls.name) creates circular inheritance")
        }
    }
}
```

### Predicate Validation

```swift
func validatePredicate(_ predicate: OntologyPredicate) throws {
    // 1. Name must be non-empty
    guard !predicate.name.isEmpty else {
        throw OntologyError.invalidDefinition("Predicate name cannot be empty")
    }

    // 2. Domain and range must be defined
    guard try await classExists(predicate.domain) else {
        throw OntologyError.classNotFound(predicate.domain)
    }

    guard predicate.isDataProperty || (try await classExists(predicate.range)) else {
        throw OntologyError.classNotFound(predicate.range)
    }

    // 3. Name must be camelCase
    let nameRegex = /^[a-z][A-Za-z0-9]*$/
    guard predicate.name.wholeMatch(of: nameRegex) != nil else {
        throw OntologyError.invalidDefinition("Predicate name must be camelCase")
    }
}
```

### Constraint Validation

```swift
func validateConstraint(_ constraint: OntologyConstraint) throws {
    // 1. Predicate must be defined
    guard try await predicateExists(constraint.predicate) else {
        throw OntologyError.predicateNotFound(constraint.predicate)
    }

    // 2. Validate parameters based on constraint type
    switch constraint.constraintType {
    case .cardinality:
        guard let min = constraint.parameters?["min"],
              let max = constraint.parameters?["max"] else {
            throw OntologyError.invalidDefinition("Cardinality constraint requires 'min' and 'max' parameters")
        }

    case .inverse:
        guard let inversePredicate = constraint.parameters?["inversePredicate"] else {
            throw OntologyError.invalidDefinition("Inverse constraint requires 'inversePredicate' parameter")
        }
        guard try await predicateExists(inversePredicate) else {
            throw OntologyError.predicateNotFound(inversePredicate)
        }

    case .symmetric, .transitive, .functional, .inverseFunctional, .unique:
        // No additional parameters required
        break
    }
}
```

## Type System

### Built-in Data Types

For data properties (`isDataProperty: true`), the following built-in types are supported:

| Type | Description | Example |
|------|-------------|---------|
| `String` | Text data | "Alice", "Hello World" |
| `Int` | Integer numbers | 42, -100 |
| `Float` | Floating-point numbers | 3.14, -0.5 |
| `Bool` | Boolean values | true, false |
| `Date` | ISO 8601 dates | "2025-10-30T10:00:00Z" |
| `URI` | URIs/URLs | "http://example.org/person/1" |

### Type Hierarchy

```
Entity (root)
  ├─ Literal
  │   ├─ String
  │   ├─ Int
  │   ├─ Float
  │   ├─ Bool
  │   └─ Date
  └─ Resource
      ├─ Person
      ├─ Organization
      └─ ...
```

### Type Compatibility Rules

```swift
func isCompatible(subjectClass: String, predicate: OntologyPredicate, objectClass: String) async throws -> Bool {
    // 1. Check domain compatibility
    guard try await isSubclassOf(subjectClass, of: predicate.domain) else {
        return false
    }

    // 2. Check range compatibility
    guard try await isSubclassOf(objectClass, of: predicate.range) else {
        return false
    }

    return true
}

func isSubclassOf(_ childClass: String, of parentClass: String) async throws -> Bool {
    if childClass == parentClass {
        return true
    }

    guard let child = try await getClass(named: childClass) else {
        return false
    }

    if let parent = child.parent {
        return try await isSubclassOf(parent, of: parentClass)
    }

    return false
}
```

## Serialization Format

### JSON Encoding

All models use standard JSON encoding:

```json
// OntologyClass
{
  "name": "Person",
  "parent": "Entity",
  "description": "A human being",
  "properties": ["name", "birthDate", "knows", "worksFor"],
  "metadata": {
    "source": "schema.org",
    "version": "1.0"
  }
}

// OntologyPredicate
{
  "name": "knows",
  "domain": "Person",
  "range": "Person",
  "description": "A person knows another person",
  "isDataProperty": false,
  "metadata": {}
}

// OntologyConstraint
{
  "predicate": "knows",
  "constraintType": "symmetric",
  "parameters": null,
  "description": "If A knows B, then B knows A"
}
```

### Size Limits

| Model | Max Size | Notes |
|-------|----------|-------|
| OntologyClass | 10 KB | Includes all fields |
| OntologyPredicate | 5 KB | Relatively small |
| OntologyConstraint | 2 KB | Minimal data |
| OntologySnippet | 50 KB | Can include large descriptions |

## References

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md) - FoundationDB key structure
- [API_DESIGN.md](API_DESIGN.md) - API specifications
- [REASONING.md](REASONING.md) - Inference logic

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
