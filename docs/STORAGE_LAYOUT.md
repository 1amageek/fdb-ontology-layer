# fdb-ontology-layer Storage Layout

## Overview

This document defines the FoundationDB key-value layout used by `fdb-ontology-layer`. The design prioritizes:
- **Efficient range queries** using Tuple encoding
- **Namespace isolation** using subspaces
- **Atomic operations** for counters and versions
- **Minimal key size** to stay within FDB's 10KB limit

## Subspace Hierarchy

All ontology data is stored under a configurable root prefix:

```
<rootPrefix>/
  ontology/
    class/              → OntologyClass definitions
    predicate/          → OntologyPredicate definitions
    constraint/         → OntologyConstraint definitions
    hierarchy/          → Class hierarchy index
    reverse_hierarchy/  → Reverse hierarchy index (children lookup)
    version/            → Version tracking
    snippet/            → Cached LLM snippets
    metadata/           → System metadata (counters, etc.)
```

## Key Encoding

All keys use FoundationDB's Tuple encoding for:
- **Lexicographic ordering**: Enables efficient range queries
- **Type safety**: Preserves data types in keys
- **Compatibility**: Standard encoding across FDB layers

### Tuple Encoding Rules

```swift
// Example: Class key
Tuple("ontology", "class", "Person").encode()
// → [rootPrefix] + [0x02] + "ontology" + [0x00] + [0x02] + "class" + [0x00] + [0x02] + "Person" + [0x00]

// Example: Hierarchy key
Tuple("ontology", "hierarchy", "Employee").encode()
// → [rootPrefix] + [0x02] + "ontology" + [0x00] + [0x02] + "hierarchy" + [0x00] + [0x02] + "Employee" + [0x00]
```

## Detailed Key Structures

### 1. Class Storage

**Purpose**: Store OntologyClass definitions

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "class", <className>)` | JSON-encoded OntologyClass | Class definition |

**Example**:
```
Key:   (rootPrefix, "ontology", "class", "Person")
Value: {"name":"Person","parent":"Entity","description":"A human being",...}
```

**Operations**:
```swift
// Define class
let key = Tuple(rootPrefix, "ontology", "class", cls.name).encode()
let value = try JSONEncoder().encode(cls)
transaction.setValue(value, for: key)

// Get class
let key = Tuple(rootPrefix, "ontology", "class", "Person").encode()
let bytes = try await transaction.getValue(for: key)
let cls = try JSONDecoder().decode(OntologyClass.self, from: bytes)

// List all classes (range query)
let beginKey = Tuple(rootPrefix, "ontology", "class", "").encode()
let endKey = Tuple(rootPrefix, "ontology", "class", "\u{FFFF}").encode()
for try await (key, value) in transaction.getRange(beginSelector: .firstGreaterOrEqual(beginKey),
                                                    endSelector: .firstGreaterThan(endKey)) {
    // Parse each class
}
```

### 2. Predicate Storage

**Purpose**: Store OntologyPredicate definitions

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "predicate", <predicateName>)` | JSON-encoded OntologyPredicate | Predicate definition |

**Example**:
```
Key:   (rootPrefix, "ontology", "predicate", "knows")
Value: {"name":"knows","domain":"Person","range":"Person","isDataProperty":false,...}
```

**Index by Domain** (for validation):
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "predicate_by_domain", <domain>, <predicateName>)` | Empty | Index for domain lookup |

**Example**:
```
Key:   (rootPrefix, "ontology", "predicate_by_domain", "Person", "knows")
Value: (empty)

Key:   (rootPrefix, "ontology", "predicate_by_domain", "Person", "worksFor")
Value: (empty)
```

**Operations**:
```swift
// Define predicate with index
let key = Tuple(rootPrefix, "ontology", "predicate", pred.name).encode()
let value = try JSONEncoder().encode(pred)
transaction.setValue(value, for: key)

// Create domain index
let indexKey = Tuple(rootPrefix, "ontology", "predicate_by_domain", pred.domain, pred.name).encode()
transaction.setValue(FDB.Bytes(), for: indexKey)

// Query predicates by domain
let beginKey = Tuple(rootPrefix, "ontology", "predicate_by_domain", "Person", "").encode()
let endKey = Tuple(rootPrefix, "ontology", "predicate_by_domain", "Person", "\u{FFFF}").encode()
for try await (key, _) in transaction.getRange(...) {
    let elements = try Tuple.decode(from: key)
    let predicateName = elements[4] as! String  // Extract predicate name
    // Load full predicate definition
}
```

### 3. Constraint Storage

**Purpose**: Store OntologyConstraint definitions

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "constraint", <predicateName>, <constraintType>)` | JSON-encoded OntologyConstraint | Constraint definition |

