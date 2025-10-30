import Foundation
@preconcurrency import FoundationDB

/// Helper functions for encoding/decoding FoundationDB keys using Tuple encoding
enum TupleHelpers {

    // MARK: - Class Keys

    /// Encode a class key: (rootPrefix, "ontology", "class", <className>)
    static func encodeClassKey(rootPrefix: String, className: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "class", className).encode()
    }

    /// Encode a class range key prefix for scanning all classes
    static func encodeClassRangePrefix(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "class").encode()
    }

    // MARK: - Predicate Keys

    /// Encode a predicate key: (rootPrefix, "ontology", "predicate", <predicateName>)
    static func encodePredicateKey(rootPrefix: String, predicateName: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "predicate", predicateName).encode()
    }

    /// Encode a predicate by domain index key
    static func encodePredicateByDomainKey(
        rootPrefix: String,
        domain: String,
        predicateName: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "predicate_by_domain", domain, predicateName).encode()
    }

    /// Encode predicate range prefix for scanning all predicates
    static func encodePredicateRangePrefix(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "predicate").encode()
    }

    /// Encode predicate by domain range prefix
    static func encodePredicateByDomainRangePrefix(
        rootPrefix: String,
        domain: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "predicate_by_domain", domain).encode()
    }

    // MARK: - Constraint Keys

    /// Encode a constraint key: (rootPrefix, "ontology", "constraint", <predicateName>, <constraintType>)
    static func encodeConstraintKey(
        rootPrefix: String,
        predicateName: String,
        constraintType: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "constraint", predicateName, constraintType).encode()
    }

    /// Encode constraint range prefix for a predicate
    static func encodeConstraintRangePrefix(
        rootPrefix: String,
        predicateName: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "constraint", predicateName).encode()
    }

    // MARK: - Hierarchy Keys

    /// Encode hierarchy key (child → parent): (rootPrefix, "ontology", "hierarchy", <childClass>)
    static func encodeHierarchyKey(rootPrefix: String, childClass: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "hierarchy", childClass).encode()
    }

    /// Encode reverse hierarchy key (parent → children): (rootPrefix, "ontology", "reverse_hierarchy", <parentClass>, <childClass>)
    static func encodeReverseHierarchyKey(
        rootPrefix: String,
        parentClass: String,
        childClass: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "reverse_hierarchy", parentClass, childClass).encode()
    }

    /// Encode reverse hierarchy range prefix
    static func encodeReverseHierarchyRangePrefix(
        rootPrefix: String,
        parentClass: String
    ) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "reverse_hierarchy", parentClass).encode()
    }

    // MARK: - Version Keys

    /// Encode version key: (rootPrefix, "ontology", "version", <versionNumber>)
    static func encodeVersionKey(rootPrefix: String, version: UInt64) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "version", version).encode()
    }

    /// Encode version range prefix
    static func encodeVersionRangePrefix(rootPrefix: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "version").encode()
    }

    // MARK: - Snippet Keys

    /// Encode snippet key: (rootPrefix, "ontology", "snippet", <className>)
    static func encodeSnippetKey(rootPrefix: String, className: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "snippet", className).encode()
    }

    /// Encode snippet timestamp key
    static func encodeSnippetTimestampKey(rootPrefix: String, className: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "snippet_ts", className).encode()
    }

    // MARK: - Metadata Keys

    /// Encode metadata key: (rootPrefix, "ontology", "metadata", <key>)
    static func encodeMetadataKey(rootPrefix: String, key: String) -> FDB.Bytes {
        return Tuple(rootPrefix, "ontology", "metadata", key).encode()
    }

    // MARK: - Range Query Helpers

    /// Create begin and end keys for range query
    static func encodeRangeKeys(prefix: FDB.Bytes) -> (beginKey: FDB.Bytes, endKey: FDB.Bytes) {
        let beginKey = prefix
        let endKey = prefix + [0xFF]
        return (beginKey, endKey)
    }

    // MARK: - Value Encoding/Decoding

    /// Encode UInt64 as little-endian bytes
    static func encodeUInt64(_ value: UInt64) -> FDB.Bytes {
        return withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    /// Decode UInt64 from little-endian bytes
    static func decodeUInt64(_ bytes: FDB.Bytes) -> UInt64 {
        return bytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }

    /// Encode Int64 as little-endian bytes
    static func encodeInt64(_ value: Int64) -> FDB.Bytes {
        return withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    /// Decode Int64 from little-endian bytes
    static func decodeInt64(_ bytes: FDB.Bytes) -> Int64 {
        return bytes.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
    }

    /// Convert String to UTF-8 bytes
    static func stringToBytes(_ string: String) -> FDB.Bytes {
        return [UInt8](string.utf8)
    }

    /// Convert UTF-8 bytes to String
    static func bytesToString(_ bytes: FDB.Bytes) -> String {
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - FDB.Bytes Extensions

extension FDB.Bytes {
    /// Computed property to easily convert to String
    var utf8String: String {
        TupleHelpers.bytesToString(self)
    }
}

extension String {
    /// Computed property to easily convert to FDB.Bytes
    var utf8Bytes: FDB.Bytes {
        TupleHelpers.stringToBytes(self)
    }
}
