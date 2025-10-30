import Foundation
@preconcurrency import FoundationDB
import Logging

extension OntologyStore {

    // MARK: - Versioning

    /// Get the current ontology version number
    public func currentVersion() async throws -> UInt64 {
        return try await database.withTransaction { transaction in
            let counterKey = TupleHelpers.encodeMetadataKey(
                rootPrefix: self.rootPrefix,
                key: "version_counter"
            )

            guard let bytes = try await transaction.getValue(for: counterKey, snapshot: true) else {
                return 0
            }

            return TupleHelpers.decodeUInt64(bytes)
        }
    }

    /// Get version metadata for a specific version
    public func getVersion(_ version: UInt64) async throws -> OntologyVersion? {
        return try await database.withTransaction { transaction in
            let versionKey = TupleHelpers.encodeVersionKey(
                rootPrefix: self.rootPrefix,
                version: version
            )

            guard let bytes = try await transaction.getValue(for: versionKey, snapshot: true) else {
                return nil
            }

            return try JSONDecoder().decode(OntologyVersion.self, from: Data(bytes))
        }
    }

    /// Get all version records
    public func allVersions() async throws -> [OntologyVersion] {
        return try await database.withTransaction { transaction in
            let prefix = TupleHelpers.encodeVersionRangePrefix(rootPrefix: self.rootPrefix)
            let (beginKey, endKey) = TupleHelpers.encodeRangeKeys(prefix: prefix)

            var versions: [OntologyVersion] = []
            let sequence = transaction.getRange(
                beginSelector: .firstGreaterOrEqual(beginKey),
                endSelector: .firstGreaterThan(endKey),
                snapshot: true
            )

            for try await (_, value) in sequence {
                let version = try JSONDecoder().decode(OntologyVersion.self, from: Data(value))
                versions.append(version)
            }

            return versions.sorted { $0.version < $1.version }
        }
    }

    // MARK: - Statistics

    /// Get ontology statistics
    public func statistics() async throws -> OntologyStatistics {
        return try await database.withTransaction { transaction in
            // Get counts
            let classCount = try await self.getMetadataCount(key: "class_count", transaction: transaction)
            let predicateCount = try await self.getMetadataCount(key: "predicate_count", transaction: transaction)
            let constraintCount = try await self.getMetadataCount(key: "constraint_count", transaction: transaction)
            let versionCount = try await self.getMetadataCount(key: "version_counter", transaction: transaction)

            // Get timestamps
            let createdAt = try await self.getMetadataTimestamp(key: "created_at", transaction: transaction)
            let lastUpdated = try await self.getMetadataTimestamp(key: "last_updated", transaction: transaction)

            return OntologyStatistics(
                classCount: classCount,
                predicateCount: predicateCount,
                constraintCount: constraintCount,
                currentVersion: versionCount,
                createdAt: createdAt,
                lastUpdated: lastUpdated
            )
        }
    }

    // MARK: - Private Helpers

    private func getMetadataCount(
        key: String,
        transaction: any TransactionProtocol
    ) async throws -> UInt64 {
        let countKey = TupleHelpers.encodeMetadataKey(
            rootPrefix: self.rootPrefix,
            key: key
        )

        guard let bytes = try await transaction.getValue(for: countKey, snapshot: true) else {
            return 0
        }

        return TupleHelpers.decodeUInt64(bytes)
    }

    private func getMetadataTimestamp(
        key: String,
        transaction: any TransactionProtocol
    ) async throws -> Date? {
        let tsKey = TupleHelpers.encodeMetadataKey(
            rootPrefix: self.rootPrefix,
            key: key
        )

        guard let bytes = try await transaction.getValue(for: tsKey, snapshot: true) else {
            return nil
        }

        let timestamp = TupleHelpers.decodeInt64(bytes)
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