**Example**:
```
Key:   (rootPrefix, "ontology", "constraint", "knows", "symmetric")
Value: {"predicate":"knows","constraintType":"symmetric",...}

Key:   (rootPrefix, "ontology", "constraint", "birthDate", "functional")
Value: {"predicate":"birthDate","constraintType":"functional",...}
```

**Operations**:
```swift
// Define constraint
let key = Tuple(rootPrefix, "ontology", "constraint", constraint.predicate, constraint.constraintType.rawValue).encode()
let value = try JSONEncoder().encode(constraint)
transaction.setValue(value, for: key)

// Get all constraints for a predicate
let beginKey = Tuple(rootPrefix, "ontology", "constraint", "knows", "").encode()
let endKey = Tuple(rootPrefix, "ontology", "constraint", "knows", "\u{FFFF}").encode()
for try await (key, value) in transaction.getRange(...) {
    let constraint = try JSONDecoder().decode(OntologyConstraint.self, from: value)
}
```

### 4. Hierarchy Storage

**Purpose**: Enable efficient ancestor/descendant queries

**Forward Index (Child → Parent)**:
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "hierarchy", <childClass>)` | Parent class name (String bytes) | Direct parent |

**Example**:
```
Key:   (rootPrefix, "ontology", "hierarchy", "Person")
Value: "Entity"

Key:   (rootPrefix, "ontology", "hierarchy", "Employee")
Value: "Person"
```

**Reverse Index (Parent → Children)**:
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "reverse_hierarchy", <parentClass>, <childClass>)` | Empty | Child set |

**Example**:
```
Key:   (rootPrefix, "ontology", "reverse_hierarchy", "Entity", "Person")
Value: (empty)

Key:   (rootPrefix, "ontology", "reverse_hierarchy", "Entity", "Organization")
Value: (empty)

Key:   (rootPrefix, "ontology", "reverse_hierarchy", "Person", "Employee")
Value: (empty)
```

**Operations**:
```swift
// Get parent class
let key = Tuple(rootPrefix, "ontology", "hierarchy", "Employee").encode()
let parentBytes = try await transaction.getValue(for: key)
let parent = String(decoding: parentBytes, as: UTF8.self)  // "Person"

// Get all children of a class
let beginKey = Tuple(rootPrefix, "ontology", "reverse_hierarchy", "Entity", "").encode()
let endKey = Tuple(rootPrefix, "ontology", "reverse_hierarchy", "Entity", "\u{FFFF}").encode()
var children: [String] = []
for try await (key, _) in transaction.getRange(...) {
    let elements = try Tuple.decode(from: key)
    let child = elements[4] as! String
    children.append(child)
}
// children = ["Person", "Organization", ...]
```

**Ancestor Path Cache** (optional optimization):
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "ancestor_path", <className>)` | JSON array of ancestors | Full path to root |

**Example**:
```
Key:   (rootPrefix, "ontology", "ancestor_path", "Employee")
Value: ["Person", "Entity"]  // JSON-encoded array
```

### 5. Version Tracking

**Purpose**: Track ontology changes over time

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "version", <versionNumber>)` | JSON-encoded OntologyVersion | Version metadata |

**Example**:
```
Key:   (rootPrefix, "ontology", "version", 1)
Value: {"version":1,"timestamp":"2025-10-30T10:00:00Z","changes":[...],"comment":"Initial setup"}

Key:   (rootPrefix, "ontology", "version", 2)
Value: {"version":2,"timestamp":"2025-10-30T11:00:00Z","changes":[...],"comment":"Added Person class"}
```

**Version Counter** (atomic):
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "metadata", "version_counter")` | UInt64 (8 bytes, little-endian) | Current version number |

**Operations**:
```swift
// Increment version atomically
let counterKey = Tuple(rootPrefix, "ontology", "metadata", "version_counter").encode()
let increment = withUnsafeBytes(of: UInt64(1).littleEndian) { Array($0) }
transaction.atomicOp(key: counterKey, param: increment, mutationType: .add)

// Get current version
let bytes = try await transaction.getValue(for: counterKey)
let version = bytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }

// Store version record
let versionKey = Tuple(rootPrefix, "ontology", "version", version).encode()
let versionData = try JSONEncoder().encode(versionRecord)
transaction.setValue(versionData, for: versionKey)
```

### 6. Snippet Cache

**Purpose**: Cache pre-generated LLM snippets

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "snippet", <className>)` | UTF-8 encoded snippet text | Cached snippet |

