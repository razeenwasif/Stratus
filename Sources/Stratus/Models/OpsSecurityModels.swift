import Foundation
import SwiftUI

enum LogSeverity: String, Sendable, Codable, CaseIterable, Hashable {
    case `default` = "DEFAULT"
    case debug = "DEBUG"
    case info = "INFO"
    case notice = "NOTICE"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    case alert = "ALERT"
    case emergency = "EMERGENCY"

    var shortLabel: String {
        switch self {
        case .default: return "LOG"
        case .debug: return "DBG"
        case .info: return "INF"
        case .notice: return "NTC"
        case .warning: return "WRN"
        case .error: return "ERR"
        case .critical: return "CRT"
        case .alert: return "ALT"
        case .emergency: return "EMG"
        }
    }

    var colorHex: String {
        switch self {
        case .default, .debug: return "#71717A"
        case .info, .notice: return "#4BC3F7"
        case .warning: return "#FBBF24"
        case .error, .critical, .alert, .emergency: return "#F87171"
        }
    }

    var isErrorOrHigher: Bool {
        switch self {
        case .error, .critical, .alert, .emergency: return true
        default: return false
        }
    }
}

enum AnyCodableValue: Sendable, Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: AnyCodableValue].self) {
            self = .object(obj)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null: try container.encodeNil()
        }
    }

    var stringSummary: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let dict):
            if let msg = dict["message"]?.stringSummary { return msg }
            if let msg = dict["msg"]?.stringSummary { return msg }
            if let err = dict["error"]?.stringSummary { return err }
            let keys = dict.keys.sorted().prefix(4)
            return keys.map { "\($0): \(dict[$0]?.stringSummary ?? "")" }.joined(separator: " · ")
        }
    }

    var prettyPrintedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return stringSummary
        }
        return str
    }
}

struct LogEntry: Identifiable, Sendable, Hashable {
    let id: String
    let insertId: String
    let timestamp: Date
    let severity: LogSeverity
    let logName: String
    let resourceType: String
    let resourceLabels: [String: String]
    let message: String
    let jsonPayload: AnyCodableValue?
}

struct IAMBinding: Identifiable, Sendable, Hashable {
    var id: String { role }
    let role: String
    let members: [String]
}

struct EnabledAPI: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let title: String
    let description: String
    let state: String

    var isEnabled: Bool {
        state.uppercased() == "ENABLED"
    }
}

enum NavSection: String, Sendable, CaseIterable, Identifiable, Hashable {
    case overview
    case compute
    case serverless
    case networkAndCI
    case storage
    case dataServices
    case monitoring
    case logging
    case iamAndApis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .compute: return "Compute & GKE"
        case .serverless: return "Serverless"
        case .networkAndCI: return "Network & CI"
        case .storage: return "Cloud Storage"
        case .dataServices: return "Data & Messaging"
        case .monitoring: return "Monitoring"
        case .logging: return "Cloud Logging"
        case .iamAndApis: return "Security & IAM"
        }
    }

    var shortTitle: String {
        switch self {
        case .overview: return "Overview"
        case .compute: return "Compute & GKE"
        case .serverless: return "Serverless"
        case .networkAndCI: return "Network & CI"
        case .storage: return "Storage"
        case .dataServices: return "Data & Pub/Sub"
        case .monitoring: return "Monitoring"
        case .logging: return "Logs"
        case .iamAndApis: return "Security & IAM"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.xyaxis.line"
        case .compute: return "cpu"
        case .serverless: return "bolt.horizontal.fill"
        case .networkAndCI: return "network"
        case .storage: return "externaldrive"
        case .dataServices: return "cylinder.split.1x2"
        case .monitoring: return "waveform.path.ecg"
        case .logging: return "text.alignleft"
        case .iamAndApis: return "lock.shield"
        }
    }

    var accentHex: String {
        switch self {
        case .overview: return "#E88255"
        case .compute: return "#E88255"
        case .serverless: return "#7A89FF"
        case .networkAndCI: return "#4BC3F7"
        case .storage: return "#4BC3F7"
        case .dataServices: return "#34D399"
        case .monitoring: return "#E88255"
        case .logging: return "#FBBF24"
        case .iamAndApis: return "#A78BFA"
        }
    }

    var shortcutDigit: String {
        switch self {
        case .overview: return "1"
        case .compute: return "2"
        case .serverless: return "3"
        case .networkAndCI: return "4"
        case .storage: return "5"
        case .dataServices: return "6"
        case .monitoring: return "7"
        case .logging: return "8"
        case .iamAndApis: return "9"
        }
    }

    enum Group: String, CaseIterable {
        case monitor = "Monitor"
        case infrastructure = "Infrastructure"
        case data = "Data & Messaging"
        case security = "Security"
    }

    var group: Group {
        switch self {
        case .overview, .monitoring, .logging: return .monitor
        case .compute, .serverless, .networkAndCI: return .infrastructure
        case .storage, .dataServices: return .data
        case .iamAndApis: return .security
        }
    }
}

enum ComputeSubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case vms
    case gke
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vms: return "Compute Engine"
        case .gke: return "GKE Clusters"
        }
    }
}

enum ServerlessSubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case cloudRun
    case functions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cloudRun: return "Cloud Run"
        case .functions: return "Cloud Functions"
        }
    }
}

enum NetworkCISubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case vpc
    case artifacts
    case builds
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vpc: return "VPC & Firewalls"
        case .artifacts: return "Artifact Registry"
        case .builds: return "Build & Scheduler"
        }
    }
}

enum DataSubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case bigQuery
    case cloudSQL
    case firestore
    case spanner
    case redis
    case pubSub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bigQuery: return "BigQuery"
        case .cloudSQL: return "Cloud SQL"
        case .firestore: return "Firestore"
        case .spanner: return "Spanner"
        case .redis: return "Memorystore"
        case .pubSub: return "Pub/Sub"
        }
    }
}

enum SecuritySubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case iam
    case apis
    case secrets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iam: return "IAM Principals"
        case .apis: return "Enabled APIs"
        case .secrets: return "Secret Manager"
        }
    }
}

enum InspectorSelection: Sendable, Hashable {
    case vm(ComputeInstance)
    case gke(GKECluster)
    case cloudRun(CloudRunService)
    case function(CloudFunctionItem)
    case firewall(FirewallRule)
    case artifactRepo(ArtifactRepo)
    case gcsObject(GCSObject, previewText: String?)
    case sql(CloudSQLInstance)
    case redis(RedisInstance)
    case secret(SecretItem)
}
