import Foundation
@preconcurrency import FoundationDB
import Logging
import Synchronization

/// Primary interface for ontology management
///
/// Thread safety is provided by:
/// - Swift Synchronization.Mutex for cache access (~1μs overhead vs ~10μs for actor)
/// - FoundationDB transaction model for database operations
public final class OntologyStore: @unchecked Sendable {

    // MARK: - Properties

    nonisolated(unsafe) let database: any DatabaseProtocol
    let rootPrefix: String
    let logger: Logger

    /// Cache state protected by Mutex
    private struct CacheState {
        var classCache: [String: OntologyClass] = [:]
        var classCacheAccessOrder: [String] = []

        var predicateCache: [String: OntologyPredicate] = [:]
        var predicateCacheAccessOrder: [String] = []

        var constraintCache: [String: [OntologyConstraint]] = [:]
        var constraintCacheAccessOrder: [String] = []
    }

    private let classCacheLimit = 1000
    private let predicateCacheLimit = 5000
    private let constraintCacheLimit = 2000

    /// Mutex-protected cache state
    private let cache: Mutex<CacheState>

    // MARK: - Initialization

    public init(
        database: any DatabaseProtocol,
        rootPrefix: String,
        logger: Logger? = nil
    ) {
        self.database = database
        self.rootPrefix = rootPrefix
        self.logger = logger ?? Logger(label: "com.ontology.store")
        self.cache = Mutex(CacheState())
    }

    // MARK: - Class Management

    /// Define or update an ontology class
    public func defineClass(_ cls: OntologyClass) async throws {
        logger.debug("Defining class", metadata: [
            "name": "\(cls.name)",
            "parent": "\(cls.parent ?? "none")"
        ])

        // Validate class
        try validateClass(cls)

        // Check for circular hierarchy
        if let parent = cls.parent {
            try await checkCircularHierarchy(className: cls.name, parent: parent)
        }

        // Check if class already exists
        let existingClass = try await getClass(named: cls.name)
        let isNewClass = existingClass == nil

        try await database.withTransaction { transaction in
            // 1. Store class definition
            let classKey = TupleHelpers.encodeClassKey(
                rootPrefix: self.rootPrefix,
                className: cls.name
            )
            let classData = try JSONEncoder().encode(cls)
            let classValue = [UInt8](classData)
            transaction.setValue(classValue, for: classKey)

            // 2. Update hierarchy if parent exists
            if let parent = cls.parent {
                // Remove old reverse hierarchy index if parent changed
                if let oldParent = existingClass?.parent, oldParent != parent {
                    let oldReverseKey = TupleHelpers.encodeReverseHierarchyKey(
                        rootPrefix: self.rootPrefix,
                        parentClass: oldParent,
                        childClass: cls.name
                    )
                    transaction.clear(key: oldReverseKey)
                }

                // Forward index: child → parent
                let hierarchyKey = TupleHelpers.encodeHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    childClass: cls.name
                )
                transaction.setValue(parent.utf8Bytes, for: hierarchyKey)

                // Reverse index: parent → child
                let reverseKey = TupleHelpers.encodeReverseHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    parentClass: parent,
                    childClass: cls.name
                )
                transaction.setValue(FDB.Bytes(), for: reverseKey)
            } else if let oldParent = existingClass?.parent {
                // Parent was removed, clean up old indexes
                let hierarchyKey = TupleHelpers.encodeHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    childClass: cls.name
                )
                transaction.clear(key: hierarchyKey)