**Example**:
```
Key:   (rootPrefix, "ontology", "snippet", "Person")
Value: "Class: Person\nInherits from: Entity\nDescription: A human being\n\nPredicates:\n  - name: The person's full name\n..."
```

**Expiration** (using TTL):
| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "snippet_ts", <className>)` | Unix timestamp (Int64) | Last updated time |

**Operations**:
```swift
// Store snippet with timestamp
let snippetKey = Tuple(rootPrefix, "ontology", "snippet", cls.name).encode()
transaction.setValue(snippetText.utf8Bytes, for: snippetKey)

let tsKey = Tuple(rootPrefix, "ontology", "snippet_ts", cls.name).encode()
let timestamp = Int64(Date().timeIntervalSince1970)
let tsBytes = withUnsafeBytes(of: timestamp.littleEndian) { Array($0) }
transaction.setValue(tsBytes, for: tsKey)

// Check if snippet is fresh (< 1 hour old)
let tsBytes = try await transaction.getValue(for: tsKey)
let storedTs = tsBytes.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
let age = Date().timeIntervalSince1970 - Double(storedTs)
if age < 3600 {
    // Use cached snippet
} else {
    // Regenerate snippet
}
```

### 7. Metadata

**Purpose**: Store system-wide metadata and counters

| Key | Value | Description |
|-----|-------|-------------|
| `Tuple(rootPrefix, "ontology", "metadata", "version_counter")` | UInt64 | Version number counter |
| `Tuple(rootPrefix, "ontology", "metadata", "class_count")` | UInt64 | Total number of classes |
| `Tuple(rootPrefix, "ontology", "metadata", "predicate_count")` | UInt64 | Total number of predicates |
| `Tuple(rootPrefix, "ontology", "metadata", "constraint_count")` | UInt64 | Total number of constraints |
| `Tuple(rootPrefix, "ontology", "metadata", "created_at")` | Int64 (Unix timestamp) | Ontology creation time |
| `Tuple(rootPrefix, "ontology", "metadata", "last_updated")` | Int64 (Unix timestamp) | Last modification time |

**Operations**:
```swift
// Increment class count atomically
let key = Tuple(rootPrefix, "ontology", "metadata", "class_count").encode()
let increment = withUnsafeBytes(of: UInt64(1).littleEndian) { Array($0) }
transaction.atomicOp(key: key, param: increment, mutationType: .add)

