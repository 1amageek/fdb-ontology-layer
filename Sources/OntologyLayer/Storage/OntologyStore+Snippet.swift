import Foundation
@preconcurrency import FoundationDB
import Logging

extension OntologyStore {

    // MARK: - Snippet Generation

    /// Generate a lightweight ontology representation for LLM prompts
    public func snippet(for className: String) async throws -> String {
        logger.debug("Generating snippet for class: \(className)")

        // Check cache first
        if let cached = try await getCachedSnippet(for: className) {
            return cached
        }

        // Generate new snippet
        let snippet = try await generateSnippet(for: className, includeSubclasses: false)
        let text = snippet.render()

        // Cache the snippet
        try await cacheSnippet(text, for: className)

        return text
    }

    /// Generate an extended snippet including subclass information
    public func fullSnippet(
        for className: String,
        includeSubclasses: Bool = false
    ) async throws -> String {
        logger.debug("Generating full snippet for class: \(className)")

        let snippet = try await generateSnippet(for: className, includeSubclasses: includeSubclasses)
        return snippet.render()
    }

    // MARK: - Private Snippet Helpers

    private func generateSnippet(
        for className: String,
        includeSubclasses: Bool
    ) async throws -> OntologySnippet {
        // Get class definition
        guard let cls = try await getClass(named: className) else {
            throw OntologyError.classNotFound(className)
        }

        // Get predicates for this class
        let predicates = try await getPredicatesByDomain(className)
        var predicateDescriptions: [String: String] = [:]

        for predicate in predicates {
            predicateDescriptions[predicate.name] = predicate.description ?? "No description"
        }

        // Get examples (if defined in class properties metadata)
        var examples: [String]? = nil
        if let examplesStr = cls.metadata?["examples"] {
            examples = examplesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        var snippet = OntologySnippet(
            className: cls.name,
            description: cls.description ?? "No description",
            parent: cls.parent,
            predicates: predicateDescriptions,
            examples: examples
        )

        return snippet
    }

    private func getCachedSnippet(for className: String) async throws -> String? {
        return try await database.withTransaction { transaction in
            let snippetKey = TupleHelpers.encodeSnippetKey(
                rootPrefix: self.rootPrefix,
                className: className
            )

            guard let snippetBytes = try await transaction.getValue(for: snippetKey, snapshot: true) else {
                return nil
            }

            // Check timestamp (TTL: 1 hour)
            let tsKey = TupleHelpers.encodeSnippetTimestampKey(
                rootPrefix: self.rootPrefix,
                className: className
            )

            if let tsBytes = try await transaction.getValue(for: tsKey, snapshot: true) {
                let storedTs = TupleHelpers.decodeInt64(tsBytes)
                let age = Date().timeIntervalSince1970 - Double(storedTs)

                if age < 3600 {
                    // Cache is fresh
                    return snippetBytes.utf8String
                }
            }

            return nil
        }
    }

    private func cacheSnippet(_ text: String, for className: String) async throws {
        try await database.withTransaction { transaction in
            // Store snippet
            let snippetKey = TupleHelpers.encodeSnippetKey(
                rootPrefix: self.rootPrefix,
                className: className
            )
            transaction.setValue(text.utf8Bytes, for: snippetKey)

            // Store timestamp
            let tsKey = TupleHelpers.encodeSnippetTimestampKey(
                rootPrefix: self.rootPrefix,
                className: className
            )
            let timestamp = Int64(Date().timeIntervalSince1970)
            transaction.setValue(TupleHelpers.encodeInt64(timestamp), for: tsKey)
        }
    }
}
