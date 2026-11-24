import Foundation

struct GCSBucket: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let location: String
    let storageClass: String
    let timeCreated: Date?
    let versioningEnabled: Bool
    let estimatedSizeBytes: Int64
    let objectCount: Int
}

struct GCSObject: Identifiable, Sendable, Hashable {
    var id: String { "\(bucket)/\(name)" }
    let name: String
    let bucket: String
    let sizeBytes: Int64
    let contentType: String
    let updated: Date?
    let isPrefix: Bool

    var displayName: String {
        if isPrefix {
            let trimmed = name.hasSuffix("/") ? String(name.dropLast()) : name
            return trimmed.split(separator: "/").last.map { String($0) + "/" } ?? name
        }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    var isPreviewableText: Bool {
        if isPrefix { return false }
        let lower = name.lowercased()
        let ct = contentType.lowercased()
        return ct.hasPrefix("text/")
            || ct.contains("json")
            || ct.contains("yaml")
            || ct.contains("xml")
            || ct.contains("javascript")
            || lower.hasSuffix(".json")
            || lower.hasSuffix(".yaml")
            || lower.hasSuffix(".yml")
            || lower.hasSuffix(".log")
            || lower.hasSuffix(".txt")
            || lower.hasSuffix(".md")
            || lower.hasSuffix(".csv")
            || lower.hasSuffix(".sql")
            || lower.hasSuffix(".tf")
            || lower.hasSuffix(".env")
    }
}

struct BQDataset: Identifiable, Sendable, Hashable {
    var id: String { datasetId }
    let datasetId: String
    let location: String
    let friendlyName: String?
    let creationTime: Date?
}

struct BQTable: Identifiable, Sendable, Hashable {
    var id: String { "\(datasetId).\(tableId)" }
    let tableId: String
    let datasetId: String
    let type: String
    let numRows: Int64
    let numBytes: Int64
    let lastModified: Date?
}

struct BQQueryResult: Sendable, Hashable {
    let columns: [String]
    let rows: [[String]]
    let totalBytesProcessed: Int64
    let durationMs: Int
    let jobComplete: Bool
}

struct CloudSQLInstance: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let databaseVersion: String
    let region: String
    let state: String
    let tier: String
    let ipAddress: String?
    let storageSizeGb: Int
    let availabilityType: String
    let estimatedMonthlyCost: Double

    var isRunnable: Bool {
        state.uppercased() == "RUNNABLE"
    }
}

struct SecretItem: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let shortName: String
    let createTime: Date?
    let replicationPolicy: String
    let labels: [String: String]
}

struct SecretVersion: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let versionNumber: String
    let state: String
    let createTime: Date?
}