// Update last_updated timestamp
let key = Tuple(rootPrefix, "ontology", "metadata", "last_updated").encode()
let timestamp = Int64(Date().timeIntervalSince1970)
let bytes = withUnsafeBytes(of: timestamp.littleEndian) { Array($0) }
transaction.setValue(bytes, for: key)
```

## Storage Efficiency

### Key Size Analysis

| Key Type | Average Size | Max Size | Notes |
|----------|--------------|----------|-------|
| Class key | ~50 bytes | ~200 bytes | `rootPrefix` (20) + "ontology/class/" (20) + class name (10-100) |
| Predicate key | ~60 bytes | ~250 bytes | Similar to class key |
| Constraint key | ~80 bytes | ~300 bytes | Includes constraint type |
| Hierarchy key | ~50 bytes | ~200 bytes | Child class name |
| Version key | ~40 bytes | ~50 bytes | Fixed-size version number |

All keys are well within FDB's 10KB limit.

### Value Size Analysis

| Value Type | Average Size | Max Size | Notes |
|------------|--------------|----------|-------|
| OntologyClass | 500 bytes | 10 KB | Limit enforced at API level |
| OntologyPredicate | 300 bytes | 5 KB | Smaller than classes |
| OntologyConstraint | 200 bytes | 2 KB | Minimal data |
| OntologyVersion | 2 KB | 50 KB | Can have many changes |
| Snippet | 5 KB | 50 KB | Pre-rendered text |

All values are within FDB's 100KB value limit.

### Storage Scalability

**Example: 1000 classes, 5000 predicates, 500 constraints**

| Component | Count | Avg Size | Total Size |
|-----------|-------|----------|------------|
| Classes | 1,000 | 500 bytes | 500 KB |
| Predicates | 5,000 | 300 bytes | 1.5 MB |
| Predicate indexes | 5,000 | 100 bytes | 500 KB |
| Constraints | 500 | 200 bytes | 100 KB |
| Hierarchy | 1,000 | 50 bytes | 50 KB |
| Reverse hierarchy | 1,000 | 50 bytes | 50 KB |
| Snippets | 1,000 | 5 KB | 5 MB |
| Metadata | 10 | 50 bytes | 500 bytes |
| **Total** | | | **~7.7 MB** |

Storage is minimal and scales linearly with ontology size.

## Transaction Patterns

### 1. Define Class (Write)

```swift
try await database.withTransaction { transaction in
    // 1. Store class definition
    let classKey = Tuple(rootPrefix, "ontology", "class", cls.name).encode()
    let classValue = try JSONEncoder().encode(cls)
    transaction.setValue(classValue, for: classKey)

    // 2. Update hierarchy if parent exists
    if let parent = cls.parent {
        let hierarchyKey = Tuple(rootPrefix, "ontology", "hierarchy", cls.name).encode()
        transaction.setValue(parent.utf8Bytes, for: hierarchyKey)

        let reverseKey = Tuple(rootPrefix, "ontology", "reverse_hierarchy", parent, cls.name).encode()
        transaction.setValue(FDB.Bytes(), for: reverseKey)
    }

    // 3. Increment class count
    let countKey = Tuple(rootPrefix, "ontology", "metadata", "class_count").encode()
    let increment = withUnsafeBytes(of: UInt64(1).littleEndian) { Array($0) }
    transaction.atomicOp(key: countKey, param: increment, mutationType: .add)

    // 4. Update last_updated timestamp
    let tsKey = Tuple(rootPrefix, "ontology", "metadata", "last_updated").encode()
    let timestamp = Int64(Date().timeIntervalSince1970)
    transaction.setValue(withUnsafeBytes(of: timestamp.littleEndian) { Array($0) }, for: tsKey)

    // 5. Invalidate snippet cache
    let snippetKey = Tuple(rootPrefix, "ontology", "snippet", cls.name).encode()
    transaction.clear(key: snippetKey)
}
```

### 2. Get Class (Read)

```swift
try await database.withTransaction { transaction in
    let key = Tuple(rootPrefix, "ontology", "class", name).encode()
    guard let bytes = try await transaction.getValue(for: key, snapshot: true) else {
        return nil
    }
    return try JSONDecoder().decode(OntologyClass.self, from: bytes)
}
```

### 3. List Classes (Range Query)

```swift
try await database.withTransaction { transaction in
    let beginKey = Tuple(rootPrefix, "ontology", "class", "").encode()
    let endKey = Tuple(rootPrefix, "ontology", "class", "\u{FFFF}").encode()

    var classes: [OntologyClass] = []
    let sequence = transaction.getRange(
        beginSelector: .firstGreaterOrEqual(beginKey),
        endSelector: .firstGreaterThan(endKey),
        snapshot: true
    )

    for try await (_, value) in sequence {
        let cls = try JSONDecoder().decode(OntologyClass.self, from: value)
        classes.append(cls)
    }

    return classes
}
```

### 4. Get Class Hierarchy (Multi-Read)

```swift
func getAncestors(of className: String) async throws -> [String] {
    return try await database.withTransaction { transaction in
        var ancestors: [String] = []
        var current = className

        while true {
            let key = Tuple(rootPrefix, "ontology", "hierarchy", current).encode()
            guard let parentBytes = try await transaction.getValue(for: key, snapshot: true) else {
                break
            }
            let parent = String(decoding: parentBytes, as: UTF8.self)
            ancestors.append(parent)
            current = parent
        }

        return ancestors
    }
}
```

## Backup and Recovery

### Snapshot Strategy

1. **Full Snapshot**: Export all keys under `<rootPrefix>/ontology/`
2. **Incremental**: Export version records since last snapshot

```bash
# FDB backup (full ontology)
fdbbackup start -d "file:///backups/ontology-$(date +%Y%m%d)"
```

### Recovery Process

1. Restore FoundationDB from backup
2. Verify ontology integrity
3. Rebuild caches (snippets, hierarchy paths)

## Performance Considerations

### Read Performance

| Operation | Latency | Caching Impact |
|-----------|---------|----------------|
| Get class (cached) | <1ms | 100x faster |
| Get class (uncached) | 5-10ms | - |
| List all classes | 50-100ms | Snapshot isolation |
| Get ancestors | 10-50ms | Linear with depth |

### Write Performance

| Operation | Latency | Notes |
|-----------|---------|-------|
| Define class | 10-20ms | Includes hierarchy updates |
| Define predicate | 5-10ms | Includes domain index |
| Delete class | 20-50ms | Must clean up hierarchy and predicates |

### Cache Hit Rate

Expected cache hit rates:
- **Classes**: 90-95% (stable definitions)
- **Predicates**: 85-90% (frequently used)
- **Constraints**: 80-85% (validation queries)

## References

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [DATA_MODEL.md](DATA_MODEL.md) - Data model specifications
- [API_DESIGN.md](API_DESIGN.md) - API design
- [FoundationDB Documentation](https://apple.github.io/foundationdb/)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Status**: Draft
