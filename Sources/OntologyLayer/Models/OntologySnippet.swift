import Foundation

/// Lightweight text representation of ontology for LLM integration
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
