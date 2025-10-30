import Foundation
import Testing
@testable import OntologyLayer
@preconcurrency import FoundationDB

// Global FDB initialization
private nonisolated(unsafe) var globalFDBInitialized = false
private nonisolated(unsafe) var globalDatabase: FDBDatabase?
private let globalInitLock = NSLock()

// Helper to get database (non-actor)
private func getGlobalDatabase() throws -> FDBDatabase {
    globalInitLock.lock()
    defer { globalInitLock.unlock() }

    if let db = globalDatabase {
        return db
    }

    if !globalFDBInitialized {
        // Initialize FDB synchronously
        let group = DispatchGroup()
        group.enter()
        var initError: Error?

        Task {
            do {
                try await FDBClient.initialize()
            } catch {
                initError = error
            }
            group.leave()
        }

        group.wait()

        if let error = initError {
            throw error
        }

        globalFDBInitialized = true
    }

    let db = try FDBClient.openDatabase()
    globalDatabase = db
    return db
}

@Suite("OntologyStore Tests")
struct OntologyStoreTests {

    // MARK: - Helper

    func getDatabase() throws -> FDBDatabase {
        return try getGlobalDatabase()
    }

    // MARK: - Class Management Tests

    @Test("Define and retrieve class")
    func testDefineAndRetrieveClass() async throws {
        let db = try getDatabase()
        let store = OntologyStore(
            database: db,
            rootPrefix: "test_class_\(UUID().uuidString)"
        )

        // Define a class
        let entity = OntologyClass(
            name: "Entity",
            description: "Root class"
        )
        try await store.defineClass(entity)

        // Retrieve the class
        let retrieved = try await store.getClass(named: "Entity")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "Entity")
        #expect(retrieved?.description == "Root class")
    }

    @Test("Define class with parent")
    func testDefineClassWithParent() async throws {
        let db = try getDatabase()
        let store = OntologyStore(
            database: db,
            rootPrefix: "test_parent_\(UUID().uuidString)"
        )

        // Define parent class
        let entity = OntologyClass(name: "Entity", description: "Root class")
        try await store.defineClass(entity)

        // Define child class
        let person = OntologyClass(
            name: "Person",
            parent: "Entity",
            description: "A human being"
        )
        try await store.defineClass(person)

        // Retrieve and verify hierarchy
        let retrieved = try await store.getClass(named: "Person")
        #expect(retrieved?.parent == "Entity")

        let superclasses = try await store.getSuperclasses(of: "Person")
        #expect(superclasses == ["Entity"])
    }

    @Test("Get all classes")
    func testGetAllClasses() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_all_\(UUID().uuidString)"
        )

        // Define multiple classes
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.defineClass(OntologyClass(name: "Organization"))

        // Retrieve all classes
        let allClasses = try await store.allClasses()
        #expect(allClasses.count == 3)
        #expect(allClasses.map { $0.name }.sorted() == ["Entity", "Organization", "Person"])
    }

    @Test("Detect circular hierarchy")
    func testCircularHierarchy() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_circular_\(UUID().uuidString)"
        )

        // Define class A with parent B
        try await store.defineClass(OntologyClass(name: "A", parent: "B"))
        try await store.defineClass(OntologyClass(name: "B", parent: "C"))

        // Try to create circular dependency: C → A
        let classC = OntologyClass(name: "C", parent: "A")

        await #expect(throws: OntologyError.self) {
            try await store.defineClass(classC)
        }
    }

    // MARK: - Predicate Management Tests

    @Test("Define and retrieve predicate")
    func testDefineAndRetrievePredicate() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_predicate_\(UUID().uuidString)"
        )

        // Define classes first
        try await store.defineClass(OntologyClass(name: "Person"))

        // Define predicate
        let knows = OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person",
            description: "A person knows another person"
        )
        try await store.definePredicate(knows)

        // Retrieve predicate
        let retrieved = try await store.getPredicate(named: "knows")
        #expect(retrieved != nil)
        #expect(retrieved?.domain == "Person")
        #expect(retrieved?.range == "Person")
    }

    @Test("Get predicates by domain")
    func testGetPredicatesByDomain() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_domain_\(UUID().uuidString)"
        )

        // Define classes
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.defineClass(OntologyClass(name: "Organization"))

        // Define predicates
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))
        try await store.definePredicate(OntologyPredicate(
            name: "worksFor",
            domain: "Person",
            range: "Organization"
        ))
        try await store.definePredicate(OntologyPredicate(
            name: "founded",
            domain: "Organization",
            range: "Person"
        ))

        // Get predicates for Person
        let personPredicates = try await store.getPredicatesByDomain("Person")
        #expect(personPredicates.count == 2)
        #expect(Set(personPredicates.map { $0.name }) == ["knows", "worksFor"])
    }

    // MARK: - Constraint Tests

    @Test("Define and retrieve constraint")
    func testDefineAndRetrieveConstraint() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_constraint_\(UUID().uuidString)"
        )

        // Setup
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))

        // Define constraint
        let symmetric = OntologyConstraint(
            predicate: "knows",
            constraintType: .symmetric,
            description: "If A knows B, then B knows A"
        )
        try await store.defineConstraint(symmetric)

        // Retrieve constraints
        let constraints = try await store.getConstraints(for: "knows")
        #expect(constraints.count == 1)
        #expect(constraints[0].constraintType == .symmetric)
    }

    // MARK: - Validation Tests

    @Test("Validate triple against ontology")
    func testValidateTriple() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_validate_\(UUID().uuidString)"
        )

        // Setup ontology
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))

        // Validate
        let validator = OntologyValidator(store: store)
        let result = try await validator.validate(
            (subject: "Person", predicate: "knows", object: "Person")
        )

        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("Detect domain mismatch")
    func testDomainMismatch() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_mismatch_\(UUID().uuidString)"
        )

        // Setup ontology
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.defineClass(OntologyClass(name: "Organization"))
        try await store.definePredicate(OntologyPredicate(
            name: "worksFor",
            domain: "Person",
            range: "Organization"
        ))

        // Validate with wrong domain
        let validator = OntologyValidator(store: store)
        let result = try await validator.validate(
            (subject: "Organization", predicate: "worksFor", object: "Organization")
        )

        #expect(!result.isValid)
        #expect(result.errors.contains { $0.errorType == ValidationError.ErrorType.domainMismatch })
    }

    // MARK: - Reasoning Tests

    @Test("Check subsumption")
    func testSubsumption() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_subsumption_\(UUID().uuidString)"
        )

        // Setup hierarchy: Employee → Person → Entity
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(name: "Person", parent: "Entity"))
        try await store.defineClass(OntologyClass(name: "Employee", parent: "Person"))

        // Test subsumption
        let reasoner = OntologyReasoner(store: store)

        #expect(try await reasoner.isSubclassOf("Employee", of: "Person"))
        #expect(try await reasoner.isSubclassOf("Employee", of: "Entity"))
        #expect(try await reasoner.isSubclassOf("Person", of: "Entity"))
        #expect(!(try await reasoner.isSubclassOf("Person", of: "Employee")))
    }

    @Test("Infer symmetric triple")
    func testSymmetricInference() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_symmetric_\(UUID().uuidString)"
        )

        // Setup
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))
        try await store.defineConstraint(OntologyConstraint(
            predicate: "knows",
            constraintType: .symmetric
        ))

        // Infer symmetric
        let reasoner = OntologyReasoner(store: store)
        let reversed = try await reasoner.inferSymmetric(
            (subject: "Alice", predicate: "knows", object: "Bob")
        )

        #expect(reversed != nil)
        #expect(reversed?.subject == "Bob")
        #expect(reversed?.object == "Alice")
    }

    // MARK: - Snippet Tests

    @Test("Generate snippet")
    func testGenerateSnippet() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_snippet_\(UUID().uuidString)"
        )

        // Setup
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(
            name: "Person",
            parent: "Entity",
            description: "A human being"
        ))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person",
            description: "A person knows another person"
        ))

        // Generate snippet
        let snippet = try await store.snippet(for: "Person")

        #expect(snippet.contains("Class: Person"))
        #expect(snippet.contains("Inherits from: Entity"))
        #expect(snippet.contains("A human being"))
        #expect(snippet.contains("knows"))
    }

    // MARK: - Update Logic Tests

    @Test("Update class doesn't duplicate counter")
    func testUpdateClassCounter() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_update_class_\(UUID().uuidString)"
        )

        // Define class
        try await store.defineClass(OntologyClass(name: "Person"))

        // Get initial count
        let stats1 = try await store.statistics()
        #expect(stats1.classCount == 1)

        // Update the same class
        try await store.defineClass(OntologyClass(name: "Person", description: "Updated"))

        // Count should still be 1
        let stats2 = try await store.statistics()
        #expect(stats2.classCount == 1)
    }

    @Test("Update class parent removes old reverse index")
    func testUpdateClassParent() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_update_parent_\(UUID().uuidString)"
        )

        // Setup hierarchy: Entity
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.defineClass(OntologyClass(name: "Manager"))

        // Employee → Person
        try await store.defineClass(OntologyClass(name: "Employee", parent: "Person"))

        // Check Person has Employee as subclass
        let subclasses1 = try await store.getSubclasses(of: "Person")
        #expect(subclasses1.contains("Employee"))

        // Change parent: Employee → Manager
        try await store.defineClass(OntologyClass(name: "Employee", parent: "Manager"))

        // Check Person no longer has Employee as subclass
        let subclasses2 = try await store.getSubclasses(of: "Person")
        #expect(!subclasses2.contains("Employee"))

        // Check Manager now has Employee
        let subclasses3 = try await store.getSubclasses(of: "Manager")
        #expect(subclasses3.contains("Employee"))
    }

    @Test("Cannot delete class with subclasses")
    func testDeleteClassWithChildren() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_delete_parent_\(UUID().uuidString)"
        )

        // Setup hierarchy
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(name: "Person", parent: "Entity"))

        // Try to delete parent class
        await #expect(throws: OntologyError.self) {
            try await store.deleteClass(named: "Entity")
        }
    }

    @Test("Update predicate doesn't duplicate counter")
    func testUpdatePredicateCounter() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_update_predicate_\(UUID().uuidString)"
        )

        // Define classes and predicate
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))

        // Get initial count
        let stats1 = try await store.statistics()
        #expect(stats1.predicateCount == 1)

        // Update the same predicate
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person",
            description: "Updated"
        ))

        // Count should still be 1
        let stats2 = try await store.statistics()
        #expect(stats2.predicateCount == 1)
    }

    // MARK: - Statistics Tests

    @Test("Get statistics")
    func testStatistics() async throws {
        let store = OntologyStore(
            database: try getDatabase(),
            rootPrefix: "test_stats_\(UUID().uuidString)"
        )

        // Setup
        try await store.defineClass(OntologyClass(name: "Entity"))
        try await store.defineClass(OntologyClass(name: "Person"))
        try await store.definePredicate(OntologyPredicate(
            name: "knows",
            domain: "Person",
            range: "Person"
        ))

        // Get statistics
        let stats = try await store.statistics()

        #expect(stats.classCount == 2)
        #expect(stats.predicateCount == 1)
        #expect(stats.constraintCount == 0)
    }
}