                let oldReverseKey = TupleHelpers.encodeReverseHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    parentClass: oldParent,
                    childClass: cls.name
                )
                transaction.clear(key: oldReverseKey)
            }

            // 3. Increment class count only if new
            if isNewClass {
                let countKey = TupleHelpers.encodeMetadataKey(
                    rootPrefix: self.rootPrefix,
                    key: "class_count"
                )
                let increment = TupleHelpers.encodeUInt64(1)
                transaction.atomicOp(key: countKey, param: increment, mutationType: .add)
            }

            // 4. Update last_updated timestamp
            let tsKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "last_updated"
            )
            let timestamp = Int64(Date().timeIntervalSince1970)
            transaction.setValue(TupleHelpers.encodeInt64(timestamp), for: tsKey)

            // 5. Invalidate snippet cache
            let snippetKey = TupleHelpers.encodeSnippetKey(
                rootPrefix: self.rootPrefix,
                className: cls.name
            )
            transaction.clear(key: snippetKey)
        }

        // Update cache with LRU
        updateClassCache(cls)

        logger.debug("Class defined successfully", metadata: [
            "name": "\(cls.name)"
        ])
    }

    /// Retrieve a class definition by name
    public func getClass(named name: String) async throws -> OntologyClass? {
        // Check cache (with Mutex)
        let cached = cache.withLock { state -> OntologyClass? in
            guard let cls = state.classCache[name] else {
                return nil
            }
            // Update access order
            if let index = state.classCacheAccessOrder.firstIndex(of: name) {
                state.classCacheAccessOrder.remove(at: index)
            }
            state.classCacheAccessOrder.append(name)
            return cls
        }

        if let cls = cached {
            return cls
        }

        // Read from database
        return try await database.withTransaction { transaction in
            let key = TupleHelpers.encodeClassKey(
                rootPrefix: self.rootPrefix,
                className: name
            )

            guard let bytes = try await transaction.getValue(for: key, snapshot: true) else {
                return nil
            }

            let cls = try JSONDecoder().decode(OntologyClass.self, from: Data(bytes))

            // Update cache
            self.updateClassCache(cls)

            return cls
        }
    }

    /// Retrieve all defined classes
    public func allClasses() async throws -> [OntologyClass] {
        return try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodeClassRangePrefix(rootPrefix: self.rootPrefix)
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var classes: [OntologyClass] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (_, value) in sequence {
                let cls = try JSONDecoder().decode(OntologyClass.self, from: Data(value))
                classes.append(cls)
            }

            return classes.sorted { $0.name < $1.name }
        }
    }

    /// Delete a class definition
    public func deleteClass(named name: String) async throws {
        logger.debug("Deleting class: \(name)")

        // Check if class exists
        guard let cls = try await getClass(named: name) else {
            throw OntologyError.classNotFound(name)
        }

        // Check for child classes
        let subclasses = try await getSubclasses(of: name)
        guard subclasses.isEmpty else {
            throw OntologyError.dependencyExists(
                "Class '\(name)' has subclasses: \(subclasses.joined(separator: ", "))"
            )
        }

        // Check for dependencies (predicates using this class)
        let allPredicates = try await allPredicates()
        let dependencies = allPredicates.filter {
            $0.domain == name || $0.range == name
        }
        guard dependencies.isEmpty else {
            throw OntologyError.dependencyExists(
                "Class '\(name)' is referenced by predicates: \(dependencies.map { $0.name }.joined(separator: ", "))"
            )
        }

        try await database.withTransaction { transaction in
            // 1. Remove class definition
            let classKey = TupleHelpers.encodeClassKey(
                rootPrefix: self.rootPrefix,
                className: name
            )
            transaction.clear(key: classKey)

            // 2. Remove hierarchy entries
            let hierarchyKey = TupleHelpers.encodeHierarchyKey(
                rootPrefix: self.rootPrefix,
                childClass: name
            )
            transaction.clear(key: hierarchyKey)

            // 3. Remove reverse hierarchy index (parent → this class)
            if let parent = cls.parent {
                let reverseKey = TupleHelpers.encodeReverseHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    parentClass: parent,
                    childClass: name
                )
                transaction.clear(key: reverseKey)
            }

            // 4. Decrement class count
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "class_count"
            )
            let decrementValue = UInt64(bitPattern: Int64(-1))
            let decrement = TupleHelpers.encodeUInt64(decrementValue)
            transaction.atomicOp(key: countKey, param: decrement, mutationType: .add)

            // 4. Remove snippet
            let snippetKey = TupleHelpers.encodeSnippetKey(
                rootPrefix: self.rootPrefix,
                className: name
            )
            transaction.clear(key: snippetKey)
        }

        // Remove from cache (with Mutex)
        cache.withLock { state in
            state.classCache.removeValue(forKey: name)
            if let index = state.classCacheAccessOrder.firstIndex(of: name) {
                state.classCacheAccessOrder.remove(at: index)
            }
        }

        logger.debug("Class deleted: \(name)")
    }

    /// Get all direct subclasses of a class
    public func getSubclasses(of className: String) async throws -> [String] {
        return try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodeReverseHierarchyRangePrefix(
                rootPrefix: self.rootPrefix,
                parentClass: className
            )
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var subclasses: [String] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (key, _) in sequence {
                let elements = try Tuple.decode(from: key)
                if elements.count >= 5, let childClass = elements[4] as? String {
                    subclasses.append(childClass)
                }
            }

            return subclasses
        }
    }

    /// Get all ancestor classes (full hierarchy path)
    public func getSuperclasses(of className: String) async throws -> [String] {
        return try await database.withTransaction { transaction in
            var ancestors: [String] = []
            var current = className

            while true {
                let key = TupleHelpers.encodeHierarchyKey(
                    rootPrefix: self.rootPrefix,
                    childClass: current
                )

                guard let parentBytes = try await transaction.getValue(for: key, snapshot: true) else {
                    break
                }

                let parent = parentBytes.utf8String
                ancestors.append(parent)
                current = parent
            }

            return ancestors
        }
    }

    // MARK: - Predicate Management

    /// Define or update an ontology predicate
    public func definePredicate(_ predicate: OntologyPredicate) async throws {
        logger.debug("Defining predicate: \(predicate.name)")

        // Validate predicate
        try await validatePredicate(predicate)

        // Check if predicate already exists
        let existingPredicate = try await getPredicate(named: predicate.name)
        let isNewPredicate = existingPredicate == nil

        try await database.withTransaction { transaction in
            // 1. Store predicate definition
            let predicateKey = TupleHelpers.encodePredicateKey(
                rootPrefix: self.rootPrefix,
                predicateName: predicate.name
            )
            let predicateData = try JSONEncoder().encode(predicate)
            let predicateValue = [UInt8](predicateData)
            transaction.setValue(predicateValue, for: predicateKey)

            // 2. Update domain index
            // Remove old domain index if domain changed
            if let oldDomain = existingPredicate?.domain, oldDomain != predicate.domain {
                let oldDomainIndexKey = TupleHelpers.encodePredicateByDomainKey(
                    rootPrefix: self.rootPrefix,
                    domain: oldDomain,
                    predicateName: predicate.name
                )
                transaction.clear(key: oldDomainIndexKey)
            }

            // Create new domain index
            let domainIndexKey = TupleHelpers.encodePredicateByDomainKey(
                rootPrefix: self.rootPrefix,
                domain: predicate.domain,
                predicateName: predicate.name
            )
            transaction.setValue(FDB.Bytes(), for: domainIndexKey)

            // 3. Increment predicate count only if new
            if isNewPredicate {
                let countKey = TupleHelpers.encodeMetadataKey(
                    rootPrefix: self.rootPrefix,
                    key: "predicate_count"
                )
                let increment = TupleHelpers.encodeUInt64(1)
                transaction.atomicOp(key: countKey, param: increment, mutationType: .add)
            }

            // 4. Update last_updated timestamp
            let tsKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "last_updated"
            )
            let timestamp = Int64(Date().timeIntervalSince1970)
            transaction.setValue(TupleHelpers.encodeInt64(timestamp), for: tsKey)
        }

        // Update cache with LRU
        updatePredicateCache(predicate)

        logger.debug("Predicate defined: \(predicate.name)")
    }

    /// Retrieve a predicate definition by name
    public func getPredicate(named name: String) async throws -> OntologyPredicate? {
        // Check cache (with Mutex)
        let cached = cache.withLock { state -> OntologyPredicate? in
            guard let predicate = state.predicateCache[name] else {
                return nil
            }
            // Update access order
            if let index = state.predicateCacheAccessOrder.firstIndex(of: name) {
                state.predicateCacheAccessOrder.remove(at: index)
            }
            state.predicateCacheAccessOrder.append(name)
            return predicate
        }

        if let predicate = cached {
            return predicate
        }

        // Read from database
        return try await database.withTransaction { transaction in
            let key = TupleHelpers.encodePredicateKey(
                rootPrefix: self.rootPrefix,
                predicateName: name
            )

            guard let bytes = try await transaction.getValue(for: key, snapshot: true) else {
                return nil
            }

            let predicate = try JSONDecoder().decode(OntologyPredicate.self, from: Data(bytes))

            // Update cache
            self.updatePredicateCache(predicate)

            return predicate
        }
    }

    /// Retrieve all defined predicates
    public func allPredicates() async throws -> [OntologyPredicate] {
        return try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodePredicateRangePrefix(rootPrefix: self.rootPrefix)
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var predicates: [OntologyPredicate] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (_, value) in sequence {
                let predicate = try JSONDecoder().decode(OntologyPredicate.self, from: Data(value))
                predicates.append(predicate)
            }

            return predicates.sorted { $0.name < $1.name }
        }
    }

    /// Retrieve all predicates applicable to a class
    public func getPredicatesByDomain(_ domain: String) async throws -> [OntologyPredicate] {
        return try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodePredicateByDomainRangePrefix(
                rootPrefix: self.rootPrefix,
                domain: domain
            )
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var predicates: [OntologyPredicate] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (key, _) in sequence {
                let elements = try Tuple.decode(from: key)
                if elements.count >= 5, let predicateName = elements[4] as? String {
                    if let predicate = try await self.getPredicate(named: predicateName) {
                        predicates.append(predicate)
                    }
                }
            }

            return predicates
        }
    }

    /// Delete a predicate definition
    public func deletePredicate(named name: String) async throws {
        logger.debug("Deleting predicate: \(name)")

        guard let predicate = try await getPredicate(named: name) else {
            throw OntologyError.predicateNotFound(name)
        }

        try await database.withTransaction { transaction in
            // 1. Remove predicate definition
            let predicateKey = TupleHelpers.encodePredicateKey(
                rootPrefix: self.rootPrefix,
                predicateName: name
            )
            transaction.clear(key: predicateKey)

            // 2. Remove domain index
            let domainIndexKey = TupleHelpers.encodePredicateByDomainKey(
                rootPrefix: self.rootPrefix,
                domain: predicate.domain,
                predicateName: name
            )
            transaction.clear(key: domainIndexKey)

            // 3. Decrement predicate count
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "predicate_count"
            )
            let decrementValue = UInt64(bitPattern: Int64(-1))
            let decrement = TupleHelpers.encodeUInt64(decrementValue)
            transaction.atomicOp(key: countKey, param: decrement, mutationType: .add)
        }

        // Remove from cache (with Mutex)
        cache.withLock { state in
            state.predicateCache.removeValue(forKey: name)
            if let index = state.predicateCacheAccessOrder.firstIndex(of: name) {
                state.predicateCacheAccessOrder.remove(at: index)
            }
        }

        logger.debug("Predicate deleted: \(name)")
    }

    // MARK: - Statistics

    /// Get total count of defined classes
    ///
    /// - Returns: The number of classes in the ontology
    /// - Throws: If the operation fails
    public func classCount() async throws -> Int {
        return try await database.withTransaction { transaction in
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "class_count"
            )

            guard let bytes = try await transaction.getValue(for: countKey, snapshot: true) else {
                return 0
            }

            let count = TupleHelpers.decodeUInt64(bytes)
            return Int(count)
        }
    }

    /// Get total count of defined predicates
    ///
    /// - Returns: The number of predicates in the ontology
    /// - Throws: If the operation fails
    public func predicateCount() async throws -> Int {
        return try await database.withTransaction { transaction in
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "predicate_count"
            )

            guard let bytes = try await transaction.getValue(for: countKey, snapshot: true) else {
                return 0
            }

            let count = TupleHelpers.decodeUInt64(bytes)
            return Int(count)
        }
    }

    /// Get total count of defined constraints
    ///
    /// - Returns: The number of constraints in the ontology
    /// - Throws: If the operation fails
    public func constraintCount() async throws -> Int {
        return try await database.withTransaction { transaction in
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "constraint_count"
            )

            guard let bytes = try await transaction.getValue(for: countKey, snapshot: true) else {
                return 0
            }

            let count = TupleHelpers.decodeUInt64(bytes)
            return Int(count)
        }
    }

    // MARK: - Constraint Management

    /// Define a constraint on a predicate
    public func defineConstraint(_ constraint: OntologyConstraint) async throws {
        logger.debug("Defining constraint: \(constraint.predicate) - \(constraint.constraintType)")

        // Validate constraint
        try await validateConstraint(constraint)

        try await database.withTransaction { transaction in
            // 1. Store constraint
            let constraintKey = TupleHelpers.encodeConstraintKey(
                rootPrefix: self.rootPrefix,
                predicateName: constraint.predicate,
                constraintType: constraint.constraintType.rawValue
            )
            let constraintData = try JSONEncoder().encode(constraint)
            let constraintValue = [UInt8](constraintData)
            transaction.setValue(constraintValue, for: constraintKey)

            // 2. Increment constraint count
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "constraint_count"
            )
            let increment = TupleHelpers.encodeUInt64(1)
            transaction.atomicOp(key: countKey, param: increment, mutationType: .add)
        }

        // Invalidate cache for this predicate (with Mutex)
        cache.withLock { state in
            state.constraintCache.removeValue(forKey: constraint.predicate)
            if let index = state.constraintCacheAccessOrder.firstIndex(of: constraint.predicate) {
                state.constraintCacheAccessOrder.remove(at: index)
            }
        }

        logger.debug("Constraint defined: \(constraint.predicate)")
    }

    /// Retrieve all constraints for a predicate
    public func getConstraints(for predicateName: String) async throws -> [OntologyConstraint] {
        // Check cache (with Mutex)
        let cached = cache.withLock { state -> [OntologyConstraint]? in
            guard let constraints = state.constraintCache[predicateName] else {
                return nil
            }
            // Update access order
            if let index = state.constraintCacheAccessOrder.firstIndex(of: predicateName) {
                state.constraintCacheAccessOrder.remove(at: index)
            }
            state.constraintCacheAccessOrder.append(predicateName)
            return constraints
        }

        if let constraints = cached {
            return constraints
        }

        // Read from database
        let constraints = try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodeConstraintRangePrefix(
                rootPrefix: self.rootPrefix,
                predicateName: predicateName
            )
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var constraints: [OntologyConstraint] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (_, value) in sequence {
                let constraint = try JSONDecoder().decode(OntologyConstraint.self, from: Data(value))
                constraints.append(constraint)
            }

            return constraints
        }

        // Update cache with LRU (with Mutex)
        cache.withLock { state in
            state.constraintCache[predicateName] = constraints

            // Update access order
            if let index = state.constraintCacheAccessOrder.firstIndex(of: predicateName) {
                state.constraintCacheAccessOrder.remove(at: index)
            }
            state.constraintCacheAccessOrder.append(predicateName)

            // Evict if over limit
            if state.constraintCache.count > constraintCacheLimit {
                let oldestKey = state.constraintCacheAccessOrder.removeFirst()
                state.constraintCache.removeValue(forKey: oldestKey)
            }
        }

        return constraints
    }

    /// Delete a constraint
    public func deleteConstraint(predicate: String, type: ConstraintType) async throws {
        logger.debug("Deleting constraint: \(predicate) - \(type)")

        try await database.withTransaction { transaction in
            let constraintKey = TupleHelpers.encodeConstraintKey(
                rootPrefix: self.rootPrefix,
                predicateName: predicate,
                constraintType: type.rawValue
            )
            transaction.clear(key: constraintKey)

            // Decrement constraint count
            let countKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "constraint_count"
            )
            let decrementValue = UInt64(bitPattern: Int64(-1))
            let decrement = TupleHelpers.encodeUInt64(decrementValue)
            transaction.atomicOp(key: countKey, param: decrement, mutationType: .add)
        }

        // Invalidate cache (with Mutex)
        cache.withLock { state in
            state.constraintCache.removeValue(forKey: predicate)
            if let index = state.constraintCacheAccessOrder.firstIndex(of: predicate) {
                state.constraintCacheAccessOrder.remove(at: index)
            }
        }

        logger.debug("Constraint deleted")
    }

    // MARK: - Helper Methods

    private func updateClassCache(_ cls: OntologyClass) {
        cache.withLock { state in
            let key = cls.name

            // Update or add to cache
            if state.classCache[key] != nil {
                // Already exists, update access order
                if let index = state.classCacheAccessOrder.firstIndex(of: key) {
                    state.classCacheAccessOrder.remove(at: index)
                }
                state.classCacheAccessOrder.append(key)
                state.classCache[key] = cls  // Update value
            } else {
                // New entry
                state.classCache[key] = cls
                state.classCacheAccessOrder.append(key)

                // Evict if over limit
                if state.classCache.count > classCacheLimit {
                    let oldestKey = state.classCacheAccessOrder.removeFirst()
                    state.classCache.removeValue(forKey: oldestKey)
                }
            }
        }
    }

    private func updatePredicateCache(_ predicate: OntologyPredicate) {
        cache.withLock { state in
            let key = predicate.name

            // Update or add to cache
            if state.predicateCache[key] != nil {
                // Already exists, update access order
                if let index = state.predicateCacheAccessOrder.firstIndex(of: key) {
                    state.predicateCacheAccessOrder.remove(at: index)
                }
                state.predicateCacheAccessOrder.append(key)
                state.predicateCache[key] = predicate  // Update value
            } else {
                // New entry
                state.predicateCache[key] = predicate
                state.predicateCacheAccessOrder.append(key)

                // Evict if over limit
                if state.predicateCache.count > predicateCacheLimit {
                    let oldestKey = state.predicateCacheAccessOrder.removeFirst()
                    state.predicateCache.removeValue(forKey: oldestKey)
                }
            }
        }
    }

    // MARK: - Validation Helpers

    private func validateClass(_ cls: OntologyClass) throws {
        // Name must be non-empty
        guard !cls.name.isEmpty else {
            throw OntologyError.invalidDefinition("Class name cannot be empty")
        }

        // Name must be alphanumeric (start with letter, then letters/digits/underscore)
        let namePattern = "^[A-Za-z][A-Za-z0-9_]*$"
        let nameRegex = try! NSRegularExpression(pattern: namePattern)
        let range = NSRange(location: 0, length: cls.name.utf16.count)
        guard nameRegex.firstMatch(in: cls.name, range: range) != nil else {
            throw OntologyError.invalidDefinition("Class name must be alphanumeric: \(cls.name)")
        }
    }

    private func validatePredicate(_ predicate: OntologyPredicate) async throws {
        // Name must be non-empty
        guard !predicate.name.isEmpty else {
            throw OntologyError.invalidDefinition("Predicate name cannot be empty")
        }

        // Domain must exist
        guard let _ = try await getClass(named: predicate.domain) else {
            throw OntologyError.classNotFound(predicate.domain)
        }

        // Range must exist (unless data property)
        if !predicate.isDataProperty {
            guard let _ = try await getClass(named: predicate.range) else {
                throw OntologyError.classNotFound(predicate.range)
            }
        }
    }

    private func validateConstraint(_ constraint: OntologyConstraint) async throws {
        // Predicate must exist
        guard let _ = try await getPredicate(named: constraint.predicate) else {
            throw OntologyError.predicateNotFound(constraint.predicate)
        }

        // Validate parameters based on constraint type
        switch constraint.constraintType {
        case .cardinality:
            guard constraint.parameters?["min"] != nil,
                  constraint.parameters?["max"] != nil else {
                throw OntologyError.invalidDefinition(
                    "Cardinality constraint requires 'min' and 'max' parameters"
                )
            }

        case .inverse:
            guard let inversePredicate = constraint.parameters?["inversePredicate"] else {
                throw OntologyError.invalidDefinition(
                    "Inverse constraint requires 'inversePredicate' parameter"
                )
            }
            guard let _ = try await getPredicate(named: inversePredicate) else {
                throw OntologyError.predicateNotFound(inversePredicate)
            }

        case .symmetric, .transitive, .functional, .inverseFunctional, .unique:
            // No additional parameters required
            break
        }
    }

    private func checkCircularHierarchy(className: String, parent: String) async throws {
        var visited = Set<String>()
        var current = parent

        while true {
            // Check if we've reached the original class
            if current == className {
                throw OntologyError.circularHierarchy(
                    "Class '\(className)' creates circular inheritance through '\(parent)'"
                )
            }

            // Check if we've already visited this class
            if visited.contains(current) {
                break
            }
            visited.insert(current)

            // Get parent
            guard let cls = try await getClass(named: current),
                  let nextParent = cls.parent else {
                break
            }

            current = nextParent
        }
    }
}
