# fdb-ontology-layer Integration Guide

## Overview

This document describes how `fdb-ontology-layer` integrates with other layers in the knowledge management stack. The ontology layer serves as the semantic foundation for all other layers, providing type checking, validation, and basic reasoning capabilities.

## Layer Architecture

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

## Integration Patterns

### 1. Integration with fdb-triple-layer

The triple layer stores raw triples. The ontology layer provides semantic validation before insertion.

#### Pattern 1: Validation Before Insert

```swift
import TripleLayer
import OntologyLayer

actor ValidatedTripleStore {
    private let tripleStore: TripleStore
    private let ontologyStore: OntologyStore
    private let validator: OntologyValidator

    init(database: any DatabaseProtocol, rootPrefix: String) async throws {
        self.tripleStore = try await TripleStore(database: database, rootPrefix: rootPrefix)
        self.ontologyStore = OntologyStore(database: database, rootPrefix: rootPrefix)
        self.validator = OntologyValidator(store: ontologyStore)
    }

    func insert(_ triple: Triple) async throws {
        // 1. Extract subject/object types from triple metadata or infer from URIs
        let subjectType = extractType(from: triple.subject)
        let objectType = extractType(from: triple.object)
        let predicateName = extractPredicateName(from: triple.predicate)

        // 2. Validate against ontology
        let result = try await validator.validate(
            (subject: subjectType, predicate: predicateName, object: objectType)
        )

        guard result.isValid else {
            throw TripleError.validationFailed("Triple violates ontology: \(result.errors)")
        }

        // 3. Insert if valid
        try await tripleStore.insert(triple)
    }

    private func extractType(from value: Value) -> String {
        // Extract type from URI or metadata
        // Example: "http://example.org/person/Alice" → "Person"
        switch value {
        case .uri(let uri):
            // Parse URI to determine type
            if uri.contains("/person/") {
                return "Person"
            } else if uri.contains("/org/") {
                return "Organization"
            }
            return "Entity"
        case .text, .integer, .float, .boolean, .binary:
            return "Literal"
        }
    }

    private func extractPredicateName(from value: Value) -> String {
        // Extract predicate name from URI
        // Example: "http://xmlns.com/foaf/0.1/knows" → "knows"
        guard case .uri(let uri) = value else {
            return ""
        }
        return uri.components(separatedBy: "/").last ?? ""
    }
}
```

**Usage**:
```swift
let store = try await ValidatedTripleStore(database: database, rootPrefix: "myapp")

let triple = Triple(
    subject: .uri("http://example.org/person/Alice"),
    predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
    object: .uri("http://example.org/person/Bob")
)

try await store.insert(triple)  // Validates before inserting
```

#### Pattern 2: Optional Validation (Performance Mode)

```swift
actor OptionalValidationStore {
    private let tripleStore: TripleStore
    private let validator: OntologyValidator?

    func insert(_ triple: Triple, validate: Bool = true) async throws {
        if validate, let validator = self.validator {
            // Perform validation
            let result = try await validator.validate(...)
            guard result.isValid else {
                throw TripleError.validationFailed(...)
            }
        }

        // Insert without validation in performance mode
        try await tripleStore.insert(triple)
    }
}
```

#### Pattern 3: Batch Validation

```swift
actor BatchValidationStore {
    func insertBatch(_ triples: [Triple], validate: Bool = true) async throws {
        if validate {
            // Extract types from all triples
            let typedTriples = triples.map { triple in
                (
                    subject: extractType(from: triple.subject),
                    predicate: extractPredicateName(from: triple.predicate),
                    object: extractType(from: triple.object)
                )
            }

            // Batch validation (more efficient)
            let results = try await validator.validateBatch(typedTriples)

            // Check all results
            let invalid = results.enumerated().filter { !$0.element.isValid }
            guard invalid.isEmpty else {
                throw TripleError.validationFailed("Batch contains invalid triples: \(invalid.map { $0.offset })")
            }
        }

        // Insert all triples
        try await tripleStore.insertBatch(triples)
    }
}
```

---

### 2. Integration with fdb-embedding-layer

The embedding layer stores vector embeddings. The ontology layer provides semantic metadata for embeddings.

#### Pattern 1: Ontology-Enriched Embeddings

