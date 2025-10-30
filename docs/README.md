# fdb-ontology-layer Documentation

## Overview

`fdb-ontology-layer` is a semantic schema layer built on FoundationDB that provides ontological structure, validation, and basic reasoning capabilities for knowledge management systems.

This documentation describes the design, implementation, and usage of the ontology layer.

---

## Documentation Structure

| Document | Description |
|----------|-------------|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | System architecture, components, and design philosophy |
| **[DATA_MODEL.md](DATA_MODEL.md)** | Data structures (OntologyClass, OntologyPredicate, etc.) |
| **[STORAGE_LAYOUT.md](STORAGE_LAYOUT.md)** | FoundationDB key-value layout and encoding |
| **[API_DESIGN.md](API_DESIGN.md)** | Complete API reference (OntologyStore, Validator, Reasoner) |
| **[INTEGRATION.md](INTEGRATION.md)** | Integration patterns with other layers |
| **[REASONING.md](REASONING.md)** | Reasoning logic and inference rules |
| **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** | Phased development roadmap |

---

## Quick Links

### Getting Started
- [Architecture Overview](ARCHITECTURE.md#overview)
- [Data Models](DATA_MODEL.md#core-models)
- [API Quick Start](API_DESIGN.md#5-usage-examples)

### Implementation
- [Storage Design](STORAGE_LAYOUT.md#detailed-key-structures)
- [Transaction Patterns](STORAGE_LAYOUT.md#transaction-patterns)
- [Implementation Phases](IMPLEMENTATION_PLAN.md#phase-1-core-foundation-week-1)

### Integration
- [Triple Layer Integration](INTEGRATION.md#1-integration-with-fdb-triple-layer)
- [Embedding Layer Integration](INTEGRATION.md#2-integration-with-fdb-embedding-layer)
- [Knowledge Layer Integration](INTEGRATION.md#3-integration-with-fdb-knowledge-layer)

### Advanced Topics
- [Reasoning Algorithms](REASONING.md#1-subsumption-reasoning)
- [Performance Optimization](ARCHITECTURE.md#performance-characteristics)
- [Versioning Strategy](ARCHITECTURE.md#versioning-strategy)

---

## Key Concepts

### 1. Ontology Components

```
Ontology
├── Classes (OntologyClass)
│   └── Hierarchical structure (Person ⊆ Entity)
├── Predicates (OntologyPredicate)
│   └── Domain and range constraints
└── Constraints (OntologyConstraint)
    └── Semantic rules (symmetric, transitive, etc.)
```

### 2. Core Operations

| Operation | Description | Document |
|-----------|-------------|----------|
| **Define** | Create ontology definitions | [API_DESIGN.md](API_DESIGN.md#class-management) |
| **Validate** | Check triples against ontology | [API_DESIGN.md](API_DESIGN.md#triple-validation) |
| **Reason** | Infer new knowledge | [REASONING.md](REASONING.md) |
| **Query** | Retrieve ontology components | [API_DESIGN.md](API_DESIGN.md#class-management) |

### 3. Integration Points

```
fdb-knowledge-layer
      │
      ├─► fdb-triple-layer (validates triples)
      ├─► fdb-ontology-layer (provides schema)
      └─► fdb-embedding-layer (semantic metadata)
```

---

## Example Workflow

### 1. Define Ontology

```swift
import OntologyLayer

// Create ontology store
let store = OntologyStore(database: database, rootPrefix: "myapp")

// Define classes
let entity = OntologyClass(name: "Entity", description: "Root class")
try await store.defineClass(entity)

let person = OntologyClass(
    name: "Person",
    parent: "Entity",
    description: "A human being"
)
try await store.defineClass(person)

// Define predicates
let knows = OntologyPredicate(
    name: "knows",
    domain: "Person",
    range: "Person",
    description: "A person knows another person"
)
try await store.definePredicate(knows)

// Define constraints
let symmetric = OntologyConstraint(
    predicate: "knows",
    constraintType: .symmetric
)
try await store.defineConstraint(symmetric)
```

### 2. Validate Triples

```swift
let validator = OntologyValidator(store: store)

let result = try await validator.validate(
    (subject: "Person", predicate: "knows", object: "Person")
)

if result.isValid {
    print("Valid triple")
} else {
    print("Errors: \(result.errors)")
}
```

### 3. Apply Reasoning

```swift
let reasoner = OntologyReasoner(store: store)

// Check subsumption
let isSubclass = try await reasoner.isSubclassOf("Employee", of: "Person")
// Returns: true (if Employee ⊆ Person)

// Infer symmetric relation
let reversed = try await reasoner.inferSymmetric(
    (subject: "Alice", predicate: "knows", object: "Bob")
)
// Returns: (subject: "Bob", predicate: "knows", object: "Alice")
```

### 4. Generate LLM Snippet

```swift
let snippet = try await store.snippet(for: "Person")
print(snippet)
```

Output:
```
Class: Person
Inherits from: Entity
Description: A human being

Predicates:
  - knows: A person knows another person
  - worksFor: A person works for an organization
```

---

## Design Principles

### 1. Minimal Reasoning
Focus on practical reasoning (subsumption, domain/range) rather than full OWL/RDF reasoning.

### 2. Actor-Based Concurrency
All components are actors for thread-safe access.

### 3. FoundationDB Native
Leverage FDB's ACID transactions and scalability.

### 4. Separation of Concerns
- **OntologyStore**: Storage and retrieval
- **OntologyValidator**: Validation logic
- **OntologyReasoner**: Inference logic

### 5. Performance First
Aggressive caching, batch operations, snapshot reads.

---

## Performance Targets

| Operation | Target Latency (p99) | Target Throughput |
|-----------|---------------------|-------------------|
| Define Class | 20-30ms | 500-1000 ops/sec |
| Get Class (cached) | <5ms | 100,000+ ops/sec |
| Validate Triple | 10-20ms | 10,000-20,000 ops/sec |
| Generate Snippet | 50-100ms | 1,000-2,000 ops/sec |

See [ARCHITECTURE.md](ARCHITECTURE.md#performance-characteristics) for details.

---

## Requirements

- **macOS 15.0+**
- **Swift 6.0+** (running in Swift 5 language mode)
- **FoundationDB 7.1.0+**

---

## Swift 6 Concurrency Compatibility

### Current Status

The project is **fully functional** but uses **Swift 5 language mode** due to FoundationDB's current limitations:

✅ **Working**:
- All 17 tests passing
- Actor-based concurrency with proper isolation
- Thread-safe operations

⚠️ **Compiler Warnings** (Swift 6 mode):
```
Sending value of non-Sendable type '(any TransactionProtocol) async throws -> ()'
risks causing data races
```

### Why These Warnings Exist

1. **FoundationDB limitation**: `TransactionProtocol` is not yet `Sendable`-compliant
2. **Actor isolation**: We use `nonisolated(unsafe)` for the database property
3. **Swift 5 vs 6**: These are warnings in Swift 5 mode, but would be **errors** in Swift 6 mode

### Safety Guarantees

Despite the warnings, the implementation is **safe** because:

1. ✅ All mutable state is protected by actor isolation
2. ✅ Database operations are properly sequenced through `withTransaction`
3. ✅ No shared mutable state escapes actor boundaries
4. ✅ All tests pass including concurrency stress tests

### Migration Path

When FoundationDB adopts Swift 6 concurrency:
1. Remove `nonisolated(unsafe)` from database properties
2. Switch to Swift 6 language mode in `Package.swift`
3. Remove `@preconcurrency import FoundationDB`

Until then, the Swift 5 mode provides full functionality without compromising safety.

---

## Project Status

**Current Phase**: ✅ Implementation Complete (v1.0)

**Test Results**: 17/17 tests passing

**Roadmap**:
- ✅ Phase 0: Design and documentation
- ✅ Phase 1: Core foundation (OntologyClass, OntologyPredicate, OntologyConstraint)
- ✅ Phase 2: Storage layer (OntologyStore with CRUD operations)
- ✅ Phase 3: Validation and reasoning (OntologyValidator, OntologyReasoner)
- ✅ Phase 4: Advanced features (Snippet generation, versioning, statistics)
- ✅ Phase 5: Testing and bug fixes (Logic corrections, 17 comprehensive tests)
- ⏳ Phase 6: Integration with other layers

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for detailed roadmap.

---

## Reading Order

### For Users (Application Developers)

1. [ARCHITECTURE.md](ARCHITECTURE.md) - Understand the system
2. [API_DESIGN.md](API_DESIGN.md) - Learn the API
3. [INTEGRATION.md](INTEGRATION.md) - Integrate with your stack

### For Contributors (Library Developers)

1. [ARCHITECTURE.md](ARCHITECTURE.md) - System design
2. [DATA_MODEL.md](DATA_MODEL.md) - Data structures
3. [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md) - FDB layout
4. [REASONING.md](REASONING.md) - Reasoning logic
5. [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - Development phases

### For Researchers (Semantic Web)

1. [ARCHITECTURE.md](ARCHITECTURE.md#design-philosophy) - Design philosophy
2. [REASONING.md](REASONING.md) - Reasoning algorithms
3. [INTEGRATION.md](INTEGRATION.md) - Layer architecture

---

## Contributing

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for development roadmap and contribution guidelines.

---

## License

MIT License (to be added)

---

## References

### External Documentation
- [FoundationDB Documentation](https://apple.github.io/foundationdb/)
- [OWL 2 Web Ontology Language](https://www.w3.org/TR/owl2-overview/)
- [RDF Schema 1.1](https://www.w3.org/TR/rdf-schema/)

### Related Projects
- [fdb-triple-layer](../../fdb-triple-layer/) - Triple storage
- [fdb-embedding-layer](../../fdb-embedding-layer/) - Vector embeddings
- [fdb-knowledge-layer](../../fdb-knowledge-layer/) - Unified knowledge API

---

**Documentation Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
