# fdb-ontology-layer Architecture

## Overview

`fdb-ontology-layer` is a semantic schema layer built on FoundationDB that provides ontological structure, validation, and basic reasoning capabilities for knowledge management systems. It serves as the semantic foundation for `fdb-triple-layer`, `fdb-embedding-layer`, and `fdb-knowledge-layer`.

## Design Philosophy

### Core Principles

1. **Semantic Typing**: Provide type constraints for triples and knowledge records
2. **Hierarchical Structure**: Support class hierarchies with inheritance
3. **Validation**: Enforce domain and range constraints on predicates
4. **Minimal Reasoning**: Implement essential inference (is-a, domain, range)
5. **LLM Integration**: Generate lightweight ontology representations for language models
6. **Versioning**: Track ontology evolution over time

### Non-Goals

- Full OWL/RDF reasoning (intentionally minimal)
- Complex inference chains (leave to higher layers)
- Schema migration tools (manual version management)

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   fdb-knowledge-layer                       │
│  (Unified API, complex reasoning, multi-modal integration)  │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐  ┌─────────▼─────────┐  ┌───────▼────────┐
│ fdb-triple-    │  │ fdb-ontology-     │  │ fdb-embedding- │
│ layer          │◄─┤ layer             │─►│ layer          │
│ (Triple Store) │  │ (Schema/Semantic) │  │ (Vector Store) │
└────────────────┘  └───────────────────┘  └────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │   FoundationDB     │
                    │ (Distributed KVS)  │
                    └────────────────────┘
```

### Layer Responsibilities

| Layer | Responsibility | Uses Ontology For |
|-------|----------------|-------------------|
| **fdb-ontology-layer** | Define & validate semantic structure | - (self-contained) |
| **fdb-triple-layer** | Store triples efficiently | Type validation before insert |
| **fdb-embedding-layer** | Store vector embeddings | Class/concept metadata for embeddings |
| **fdb-knowledge-layer** | Unified knowledge API | Reasoning, validation, integrity checks |

## Components

### 1. Core Data Models

#### OntologyClass
- Defines entity types (Person, Organization, Event, etc.)
- Supports hierarchical inheritance (Person ⊆ Entity)
- Lists applicable properties/predicates

#### OntologyPredicate
- Defines relationships between classes
- Specifies domain (subject type) and range (object type)
- Enables type checking for triples

#### OntologyConstraint
- Defines additional semantic rules (cardinality, uniqueness, symmetry, transitivity)
- Supports OWL-like property characteristics

### 2. Storage Layer

#### SubspaceManager
- Manages FoundationDB subspace organization
- Provides isolated namespaces for different ontology components
- Handles key encoding/decoding

**Subspace Structure**:
```
<rootPrefix>/
  ontology/
    class/<name>          → OntologyClass JSON
    predicate/<name>      → OntologyPredicate JSON
    constraint/<name>     → [OntologyConstraint] JSON
    hierarchy/<child>     → parent class name
    version/<n>           → Version metadata
    snippet/<class>       → LLM-friendly text
```

### 3. API Layer

#### OntologyStore (Actor)
- **Definition APIs**: Define classes, predicates, constraints
- **Query APIs**: Retrieve ontology components
- **Hierarchy APIs**: Navigate class hierarchies
- **Snippet APIs**: Generate LLM-friendly representations

Thread-safe actor-based design ensures safe concurrent access.

#### OntologyValidator (Actor)
- **Triple Validation**: Check (subject, predicate, object) against ontology
- **Type Checking**: Verify instances match expected classes
- **Constraint Checking**: Enforce cardinality, uniqueness, etc.

### 4. Reasoning Engine

#### BasicReasoner
- **Subsumption**: Infer class membership via hierarchy (A ⊆ B)
- **Domain/Range**: Validate triple structure against predicate definitions
- **Property Characteristics**: Apply symmetric, transitive rules

**Example Inferences**:
```
Given:
  Person ⊆ Entity
  Alice is-a Person

Infer:
  Alice is-a Entity
```

## Data Flow Patterns

### Pattern 1: Define Ontology

```
User/System
    │
    ▼
OntologyStore.defineClass(...)
    │
    ▼
SubspaceManager.encodeKey(...)
    │
    ▼
FoundationDB Transaction
    │
    ▼
/ontology/class/<name>
```

### Pattern 2: Validate Triple (Integration with fdb-triple-layer)

```
Triple Insert Request
    │
    ▼
fdb-triple-layer.insert(triple)
    │
    ▼