```swift
import EmbeddingLayer
import OntologyLayer

actor SemanticEmbeddingStore {
    private let embeddingStore: EmbeddingStore
    private let ontologyStore: OntologyStore

    func storeEmbedding(
        entity: String,
        vector: [Float],
        entityType: String
    ) async throws {
        // 1. Get ontology metadata for entity type
        guard let cls = try await ontologyStore.getClass(named: entityType) else {
            throw OntologyError.classNotFound(entityType)
        }

        // 2. Enrich metadata with ontology info
        var metadata = EmbeddingMetadata()
        metadata["class"] = cls.name
        metadata["description"] = cls.description
        metadata["parent"] = cls.parent

        // 3. Store embedding with enriched metadata
        try await embeddingStore.store(
            id: entity,
            vector: vector,
            metadata: metadata
        )
    }

    func similarEntities(
        to query: [Float],
        ofType entityType: String?,
        limit: Int = 10
    ) async throws -> [SimilarityResult] {
        // 1. If type filter specified, include subclasses
        var typeFilter: [String]? = nil
        if let entityType = entityType {
            let subclasses = try await ontologyStore.getSubclasses(of: entityType)
            typeFilter = [entityType] + subclasses
        }

        // 2. Query with type filter
        return try await embeddingStore.similarTo(
            query: query,
            filter: { metadata in
                guard let typeFilter = typeFilter else { return true }
                guard let cls = metadata["class"] as? String else { return false }
                return typeFilter.contains(cls)
            },
            limit: limit
        )
    }
}
```

**Usage**:
```swift
let store = SemanticEmbeddingStore(...)

// Store embedding with ontology metadata
try await store.storeEmbedding(
    entity: "Alice",
    vector: [0.1, 0.2, ...],
    entityType: "Person"
)

// Query with type hierarchy
let results = try await store.similarEntities(
    to: queryVector,
    ofType: "Person",  // Includes Employee, Student, etc.
    limit: 10
)
```

#### Pattern 2: Ontology-Guided Embedding Generation

```swift
actor OntologyGuidedEmbedding {
    func generateEmbedding(
        for entity: String,
        type: String
    ) async throws -> [Float] {
        // 1. Get ontology snippet for context
        let snippet = try await ontologyStore.snippet(for: type)

        // 2. Construct enriched prompt
        let prompt = """
        Entity: \(entity)
        Type: \(type)

        Ontology Context:
        \(snippet)

        Generate embedding that captures the semantic role of this entity within the ontology.
        """

        // 3. Generate embedding with LLM/embedding model
        return try await llm.generateEmbedding(prompt: prompt)
    }
}
```

---

### 3. Integration with fdb-knowledge-layer

The knowledge layer provides a unified API over all other layers. It uses ontology for reasoning and validation.

#### Pattern 1: Unified Knowledge API

```swift
import KnowledgeLayer
import TripleLayer
import OntologyLayer
import EmbeddingLayer

public actor KnowledgeStore {
    private let tripleStore: TripleStore
    private let ontologyStore: OntologyStore
    private let embeddingStore: EmbeddingStore
    private let validator: OntologyValidator
    private let reasoner: OntologyReasoner

    public func insert(
        _ triple: Triple,
        validate: Bool = true,
        infer: Bool = false
    ) async throws {
        // 1. Validate against ontology
        if validate {
            let result = try await validator.validate(...)
            guard result.isValid else {
                throw ValidationError(...)
            }
        }

        // 2. Insert triple
        try await tripleStore.insert(triple)

        // 3. Apply reasoning if requested
        if infer {
            let inferred = try await reasoner.inferTriples(from: triple)
            for inferredTriple in inferred {
                try await tripleStore.insert(inferredTriple)
            }
        }

        // 4. Update embeddings
        try await updateEmbeddings(for: triple)
    }

    public func query(
        pattern: TriplePattern,
        inferredTypes: Bool = true
    ) async throws -> [Triple] {
        // 1. Query triples
        var results = try await tripleStore.query(
            subject: pattern.subject,
            predicate: pattern.predicate,
            object: pattern.object
        )

        // 2. Expand with inferred types if requested
        if inferredTypes, let subjectType = pattern.subjectType {
            let subclasses = try await reasoner.getSubclasses(of: subjectType)
            for subclass in subclasses {
                let subResults = try await tripleStore.query(
                    subject: pattern.subject,  // Keep same pattern
                    predicate: pattern.predicate,
                    object: pattern.object
                )
                results.append(contentsOf: subResults)
            }
        }

        return results
    }

    private func updateEmbeddings(for triple: Triple) async throws {
        // Generate and store embeddings for entities in the triple
        // (Implementation depends on embedding strategy)
    }
}
```

