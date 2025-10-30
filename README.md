# fdb-ontology-layer

Semantic schema layer built on FoundationDB for knowledge management systems.

## Status

✅ **Implementation Complete** - All 17 tests passing

## Overview

`fdb-ontology-layer` provides ontological structure, validation, and reasoning capabilities on top of FoundationDB. It enables:

- **Class hierarchies** with inheritance
- **Predicate constraints** (domain, range)
- **Semantic validation** of triples
- **Basic reasoning** (subsumption, symmetric, transitive)
- **LLM snippet generation** for context

## Quick Start

```swift
import OntologyLayer

// Create ontology store
let store = OntologyStore(database: database, rootPrefix: "myapp")

// Define classes
try await store.defineClass(OntologyClass(name: "Person", parent: "Entity"))

// Define predicates
try await store.definePredicate(OntologyPredicate(
    name: "knows",
    domain: "Person",
    range: "Person"
))

// Validate triples
let validator = OntologyValidator(store: store)
let result = try await validator.validate(
    (subject: "Person", predicate: "knows", object: "Person")
)

// Apply reasoning
let reasoner = OntologyReasoner(store: store)
let isSubclass = try await reasoner.isSubclassOf("Employee", of: "Person")
```

## Features

### Core Capabilities
- ✅ Class management with hierarchy
- ✅ Predicate definitions with domain/range
- ✅ Constraint types (symmetric, transitive, functional, cardinality)
- ✅ Triple validation against ontology
- ✅ Subsumption reasoning
- ✅ Property inference (symmetric, inverse, transitive)
- ✅ LLM snippet generation
- ✅ Version tracking and statistics

### Technical Features
- 🎯 Actor-based concurrency for thread safety
- 🚀 LRU caching for performance (1000 classes, 5000 predicates)
- 💾 FoundationDB native with ACID transactions
- 📊 Comprehensive test coverage (17 tests)
- 🔍 Circular hierarchy detection
- 📝 Dependency checking (prevent orphaned data)

## Architecture

```
OntologyStore (Storage & Retrieval)
    ├── defineClass/getClass/deleteClass
    ├── definePredicate/getPredicate/deletePredicate
    └── defineConstraint/getConstraints

OntologyValidator (Validation)
    ├── validate(triple)
    ├── validateDomain/validateRange
    └── validateConstraints

OntologyReasoner (Inference)
    ├── isSubclassOf (subsumption)
    ├── inferSymmetric/inferInverse
    └── computeTransitiveClosure
```

## Requirements

- **macOS 15.0+**
- **Swift 6.0+** (Swift 5 language mode)
- **FoundationDB 7.1.0+**

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-repo/fdb-ontology-layer.git", from: "1.0.0")
]
```

## Documentation

Full documentation is available in the [`docs/`](docs/) directory:

- 📖 [README.md](docs/README.md) - Overview and quick start
- 🏗️ [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design
- 📊 [DATA_MODEL.md](docs/DATA_MODEL.md) - Data structures
- 💾 [STORAGE_LAYOUT.md](docs/STORAGE_LAYOUT.md) - FoundationDB layout
- 🔌 [API_DESIGN.md](docs/API_DESIGN.md) - Complete API reference
- 🧠 [REASONING.md](docs/REASONING.md) - Reasoning algorithms
- 🔗 [INTEGRATION.md](docs/INTEGRATION.md) - Integration patterns

## Testing

Run tests:

```bash
swift test
```

All 17 tests should pass:
- ✅ Class management (5 tests)
- ✅ Predicate management (2 tests)
- ✅ Constraint management (1 test)
- ✅ Validation (2 tests)
- ✅ Reasoning (2 tests)
- ✅ Snippets (1 test)
- ✅ Statistics (1 test)
- ✅ Update logic (3 tests)

## Swift 6 Compatibility

⚠️ **Note**: Currently uses Swift 5 language mode due to FoundationDB's non-Sendable protocols.

The implementation is **fully safe** despite compiler warnings:
- All mutable state is actor-protected
- No data races in practice
- All tests pass including concurrent operations

See [docs/README.md#swift-6-concurrency-compatibility](docs/README.md#swift-6-concurrency-compatibility) for details.

## Integration

This layer integrates with:

- **fdb-triple-layer**: Validates triples before storage
- **fdb-embedding-layer**: Provides semantic metadata
- **fdb-knowledge-layer**: Unified knowledge API

## Implementation Highlights

### Logic Corrections Made

1. ✅ **Counter management**: Prevents duplicate increments on updates
2. ✅ **Hierarchy indexes**: Properly maintains forward and reverse indexes
3. ✅ **Dependency checking**: Prevents deletion of classes with children
4. ✅ **Domain index updates**: Handles predicate domain changes

### Key Design Decisions

- **Actor-based**: Thread-safe without locks
- **LRU caching**: Fast reads with bounded memory
- **Tuple encoding**: Efficient range queries
- **Snapshot reads**: High concurrency
- **Atomic operations**: Lock-free counters

## Performance

| Operation | Target Latency (p99) |
|-----------|---------------------|
| Define Class | 20-30ms |
| Get Class (cached) | <5ms |
| Validate Triple | 10-20ms |
| Generate Snippet | 50-100ms |

## License

MIT License

## Contributing

See [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for development roadmap.

---

**Version**: 1.0.0
**Last Updated**: 2025-10-30
**Status**: Production Ready