OntologyValidator.validate(subject, predicate, object)
    │
    ├─► OntologyStore.getPredicate(name)
    │
    ├─► Check domain: isInstance(subject, domain)
    │
    ├─► Check range: isInstance(object, range)
    │
    ▼
Valid? → Proceed with insert
Invalid? → Throw ValidationError
```

### Pattern 3: Generate Snippet for LLM

```
LLM Prompt Generation
    │
    ▼
OntologyStore.snippet(for: "Person")
    │
    ▼
Load OntologyClass("Person")
    │
    ▼
Load related Predicates
    │
    ▼
Format as text snippet
    │
    ▼
Return to LLM prompt builder
```

## Concurrency Model

### Actor-Based Isolation

```swift
public actor OntologyStore {
    // All mutable state is actor-isolated
    private let database: any DatabaseProtocol
    private var classCache: [String: OntologyClass] = [:]
    private var predicateCache: [String: OntologyPredicate] = [:]
}
```

- **Thread Safety**: Actors ensure serial access to mutable state
- **Caching**: In-memory LRU caches reduce database reads
- **Transactions**: FoundationDB provides ACID guarantees

### Cache Strategy

| Cache Type | Size Limit | Eviction Policy | Use Case |
|------------|------------|-----------------|----------|
| Class Cache | 1,000 entries | LRU | Frequently accessed classes |
| Predicate Cache | 5,000 entries | LRU | Common predicates |
| Constraint Cache | 2,000 entries | LRU | Validation rules |

## Transaction Patterns

### Write Operations

```swift
try await database.withTransaction { transaction in
    // 1. Encode key
    let key = subspaceManager.classKey(name: cls.name)

    // 2. Serialize value
    let value = try JSONEncoder().encode(cls)

    // 3. Write to FDB
    transaction.setValue(value, for: key)

    // 4. Update hierarchy index (if parent exists)
    if let parent = cls.parent {
        let hierarchyKey = subspaceManager.hierarchyKey(child: cls.name)
        transaction.setValue(parent.utf8Bytes, for: hierarchyKey)
    }

    // 5. Increment version counter
    let versionKey = subspaceManager.versionCounterKey()
    transaction.atomicOp(key: versionKey, param: increment(1), mutationType: .add)
}
```

### Read Operations

```swift
try await database.withTransaction { transaction in
    // 1. Check cache
    if let cached = classCache[name] {
        return cached
    }

    // 2. Read from FDB
    let key = subspaceManager.classKey(name: name)
    guard let bytes = try await transaction.getValue(for: key, snapshot: true) else {
        return nil
    }

    // 3. Deserialize
    let cls = try JSONDecoder().decode(OntologyClass.self, from: bytes)

    // 4. Update cache
    classCache[name] = cls

    return cls
}
```

## Error Handling

### Error Types

```swift
public enum OntologyError: Error, Sendable {
    case classNotFound(String)
    case predicateNotFound(String)
    case validationFailed(String)
    case circularHierarchy(String)
    case conflictingDefinition(String)
    case encodingError(String)
}
```

### Error Recovery Strategies

| Error | Strategy | Action |
|-------|----------|--------|
| `classNotFound` | Graceful degradation | Return nil or skip validation |
| `validationFailed` | Reject operation | Throw error to caller |
| `circularHierarchy` | Reject definition | Prevent cycles in class hierarchy |
| `conflictingDefinition` | Last-write-wins | Allow overwrite with version bump |

## Performance Characteristics

### Expected Performance

| Operation | Latency (p50) | Latency (p99) | Throughput |
|-----------|---------------|---------------|------------|
| Define Class | 5-10ms | 20-30ms | 500-1000 ops/sec |
| Get Class (cached) | <1ms | <5ms | 100,000+ ops/sec |
| Get Class (uncached) | 5-10ms | 20-30ms | 5,000-10,000 ops/sec |
| Validate Triple | 2-5ms | 10-20ms | 10,000-20,000 ops/sec |
| Generate Snippet | 10-20ms | 50-100ms | 1,000-2,000 ops/sec |

### Optimization Strategies

1. **Aggressive Caching**: Cache frequently accessed classes and predicates
2. **Batch Operations**: Support bulk definition/validation
3. **Snapshot Reads**: Use FDB snapshot isolation for read-only queries
4. **Lazy Loading**: Load related entities on-demand
5. **Denormalization**: Store computed hierarchy paths for fast lookups

## Scalability

### Storage Scalability

- **Vertical**: FoundationDB handles petabyte-scale data
- **Horizontal**: Ontology layer adds minimal overhead (~100-500 bytes per class/predicate)
- **Growth**: Linear with number of classes/predicates

### Query Scalability

- **Class Hierarchy Depth**: Recommend max depth of 10 levels
- **Predicate Count**: Scales to millions of predicates
- **Constraint Count**: Scales to hundreds per predicate

### Concurrent Access

- **Read Scalability**: Near-linear with cache hit rate
- **Write Scalability**: Limited by FDB transaction throughput (~10k transactions/sec)
- **Contention**: Minimal (different classes/predicates rarely conflict)

## Versioning Strategy

### Version Tracking

```
/ontology/version/<n> → {
    "version": n,
    "timestamp": "2025-10-30T10:00:00Z",
    "changes": [
        {"type": "addClass", "name": "Person"},
        {"type": "addPredicate", "name": "knows"}
    ]
}
```

### Migration Strategy

- **Backward Compatibility**: New versions don't break existing queries
- **Manual Migration**: Applications handle version upgrades
- **Snapshot Isolation**: Read operations see consistent ontology version

## Integration Points

### With fdb-triple-layer

```swift
// Triple layer validates before insert
let validator = OntologyValidator(store: ontologyStore)
if try await validator.validate(subject: s, predicate: p, object: o) {
    try await tripleStore.insert(triple)
} else {
    throw ValidationError("Triple violates ontology constraints")
}
```

### With fdb-embedding-layer

```swift
// Embedding layer uses ontology for concept metadata
let cls = try await ontologyStore.getClass(named: "Person")
let embedding = try await generateEmbedding(
    text: entity,
    metadata: ["class": cls.name, "description": cls.description]
)
```

### With fdb-knowledge-layer

```swift
// Knowledge layer uses full ontology API
let knowledge = KnowledgeStore(
    tripleStore: tripleStore,
    ontologyStore: ontologyStore,
    embeddingStore: embeddingStore
)