#### Pattern 2: Semantic Search with Ontology

```swift
public actor SemanticKnowledgeSearch {
    public func search(
        query: String,
        entityType: String? = nil,
        useOntology: Bool = true
    ) async throws -> [SearchResult] {
        // 1. Generate query embedding
        let queryEmbedding = try await generateEmbedding(for: query)

        // 2. Get ontology context if type specified
        var typeContext = ""
        if useOntology, let entityType = entityType {
            typeContext = try await ontologyStore.snippet(for: entityType)
        }

        // 3. Search embeddings with type filter
        let embeddingResults = try await embeddingStore.similarTo(
            query: queryEmbedding,
            filter: { metadata in
                guard let entityType = entityType else { return true }
                return metadata["class"] as? String == entityType
            },
            limit: 100
        )

        // 4. Retrieve triples for matched entities
        var results: [SearchResult] = []
        for embResult in embeddingResults {
            let triples = try await tripleStore.query(
                subject: .uri(embResult.id),
                predicate: nil,
                object: nil
            )
            results.append(SearchResult(
                entity: embResult.id,
                score: embResult.score,
                triples: triples,
                metadata: embResult.metadata
            ))
        }

        // 5. Re-rank using ontology similarity
        if useOntology {
            results = try await rerankByOntology(results, queryType: entityType)
        }

        return results
    }

    private func rerankByOntology(
        _ results: [SearchResult],
        queryType: String?
    ) async throws -> [SearchResult] {
        // Boost results that match the expected ontology type
        guard let queryType = queryType else { return results }

        return results.sorted { r1, r2 in
            let t1Match = r1.metadata["class"] as? String == queryType
            let t2Match = r2.metadata["class"] as? String == queryType

            if t1Match != t2Match {
                return t1Match  // Prefer type matches
            }
            return r1.score > r2.score  // Otherwise sort by embedding score
        }
    }
}
```

---

## Integration Best Practices

### 1. Lazy Validation

Validate only when necessary to avoid performance overhead:

```swift
// ✓ Good: Validate user input
let userTriple = parseUserInput()
try await validator.validate(userTriple)

// ✗ Bad: Validate trusted internal data
let inferredTriple = reasoner.infer(...)
try await validator.validate(inferredTriple)  // Redundant
```

### 2. Cache Ontology Data

Frequently accessed ontology data should be cached:

```swift
actor CachedOntologyClient {
    private var classCache: [String: OntologyClass] = [:]

    func getClass(_ name: String) async throws -> OntologyClass? {
        if let cached = classCache[name] {
            return cached
        }

        let cls = try await ontologyStore.getClass(named: name)
        if let cls = cls {
            classCache[name] = cls
        }
        return cls
    }
}
```

### 3. Batch Operations

Always use batch operations for multiple entities:

```swift
// ✗ Bad: Individual operations
for triple in triples {
    try await validator.validate(triple)
    try await tripleStore.insert(triple)
}

// ✓ Good: Batch operations
let results = try await validator.validateBatch(triples)
let valid = triples.enumerated().filter { results[$0.offset].isValid }.map { $0.element }
try await tripleStore.insertBatch(valid)
```

### 4. Graceful Degradation

Handle missing ontology gracefully:

```swift
func insert(_ triple: Triple) async throws {
    do {
        let result = try await validator.validate(triple)
        if !result.isValid {
            logger.warning("Triple validation failed: \(result.errors)")
            // Decide: throw error or insert anyway
        }
    } catch {
        logger.warning("Ontology validation unavailable: \(error)")
        // Continue without validation
    }

    try await tripleStore.insert(triple)
}
```

### 5. Ontology Versioning

Track ontology versions for reproducibility:

```swift
struct KnowledgeRecord: Codable {
    let triple: Triple
    let ontologyVersion: UInt64  // Capture ontology version at insertion time
    let timestamp: Date
}

func insert(_ triple: Triple) async throws {
    let version = try await ontologyStore.currentVersion()

    let record = KnowledgeRecord(
        triple: triple,
        ontologyVersion: version,
        timestamp: Date()
    )

    try await store.insert(record)
}
```

---

## Data Flow Examples

### Example 1: Insert with Full Validation

```
User Input (Triple)
    │
    ▼
Parse & Extract Types
    │
    ▼
OntologyValidator.validate()
    │
    ├─► OntologyStore.getPredicate()
    ├─► OntologyStore.getClass() (domain)
    ├─► OntologyStore.getClass() (range)
    ├─► OntologyStore.getConstraints()
    │
    ▼
Validation Result
    │
    ├─► Valid? → TripleStore.insert()
    └─► Invalid? → Throw ValidationError
```

### Example 2: Semantic Search

```
User Query (text)
    │
    ▼
Generate Embedding
    │
    ▼
EmbeddingStore.similarTo()
    │
    ├─► Filter by ontology type (optional)
    │   └─► OntologyStore.getSubclasses()
    │
    ▼
Matched Entities
    │
    ▼
TripleStore.query() (for each entity)
    │
    ▼
Re-rank by Ontology
    │
    └─► OntologyReasoner.isSubclassOf()
    │
    ▼
Ranked Results
```

### Example 3: Inference and Storage

```
Insert Triple(A, knows, B)
    │
    ▼
TripleStore.insert()
    │
    ▼
OntologyReasoner.inferTriples()
    │
    ├─► Check symmetric constraint
    │   └─► OntologyStore.getConstraints("knows")
    │
    ├─► Infer Triple(B, knows, A)
    │
    ▼
TripleStore.insert(inferred triples)
```

---

## Testing Integration

### Mock Ontology Store

```swift
actor MockOntologyStore: OntologyStore {
    var classes: [String: OntologyClass] = [:]
    var predicates: [String: OntologyPredicate] = [:]

    func defineClass(_ cls: OntologyClass) async throws {
        classes[cls.name] = cls
    }

    func getClass(named name: String) async throws -> OntologyClass? {
        return classes[name]
    }

    // ... implement other methods
}

// Usage in tests
let mockStore = MockOntologyStore()
let testClass = OntologyClass(name: "TestClass")
try await mockStore.defineClass(testClass)

let validator = OntologyValidator(store: mockStore)
let result = try await validator.validate(...)
```

### Integration Test Example

```swift
import Testing
@testable import TripleLayer
@testable import OntologyLayer

@Test("Triple insertion with ontology validation")
func testValidatedInsertion() async throws {
    let db = try FDBClient.openDatabase()

    // 1. Setup ontology
    let ontologyStore = OntologyStore(database: db, rootPrefix: "test")
    try await ontologyStore.defineClass(OntologyClass(name: "Person"))
    try await ontologyStore.definePredicate(OntologyPredicate(
        name: "knows",
        domain: "Person",
        range: "Person"
    ))

    // 2. Create validated triple store
    let store = try await ValidatedTripleStore(database: db, rootPrefix: "test")

    // 3. Insert valid triple
    let validTriple = Triple(
        subject: .uri("http://example.org/person/Alice"),
        predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
        object: .uri("http://example.org/person/Bob")
    )
    try await store.insert(validTriple)

    // 4. Verify insertion
    let results = try await store.query(subject: validTriple.subject)
    #expect(results.count == 1)

    // 5. Try invalid triple (should fail)
    let invalidTriple = Triple(
        subject: .uri("http://example.org/person/Alice"),
        predicate: .uri("http://xmlns.com/foaf/0.1/knows"),
        object: .uri("http://example.org/org/Acme")  // Wrong type!
    )
    await #expect(throws: TripleError.self) {
        try await store.insert(invalidTriple)
    }
}
```

---

## References

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [API_DESIGN.md](API_DESIGN.md) - API specifications
- [fdb-triple-layer Documentation](../../fdb-triple-layer/README.md)
- [fdb-embedding-layer Documentation](../../fdb-embedding-layer/README.md)
- [fdb-knowledge-layer Documentation](../../fdb-knowledge-layer/README.md)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