// Unified validation and reasoning
try await knowledge.insert(triple, validate: true, infer: true)
```

## Testing Strategy

### Unit Tests

- Model encoding/decoding
- Cache eviction logic
- Key generation correctness

### Integration Tests

- FoundationDB transaction behavior
- Multi-actor concurrent access
- Cache consistency

### Validation Tests

- Domain/range validation
- Hierarchy reasoning
- Constraint enforcement

### Performance Tests

- Throughput benchmarks
- Cache hit rate measurement
- Concurrent load testing

## Future Enhancements

### Phase 2 (Post-MVP)

1. **SPARQL-like Query Language**: Query ontology structure declaratively
2. **Constraint Solver**: Advanced constraint propagation
3. **Rule Engine**: User-defined inference rules
4. **Ontology Import**: Load OWL/RDF ontologies
5. **Schema Visualization**: Generate ontology graphs

### Phase 3 (Advanced)

1. **Distributed Reasoning**: Scale inference across cluster
2. **Probabilistic Ontology**: Handle uncertainty in definitions
3. **Temporal Ontology**: Track ontology changes over time
4. **Multi-Tenancy**: Isolate ontologies per tenant

## Security Considerations

### Access Control

- **Layer Boundary**: Ontology layer doesn't implement auth (delegate to knowledge layer)
- **Read-Only Access**: Most operations should be read-only (validation, querying)
- **Write Access**: Restrict ontology modification to admin roles

### Data Integrity

- **Validation**: All definitions validated before storage
- **Atomicity**: FoundationDB transactions ensure consistency
- **No SQL Injection**: Tuple encoding prevents injection attacks

## Monitoring and Observability

### Metrics

```swift
struct OntologyMetrics {
    var classCount: Int
    var predicateCount: Int
    var constraintCount: Int
    var cacheHitRate: Double
    var validationLatency: Histogram
    var definitionLatency: Histogram
}
```

### Logging

- **DEBUG**: Cache hits/misses, query details
- **INFO**: Definition operations, validation results
- **WARNING**: Validation failures, cache evictions
- **ERROR**: Transaction failures, encoding errors

## References

- [DATA_MODEL.md](DATA_MODEL.md) - Detailed model specifications
- [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md) - FoundationDB key structure
- [API_DESIGN.md](API_DESIGN.md) - Complete API reference
- [REASONING.md](REASONING.md) - Inference logic details
- [INTEGRATION.md](INTEGRATION.md) - Layer integration patterns

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
